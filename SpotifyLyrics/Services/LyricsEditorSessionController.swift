import Combine
import Foundation

public enum LyricsEditorSessionState: Equatable, Sendable {
    case idle
    case unavailable(String)
    case loading
    case editing
    case importPreview
    case saving
    case saved
    case stale
    case failed(String)

    public var userFacingMessage: String {
        switch self {
        case .idle: return ""
        case .unavailable(let message): return message
        case .loading: return "正在加载歌词版本…"
        case .editing: return ""
        case .importPreview: return "请确认 LRC 导入预览"
        case .saving: return "正在保存人工版本…"
        case .saved: return "已保存人工版本"
        case .stale: return "当前 Spotify 已切歌，编辑会话仍绑定原歌曲"
        case .failed(let message): return "保存失败：\(message)"
        }
    }
}

public struct LyricsEditorImportPreview: Equatable, Sendable {
    public let result: LRCImportResult
    public let document: LyricsDocument
    public let match: LRCImportMatchReport

    public init(result: LRCImportResult, document: LyricsDocument, match: LRCImportMatchReport) {
        self.result = result
        self.document = document
        self.match = match
    }
}

/// Shared, main-actor editing state for the independent editor window.
///
/// The editor never writes SQL itself. It keeps a value-type draft, performs
/// optimistic local validation, and hands a compare-and-save request to the
/// repository. A PlaybackState callback supplies the final track/revision
/// guard so an old editor cannot save into a newly playing song.
@MainActor
public final class LyricsEditorSessionController: ObservableObject {
    @Published public private(set) var state: LyricsEditorSessionState = .idle
    @Published public private(set) var draft: LyricsEditorDraft?
    @Published public private(set) var availableVersions: [StoredEditableLyricsVersion] = []
    @Published public private(set) var availableTranslations: [StoredTranslationVersion] = []
    @Published public private(set) var selectedTranslation: StoredTranslationVersion?
    @Published public private(set) var validation = LyricsTimelineValidationResult(issues: [], isSynchronized: false)
    @Published public private(set) var pendingImport: LyricsEditorImportPreview?
    @Published public private(set) var pendingTextImport: TextLyricsImportResult?
    @Published public private(set) var message: String?
    @Published public private(set) var isStale = false
    /// Assist: line IDs that currently hold unconfirmed auto-suggestions.
    @Published public private(set) var assistSuggestedLineIDs: Set<UUID> = []
    /// Assist: auto-advance to next untimed line after mark (user-toggleable).
    @Published public var assistAutoAdvance = true
    /// Callback for partial-save confirmation. Return true to proceed.
    public var confirmPartialSave: ((Int, Int) -> Bool)?

    public var onSaved: ((LyricsEditSaveResult, TrackIdentity) -> Void)?
    public var isStillCurrent: (() -> Bool)?

    private let repository: (any LyricsEditingRepository)?
    private var loadTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var generation: UInt64 = 0
    private var track: Track?
    private var identity: TrackIdentity?
    private var sourceVersionID: UUID?
    private var sourceContentHash: String?
    private var isNewSourceSession = false
    private var newSourceKind: LyricsSource = .manualCreate
    private var pendingTextImportSource: LyricsSource = .manualCreate
    private var sourceRevision: UInt64 = 0
    private var translationConfiguration = AITranslationConfiguration()
    private var baseLyricsLines: [LyricsEditorLineDraft] = []
    private var baseTranslationLines: [String] = []
    private var lockedReadingIDs: Set<UUID> = []
    private var baseLockedReadingIDs: Set<UUID> = []

    public init(repository: (any LyricsEditingRepository)?) {
        self.repository = repository
    }

    deinit {
        loadTask?.cancel()
        saveTask?.cancel()
    }

    public var canSave: Bool {
        draft != nil && !isStale && state != .saving && validation.isSaveAllowed
    }

    public var hasUnsavedChanges: Bool {
        draft?.isDirty == true || pendingImport != nil || pendingTextImport != nil
    }

    public var currentIdentity: TrackIdentity? { identity }
    public var currentSourceVersionID: UUID? { sourceVersionID }
    public var currentSourceContentHash: String? { sourceContentHash }
    public var currentSourceRevision: UInt64 { sourceRevision }

    public func reportExportResult(_ message: String) {
        self.message = message
    }

    public func updateSourceRevision(_ revision: UInt64) {
        sourceRevision = revision
        isStale = false
        if state == .stale { state = .saved }
    }

    public func markStale() {
        isStale = true
        state = .stale
    }

    public func begin(
        track: Track,
        identity: TrackIdentity,
        document: LyricsDocument,
        lyricsVersionID: UUID,
        sourceContentHash: String,
        revision: UInt64,
        translations: [StoredTranslationVersion],
        selectedTranslation: StoredTranslationVersion?,
        configuration: AITranslationConfiguration
    ) {
        generation &+= 1
        loadTask?.cancel()
        saveTask?.cancel()
        self.track = track
        self.identity = identity
        self.sourceVersionID = lyricsVersionID
        self.sourceContentHash = sourceContentHash
        self.sourceRevision = revision
        self.translationConfiguration = configuration
        self.availableTranslations = translations
        self.selectedTranslation = selectedTranslation
        self.pendingImport = nil
        self.pendingTextImport = nil
        self.isNewSourceSession = false
        self.newSourceKind = .manualCreate
        self.pendingTextImportSource = .manualCreate
        self.message = nil
        self.isStale = false
        self.assistSuggestedLineIDs = []

        let displayDocument = Self.documentByProjecting(
            selectedTranslation,
            onto: document
        )
        let newDraft = LyricsEditorDraft(
            document: displayDocument,
            sourceVersionID: lyricsVersionID,
            sourceContentHash: sourceContentHash
        )
        self.draft = newDraft
        self.baseLyricsLines = newDraft.lines.map(Self.lyricsProjection)
        self.baseTranslationLines = newDraft.lines.map(Self.translationText)
        self.lockedReadingIDs = []
        self.baseLockedReadingIDs = []
        self.validation = LyricsTimelineValidator.validate(lines: newDraft.lines, duration: newDraft.duration)
        self.state = .editing

        guard let repository else {
            state = .unavailable("当前歌词仓库不支持编辑")
            return
        }

        let loadGeneration = generation
        loadTask = Task { [weak self, repository] in
            do {
                let versions = try await repository.loadEditableVersions(track: track, identity: identity)
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    guard let self,
                          self.generation == loadGeneration,
                          self.identity == identity,
                          self.sourceVersionID == lyricsVersionID else { return }
                    self.availableVersions = versions
                    if let selected = versions.first(where: { $0.record.id == lyricsVersionID }) {
                        self.lockedReadingIDs = Set(selected.lockedReadingLayers.compactMap { layer in
                            guard self.draft?.lines.indices.contains(layer.lineIndex) == true else { return nil }
                            return self.draft?.lines[layer.lineIndex].id
                        })
                        self.baseLockedReadingIDs = self.lockedReadingIDs
                        self.message = selected.record.isLocked ? "当前来源版本已锁定；保存将创建新的人工版本" : nil
                    }
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self, self.generation == loadGeneration else { return }
                    self.message = "版本读取失败：\(error.localizedDescription)"
                }
            }
        }
    }

    /// Starts a fresh manual/import session without inventing a provider
    /// parent. The editor still uses the same draft, validation, save and
    /// lock path as edits to an existing Provider version.
    public func beginNew(
        track: Track,
        identity: TrackIdentity,
        document: LyricsDocument,
        source: LyricsSource,
        revision: UInt64,
        configuration: AITranslationConfiguration
    ) {
        generation &+= 1
        loadTask?.cancel()
        saveTask?.cancel()
        self.track = track
        self.identity = identity
        let newSourceVersionID = UUID()
        self.sourceVersionID = newSourceVersionID
        self.sourceContentHash = LyricsPersistenceMapper.sourceContentHash(document: document)
        self.sourceRevision = revision
        self.translationConfiguration = configuration
        self.availableVersions = []
        self.availableTranslations = []
        self.selectedTranslation = nil
        self.pendingImport = nil
        self.pendingTextImport = nil
        self.message = nil
        self.isStale = false
        self.isNewSourceSession = true
        self.newSourceKind = source
        self.pendingTextImportSource = source

        let enriched = LyricsDocument(
            identity: document.identity,
            title: document.title,
            artist: document.artist,
            album: document.album,
            duration: document.duration,
            lines: LyricsLayerEnricher.enrich(lines: document.lines),
            isSynchronized: false,
            source: source,
            confidence: document.confidence,
            providerSourceID: nil,
            spotifyTrackID: identity.spotifyTrackID,
            isrc: identity.isrc
        )
        let newDraft = LyricsEditorDraft(
            document: enriched,
            sourceVersionID: newSourceVersionID,
            sourceContentHash: LyricsPersistenceMapper.sourceContentHash(document: enriched)
        )
        self.sourceContentHash = LyricsPersistenceMapper.sourceContentHash(document: enriched)
        self.draft = newDraft
        self.baseLyricsLines = newDraft.lines.map(Self.lyricsProjection)
        self.baseTranslationLines = newDraft.lines.map(Self.translationText)
        self.lockedReadingIDs = []
        self.baseLockedReadingIDs = []
        self.assistSuggestedLineIDs = []
        self.validation = LyricsTimelineValidator.validate(lines: newDraft.lines, duration: newDraft.duration)
        self.state = .editing
    }

    public func close() {
        generation &+= 1
        loadTask?.cancel()
        saveTask?.cancel()
        pendingImport = nil
        pendingTextImport = nil
        draft = nil
        availableVersions = []
        availableTranslations = []
        selectedTranslation = nil
        identity = nil
        track = nil
        sourceVersionID = nil
        sourceContentHash = nil
        isNewSourceSession = false
        newSourceKind = .manualCreate
        pendingTextImportSource = .manualCreate
        lockedReadingIDs = []
        baseLockedReadingIDs = []
        assistSuggestedLineIDs = []
        state = .idle
        message = nil
        isStale = false
    }

    /// Called when Spotify changes tracks. The window remains bound to its
    /// original identity, but saving is disabled until it is reopened.
    public func observePlayback(identity currentIdentity: TrackIdentity?, revision: UInt64) {
        guard let identity else { return }
        guard let editorIdentity = self.identity else { return }
        if editorIdentity != identity || revision != sourceRevision {
            isStale = true
            state = .stale
        }
    }

#if DEBUG
    /// Apply Assist candidate times into the open draft (suggested, not confirmed).
    /// Does not write SQLite. Each timed suggestion is one undo frame (last undo
    /// restores the pre-apply draft after undoing each apply step, or user may
    /// use multiple undos).
    public func applyAssistedDraft(_ assist: AssistedAlignmentDraft) {
        guard !isStale, draft != nil else {
            message = "请先打开可编辑的纯文本歌词版本"
            return
        }
        guard let lineCount = draft?.lines.count,
              assist.plainLineCount == lineCount || assist.lines.count == lineCount else {
            message = "建议行数与当前歌词不一致，已忽略"
            return
        }
        var suggested = Set<UUID>()
        for suggestion in assist.lines {
            guard suggestion.status == .suggested, let start = suggestion.suggestedStartTime else { continue }
            guard let id = draft?.lines.indices.contains(suggestion.lyricLineIndex) == true
                    ? draft?.lines[suggestion.lyricLineIndex].id
                    : nil else { continue }
            updateLine(id) { line in
                line.startTime = start
                line.endTime = suggestion.suggestedEndTime
            }
            suggested.insert(id)
        }
        assistSuggestedLineIDs = suggested
        let timed = draft?.timedNonBlankLineCount ?? 0
        let untimed = draft?.untimedNonBlankLineCount ?? 0
        message = "已载入 \(timed) 条建议时间，\(untimed) 行仍未排。确认前不会写入正式版本。"
        state = .editing
    }

    public func clearAssistSuggestions() {
        assistSuggestedLineIDs = []
    }

    /// Mark line at playback position; returns next focus line id if auto-advance.
    public func markLineAtPlayback(lineID: UUID, position: TimeInterval, advance: Bool) -> UUID? {
        guard !isStale else { return nil }
        updateLine(lineID) { line in
            line.startTime = position
            if let end = line.endTime, end < position { line.endTime = nil }
        }
        assistSuggestedLineIDs.remove(lineID)
        guard advance || assistAutoAdvance else { return nil }
        return draft?.nextUntimedLineID(after: lineID)
    }
#endif

    public func updateLine(_ lineID: UUID, _ change: (inout LyricsEditorLineDraft) -> Void) {
        guard !isStale, var draft else { return }
        do {
            try draft.update(lineID, change)
            self.draft = draft
            validate(draft)
        } catch {
            message = error.localizedDescription
        }
    }

    public func split(lineID: UUID, at offset: Int) {
        guard var draft else { return }
        do {
            try draft.split(lineID: lineID, at: offset)
            lockedReadingIDs.remove(lineID)
            self.draft = draft
            validate(draft)
        } catch { message = error.localizedDescription }
    }

    public func merge(lineID: UUID, with nextID: UUID) {
        guard var draft else { return }
        do {
            try draft.merge(lineID: lineID, with: nextID)
            lockedReadingIDs.remove(lineID)
            lockedReadingIDs.remove(nextID)
            self.draft = draft
            validate(draft)
        } catch { message = error.localizedDescription }
    }

    public func insertBlank(after lineID: UUID?) {
        guard var draft else { return }
        draft.insertBlank(after: lineID)
        self.draft = draft
        validate(draft)
    }

    public func delete(lineID: UUID) {
        guard var draft else { return }
        do {
            try draft.delete(lineID: lineID)
            lockedReadingIDs.remove(lineID)
            self.draft = draft
            validate(draft)
        } catch { message = error.localizedDescription }
    }

    public func move(lineID: UUID, offset: Int) {
        guard var draft else { return }
        draft.move(lineID: lineID, offset: offset)
        self.draft = draft
        validate(draft)
    }

    public func undo() {
        guard var draft else { return }
        do { try draft.undo(); self.draft = draft; validate(draft) }
        catch { message = error.localizedDescription }
    }

    public func redo() {
        guard var draft else { return }
        do { try draft.redo(); self.draft = draft; validate(draft) }
        catch { message = error.localizedDescription }
    }

    public func toggleReadingLock(lineID: UUID) {
        guard let draft, draft.lines.contains(where: { $0.id == lineID }) else { return }
        if lockedReadingIDs.contains(lineID) {
            lockedReadingIDs.remove(lineID)
        } else {
            lockedReadingIDs.insert(lineID)
        }
        message = lockedReadingIDs.contains(lineID) ? "已锁定当前行读音" : "已解除当前行读音锁定"
    }

    public func isReadingLocked(lineID: UUID) -> Bool {
        lockedReadingIDs.contains(lineID)
    }

    public func regenerateReading(for lineID: UUID) {
        guard !lockedReadingIDs.contains(lineID), let draft,
              let existing = draft.lines.first(where: { $0.id == lineID }) else { return }
        let generated = Self.regenerate(existing)
        updateLine(lineID) { line in
            line.kanaText = generated.kanaText
            line.romajiText = generated.romajiText
            line.rubyTokens = generated.rubyTokens
        }
    }

    public func regenerateAllReadings() {
        guard var draft else { return }
        let locked = lockedReadingIDs
        for lineID in draft.lines.map(\.id) where !locked.contains(lineID) {
            try? draft.update(lineID) { line in
                line = Self.regenerate(line)
            }
        }
        self.draft = draft
        validate(draft)
        message = "已重新生成未锁定行的假名和罗马音"
    }

    public func selectTranslation(versionID: UUID) {
        guard let version = availableTranslations.first(where: { $0.record.id == versionID }), version.isComplete,
              let draft else { return }
        let document = Self.documentByProjecting(version, onto: draft.document(source: draft.source))
        let replacement = LyricsEditorDraft(document: document, sourceVersionID: draft.sourceVersionID, sourceContentHash: draft.sourceContentHash)
        self.draft = replacement
        self.selectedTranslation = version
        self.baseTranslationLines = replacement.lines.map(Self.translationText)
        validate(replacement)
    }

    public func selectLyricsVersion(versionID: UUID) {
        guard let repository, let track, let identity else { return }
        guard let record = availableVersions.first(where: { $0.record.id == versionID }) else { return }
        let preferredTranslationID = availableTranslations.first {
            $0.record.lyricsVersionID == versionID &&
            $0.record.sourceContentHash == record.record.contentHash &&
            $0.record.targetLanguage == translationConfiguration.targetLanguage
        }?.record.id
        let requestGeneration = generation
        loadTask?.cancel()
        loadTask = Task { [weak self, repository] in
            do {
                guard let loaded = try await repository.loadEditableVersion(versionID: versionID, track: track, identity: identity),
                      !Task.isCancelled else { return }
                let translations = try await repository.loadTranslationVersions(
                    lyricsVersionID: loaded.record.id,
                    targetLanguage: self?.translationConfiguration.targetLanguage ?? "zh-Hans",
                    sourceContentHash: loaded.record.contentHash
                )
                guard !Task.isCancelled else { return }
                let selected = translations.first { $0.record.id == preferredTranslationID }
                    ?? translations.first(where: { $0.record.isLocked })
                    ?? translations.first
                await MainActor.run { [weak self] in
                    guard let self, self.generation == requestGeneration else { return }
                    self.begin(
                        track: track,
                        identity: identity,
                        document: loaded.document,
                        lyricsVersionID: loaded.record.id,
                        sourceContentHash: loaded.record.contentHash,
                        revision: self.sourceRevision,
                        translations: translations,
                        selectedTranslation: selected,
                        configuration: self.translationConfiguration
                    )
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.message = "版本读取失败：\(error.localizedDescription)"
                }
            }
        }
    }

    public func prepareImport(_ content: String) {
        guard !isStale, isStillCurrent?() ?? true,
              let track, let identity else {
            message = "当前 Spotify 已切歌，请重新打开对应歌曲的编辑器"
            state = .stale
            return
        }
        do {
            let result = try LRCImportParser.parse(content)
            let imported = result.document(identity: identity, track: track)
            let match = LRCImportMatcher.compare(metadata: result.metadata, track: track)
            pendingImport = LyricsEditorImportPreview(result: result, document: imported, match: match)
            pendingTextImport = nil
            state = .importPreview
            message = match.isMismatchWarning ? "LRC 元数据与当前歌曲存在差异，请确认后再导入" : "LRC 与当前歌曲匹配"
        } catch {
            message = error.localizedDescription
            state = .failed(error.localizedDescription)
        }
    }

    public func cancelImportPreview() {
        pendingImport = nil
        pendingTextImport = nil
        state = isStale ? .stale : .editing
    }

    public func prepareTextImport(_ content: String, source: LyricsSource = .manualCreate) {
        guard !isStale, isStillCurrent?() ?? true else {
            message = "当前 Spotify 已切歌，请重新打开对应歌曲的编辑器"
            state = .stale
            return
        }
        do {
            pendingTextImport = try TextLyricsImportParser.parse(content)
            pendingTextImportSource = source
            pendingImport = nil
            state = .importPreview
            let warningCount = pendingTextImport?.warnings.count ?? 0
            message = warningCount == 0
                ? "纯文本已标准化，请确认后创建人工歌词版本"
                : "检测到 \(warningCount) 个需要确认的提示；文本不会被自动删除"
        } catch {
            message = error.localizedDescription
            state = .failed(error.localizedDescription)
        }
    }

    public func prepareTextImport(data: Data, source: LyricsSource = .manualImport) {
        guard !isStale, isStillCurrent?() ?? true else {
            message = "当前 Spotify 已切歌，请重新打开对应歌曲的编辑器"
            state = .stale
            return
        }
        do {
            pendingTextImport = try TextLyricsImportParser.parse(data)
            pendingTextImportSource = source
            pendingImport = nil
            state = .importPreview
            let warningCount = pendingTextImport?.warnings.count ?? 0
            message = warningCount == 0
                ? "TXT 已标准化，请确认后创建人工歌词版本"
                : "检测到 \(warningCount) 个需要确认的提示；文本不会被自动删除"
        } catch {
            message = error.localizedDescription
            state = .failed(error.localizedDescription)
        }
    }

    public func confirmTextImport() {
        guard !isStale, isStillCurrent?() ?? true,
              let result = pendingTextImport,
              let track,
              let identity else { return }
        let document = result.document(identity: identity, track: track, source: pendingTextImportSource)
        beginNew(
            track: track,
            identity: identity,
            document: document,
            source: pendingTextImportSource,
            revision: sourceRevision,
            configuration: translationConfiguration
        )
        message = "已载入 TXT 预览；保存后才会写入 SQLite"
    }

    public func confirmImport(lock: Bool = false) {
        guard let preview = pendingImport, let track, let identity,
              let repository,
              !isStale else { return }
        pendingImport = nil
        state = .saving
        let saveGeneration = generation
        let requestSourceVersionID = sourceVersionID ?? UUID()
        let requestSourceHash = sourceContentHash ?? ""
        let requestIsNewSource = isNewSourceSession
        saveTask?.cancel()
        saveTask = Task { [weak self, repository] in
            do {
                let request = LyricsEditSaveRequest(
                    track: track,
                    identity: identity,
                    sourceVersionID: requestSourceVersionID,
                    sourceContentHash: requestSourceHash,
                    document: preview.document,
                    createLyricsVersion: true,
                    lockLyricsVersion: lock,
                    targetSource: .manualImport,
                    isNewSource: requestIsNewSource
                )
                let result = try await repository.saveManualEdit(request)
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    guard let self, self.generation == saveGeneration, self.isStillCurrent?() ?? true else { return }
                    self.applySaved(result, identity: identity)
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self, self.generation == saveGeneration else { return }
                    self.state = .failed(error.localizedDescription)
                    self.message = error.localizedDescription
                }
            }
        }
    }

    public func save(lockLyrics: Bool = false, lockTranslation: Bool = false, forceCopy: Bool = false) {
        guard let draft, let track, let identity,
              let repository else { return }
        guard !isStale, isStillCurrent?() ?? true else {
            isStale = true
            state = .stale
            return
        }
        let currentLyrics = draft.lines.map(Self.lyricsProjection)
        let currentTranslations = draft.lines.map(Self.translationText)
        let readingsChanged = lockedReadingIDs != baseLockedReadingIDs
        let lyricsChanged = isNewSourceSession || forceCopy || currentLyrics != baseLyricsLines || readingsChanged
        let translationsChanged = currentTranslations != baseTranslationLines
        let hasTranslationLayer = currentTranslations.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            || baseTranslationLines.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        // A provider-embedded/legacy translation may not be selectable in the
        // current target language menu. Editing it still creates a proper
        // manual TranslationVersion rather than losing the layer.
        let shouldSaveTranslation = hasTranslationLayer && (translationsChanged || lyricsChanged)
        guard lyricsChanged || shouldSaveTranslation else {
            state = .failed("没有需要保存的编辑")
            message = "没有需要保存的编辑"
            return
        }
        guard validation.isSaveAllowed else { return }

        let timedCount = draft.timedNonBlankLineCount
        let untimedCount = draft.untimedNonBlankLineCount
        if untimedCount > 0, timedCount > 0 {
            let allowed = confirmPartialSave?(timedCount, untimedCount) ?? true
            guard allowed else {
                message = "已取消保存"
                return
            }
        }

        let document = draft.document(
            source: isNewSourceSession ? newSourceKind : .manualEdit,
            isSynchronized: validation.isSynchronized
        )
        let translation = shouldSaveTranslation ? ManualTranslationEdit(
            targetLanguage: selectedTranslation?.record.targetLanguage ?? translationConfiguration.targetLanguage,
            model: selectedTranslation?.record.model ?? "",
            baseURLHost: selectedTranslation?.record.baseURLHost ?? "",
            promptHash: selectedTranslation?.record.promptHash ?? "",
            lines: currentTranslations,
            parentVersionID: selectedTranslation?.record.id,
            isLocked: lockTranslation
        ) : nil
        let readingLayers = draft.lines.enumerated().compactMap { index, line -> LyricsReadingLayerDraft? in
            guard lockedReadingIDs.contains(line.id) else { return nil }
            return LyricsReadingLayerDraft(
                lineIndex: index,
                kanaText: line.kanaText,
                romajiText: line.romajiText,
                source: "manualEdit",
                isLocked: true
            )
        }

        state = .saving
        message = nil
        let saveGeneration = generation
        let requestSourceVersionID = sourceVersionID ?? UUID()
        let requestSourceHash = sourceContentHash ?? ""
        let requestIsNewSource = isNewSourceSession
        let requestTargetSource = isNewSourceSession ? newSourceKind : .manualEdit
        saveTask?.cancel()
        saveTask = Task { [weak self, repository] in
            do {
                let request = LyricsEditSaveRequest(
                    track: track,
                    identity: identity,
                    sourceVersionID: requestSourceVersionID,
                    sourceContentHash: requestSourceHash,
                    document: document,
                    createLyricsVersion: lyricsChanged,
                    lockLyricsVersion: lockLyrics,
                    targetSource: requestTargetSource,
                    isNewSource: requestIsNewSource,
                    translation: translation,
                    readingLayers: readingLayers
                )
                let result = try await repository.saveManualEdit(request)
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    guard let self, self.generation == saveGeneration, self.isStillCurrent?() ?? true else {
                        self?.isStale = true
                        self?.state = .stale
                        return
                    }
                    self.applySaved(result, identity: identity)
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self, self.generation == saveGeneration else { return }
                    self.state = .failed(error.localizedDescription)
                    self.message = error.localizedDescription
                }
            }
        }
    }

    private func applySaved(_ result: LyricsEditSaveResult, identity: TrackIdentity) {
        if let stored = result.lyricsVersion {
            isNewSourceSession = false
            newSourceKind = .manualEdit
            sourceVersionID = stored.record.id
            sourceContentHash = stored.record.contentHash
            // SQLite stores rows by lineIndex, not the editor-only UUID used by
            // SwiftUI bindings. Preserve the current draft IDs while the
            // focused TextField is committing, otherwise the re-render after
            // save can send one final setter for an old line ID and surface a
            // misleading "找不到歌词行" message.
            let projected = Self.documentByProjecting(result.translationVersion, onto: stored.document)
            let stableProjected = Self.documentPreservingLineIDs(projected, from: self.draft)
            var next = LyricsEditorDraft(document: stableProjected, sourceVersionID: stored.record.id, sourceContentHash: stored.record.contentHash)
            next.markSaved()
            draft = next
            baseLyricsLines = next.lines.map(Self.lyricsProjection)
            baseTranslationLines = next.lines.map(Self.translationText)
            availableVersions.insert(stored, at: 0)
            lockedReadingIDs = Set(stored.lockedReadingLayers.compactMap { layer in
                guard next.lines.indices.contains(layer.lineIndex) else { return nil }
                return next.lines[layer.lineIndex].id
            })
            baseLockedReadingIDs = lockedReadingIDs
        } else if var draft {
            draft.markSaved()
            self.draft = draft
            baseLyricsLines = draft.lines.map(Self.lyricsProjection)
            baseTranslationLines = draft.lines.map(Self.translationText)
        }
        if let translation = result.translationVersion {
            availableTranslations.insert(translation, at: 0)
            selectedTranslation = translation
        }
        pendingImport = nil
        state = .saved
        message = "已保存人工版本；原始 Provider 版本仍保留"
        if let currentDraft = self.draft { validate(currentDraft) }
        onSaved?(result, identity)
    }

    private func validate(_ draft: LyricsEditorDraft) {
        validation = LyricsTimelineValidator.validate(lines: draft.lines, duration: draft.duration)
        if state == .saved { return }
        if state != .stale && state != .saving && state != .importPreview {
            state = .editing
        }
    }

    private static func lyricsProjection(_ line: LyricsEditorLineDraft) -> LyricsEditorLineDraft {
        LyricsEditorLineDraft(
            id: line.id,
            originalText: line.originalText,
            startTime: line.startTime,
            endTime: line.endTime,
            kanaText: line.kanaText,
            romajiText: line.romajiText,
            rubyTokens: line.rubyTokens
        )
    }

    private static func translationText(_ line: LyricsEditorLineDraft) -> String {
        line.translationText ?? ""
    }

    private static func documentByProjecting(
        _ translation: StoredTranslationVersion?,
        onto document: LyricsDocument
    ) -> LyricsDocument {
        guard let translation,
              translation.isComplete,
              translation.lines.count == document.lines.count else { return document }
        var lines = document.lines
        for stored in translation.lines where lines.indices.contains(stored.lineIndex) {
            lines[stored.lineIndex].translationText = stored.translatedText
        }
        return LyricsDocument(
            identity: document.identity,
            title: document.title,
            artist: document.artist,
            album: document.album,
            duration: document.duration,
            lines: lines,
            isSynchronized: document.isSynchronized,
            source: document.source,
            confidence: document.confidence,
            providerSourceID: document.providerSourceID
        )
    }

    private static func documentPreservingLineIDs(
        _ document: LyricsDocument,
        from previousDraft: LyricsEditorDraft?
    ) -> LyricsDocument {
        guard let previousDraft,
              previousDraft.lines.count == document.lines.count else { return document }
        let lines = document.lines.enumerated().map { index, line in
            LyricLine(
                id: previousDraft.lines[index].id,
                timestamp: line.timestamp,
                originalText: line.originalText,
                endTime: line.endTime,
                translationText: line.translationText,
                romajiText: line.romajiText,
                kanaText: line.kanaText,
                rubyTokens: line.rubyTokens
            )
        }
        return LyricsDocument(
            identity: document.identity,
            title: document.title,
            artist: document.artist,
            album: document.album,
            duration: document.duration,
            lines: lines,
            isSynchronized: document.isSynchronized,
            source: document.source,
            confidence: document.confidence,
            providerSourceID: document.providerSourceID
        )
    }

    private static func regenerate(_ line: LyricsEditorLineDraft) -> LyricsEditorLineDraft {
        let source = LyricsEditorLineDraft(
            id: line.id,
            originalText: line.originalText,
            translationText: line.translationText,
            startTime: line.startTime,
            endTime: line.endTime
        )
        let generated = LyricsLayerEnricher.enrich(lines: [source.asLyricLine()]).first
        guard let generated else { return source }
        var result = LyricsEditorLineDraft(
            line: generated,
            startTimeIsMeaningful: line.startTime != nil
        )
        // The enrichment pipeline sees a compatibility zero placeholder when
        // a row is untimed. Restore the editor's optional timing exactly.
        result.startTime = line.startTime
        result.endTime = line.endTime
        return result
    }
}

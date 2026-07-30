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
    @Published public private(set) var message: String?
    @Published public private(set) var isStale = false

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
        draft?.isDirty == true || pendingImport != nil
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
        self.message = nil
        self.isStale = false

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

    public func close() {
        generation &+= 1
        loadTask?.cancel()
        saveTask?.cancel()
        pendingImport = nil
        draft = nil
        availableVersions = []
        availableTranslations = []
        selectedTranslation = nil
        identity = nil
        track = nil
        sourceVersionID = nil
        sourceContentHash = nil
        lockedReadingIDs = []
        baseLockedReadingIDs = []
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
        guard let track, let identity, let sourceVersionID, let sourceContentHash else { return }
        do {
            let result = try LRCImportParser.parse(content)
            let imported = result.document(identity: identity, track: track)
            let match = LRCImportMatcher.compare(metadata: result.metadata, track: track)
            pendingImport = LyricsEditorImportPreview(result: result, document: imported, match: match)
            state = .importPreview
            message = match.isMismatchWarning ? "LRC 元数据与当前歌曲存在差异，请确认后再导入" : "LRC 与当前歌曲匹配"
            _ = sourceVersionID
            _ = sourceContentHash
        } catch {
            message = error.localizedDescription
            state = .failed(error.localizedDescription)
        }
    }

    public func cancelImportPreview() {
        pendingImport = nil
        state = isStale ? .stale : .editing
    }

    public func confirmImport(lock: Bool = false) {
        guard let preview = pendingImport, let track, let identity,
              let sourceVersionID, let sourceContentHash, let repository,
              !isStale else { return }
        pendingImport = nil
        state = .saving
        let saveGeneration = generation
        saveTask?.cancel()
        saveTask = Task { [weak self, repository] in
            do {
                let request = LyricsEditSaveRequest(
                    track: track,
                    identity: identity,
                    sourceVersionID: sourceVersionID,
                    sourceContentHash: sourceContentHash,
                    document: preview.document,
                    createLyricsVersion: true,
                    lockLyricsVersion: lock,
                    targetSource: .manualImport
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
              let sourceVersionID, let sourceContentHash, let repository else { return }
        guard !isStale, isStillCurrent?() ?? true else {
            isStale = true
            state = .stale
            return
        }
        let currentLyrics = draft.lines.map(Self.lyricsProjection)
        let currentTranslations = draft.lines.map(Self.translationText)
        let readingsChanged = lockedReadingIDs != baseLockedReadingIDs
        let lyricsChanged = forceCopy || currentLyrics != baseLyricsLines || readingsChanged
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

        let document = draft.document(source: .manualEdit, isSynchronized: validation.isSynchronized)
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
        saveTask?.cancel()
        saveTask = Task { [weak self, repository] in
            do {
                let request = LyricsEditSaveRequest(
                    track: track,
                    identity: identity,
                    sourceVersionID: sourceVersionID,
                    sourceContentHash: sourceContentHash,
                    document: document,
                    createLyricsVersion: lyricsChanged,
                    lockLyricsVersion: lockLyrics,
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

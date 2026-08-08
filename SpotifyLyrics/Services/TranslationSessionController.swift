import Combine
import Foundation

public enum TranslationSessionState: Equatable, Sendable {
    case idle
    case unavailable
    case loading
    case loaded(UUID)
    case candidateReady(UUID)
    case failed(String)

    public var userFacingMessage: String {
        switch self {
        case .idle: return ""
        case .unavailable: return "未配置 AI 翻译"
        case .loading: return "正在翻译整首歌词…"
        case .loaded: return ""
        case .candidateReady: return "有新的翻译候选待采用"
        case .failed(let message): return "翻译失败：\(message)"
        }
    }
}

/// The one shared translation state source for V3, lyrics focus and retained
/// auxiliary windows. It merges identical in-flight requests and commits only
/// complete, source-hash-validated versions.
@MainActor
public final class TranslationSessionController: ObservableObject {
    @Published public private(set) var state: TranslationSessionState = .idle
    @Published public private(set) var selectedVersion: StoredTranslationVersion?
    @Published public private(set) var availableVersions: [StoredTranslationVersion] = []
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var progressMessage = ""
    /// Distinguishes an explicit session-level “无翻译版本” choice from a
    /// hidden translation layer or a context that has not loaded yet.
    @Published public private(set) var isNoSelection = false
    @Published public private(set) var pendingCandidate: StoredTranslationVersion?

    private let repository: any TranslationRepository
    private var engine: (any TranslationEngine)?
    private var requestTask: Task<Void, Never>?
    private var context: TranslationContext?
    private var inFlightKey: String?
    private var manualSelection: [String: UUID] = [:]
    private var manualNoSelection: Set<String> = []
    private var requestGeneration: UInt64 = 0

    private struct TranslationContext: Equatable, Sendable {
        let identity: TrackIdentity
        let lyricsVersionID: UUID
        let sourceContentHash: String
        let document: LyricsDocument
        let configuration: AITranslationConfiguration

        var key: String {
            [identity.stableKey, lyricsVersionID.uuidString, sourceContentHash, configuration.targetLanguage]
                .joined(separator: "|")
        }
    }

    public init(
        repository: any TranslationRepository,
        service: (any AITranslationService)? = OpenAICompatibleTranslationService()
    ) {
        self.repository = repository
        self.engine = service.map { TranslationEngineRegistry.wrapping($0) }
    }

    public init(
        repository: any TranslationRepository,
        engine: (any TranslationEngine)?
    ) {
        self.repository = repository
        self.engine = engine
    }

    deinit {
        requestTask?.cancel()
    }

    public var isTranslating: Bool {
        if case .loading = state { return true }
        return false
    }

    public func synchronize(
        document: LyricsDocument?,
        lyricsVersionID: UUID?,
        sourceContentHash: String?,
        configuration: AITranslationConfiguration
    ) {
        guard let document, !document.lines.isEmpty, let lyricsVersionID else {
            resetForMissingLyrics()
            return
        }
        let hash = sourceContentHash ?? LyricsPersistenceMapper.sourceContentHash(document: document)
        let next = TranslationContext(
            identity: document.identity,
            lyricsVersionID: lyricsVersionID,
            sourceContentHash: hash,
            document: document,
            configuration: configuration
        )
        if let previous = context, previous.key == next.key {
            // A session refresh may carry newly enriched display layers. Keep
            // the selected version but update the document used for projection.
            context = next
            // Configuration is deliberately not part of the persistence key:
            // changing model/style must not discard the user-selected version.
            // It can, however, turn automatic translation on or make a
            // previously unconfigured service usable, so re-run selection and
            // the one-shot auto branch when that boundary changes.
            let configurationBoundaryChanged =
                previous.configuration.autoTranslateNewLyrics != next.configuration.autoTranslateNewLyrics ||
                previous.configuration.isConfigured != next.configuration.isConfigured
            if configurationBoundaryChanged {
                loadExistingOrAutoTranslate(next)
            }
            return
        }
        requestTask?.cancel()
        requestTask = nil
        inFlightKey = nil
        requestGeneration &+= 1
        context = next
        selectedVersion = nil
        availableVersions = []
        pendingCandidate = nil
        errorMessage = nil
        progressMessage = ""
        isNoSelection = manualNoSelection.contains(next.key)
        state = .idle
        loadExistingOrAutoTranslate(next)
    }

    public func cancel() {
        requestTask?.cancel()
        requestTask = nil
        inFlightKey = nil
        requestGeneration &+= 1
        state = .idle
        progressMessage = ""
    }

    public func setEngine(_ engine: any TranslationEngine) {
        self.engine = engine
    }

    /// Re-reads the selected/source-matched versions after another session
    /// (for example the lyrics editor) has committed a new version.
    public func reloadCurrentContext() {
        guard let context else { return }
        loadExistingOrAutoTranslate(context)
    }

    public func resetForMissingLyrics() {
        requestTask?.cancel()
        requestTask = nil
        inFlightKey = nil
        requestGeneration &+= 1
        context = nil
        selectedVersion = nil
        availableVersions = []
        errorMessage = nil
        progressMessage = ""
        isNoSelection = false
        pendingCandidate = nil
        state = .idle
    }

    public func translateCurrentLyrics() {
        guard let context else { return }
        startTranslation(context, forceNewVersion: false)
    }

    public func retranslateCurrentLyrics() {
        guard let context else { return }
        startTranslation(context, forceNewVersion: true)
    }

    /// Explicitly selects no translation for the current lyric context. The
    /// existing versions remain available and are never deleted or modified.
    public func selectNone() {
        guard let context else { return }
        requestTask?.cancel()
        requestTask = nil
        inFlightKey = nil
        requestGeneration &+= 1
        manualNoSelection.insert(context.key)
        selectedVersion = nil
        pendingCandidate = nil
        isNoSelection = true
        errorMessage = nil
        state = .idle
        progressMessage = ""
    }

    public func restoreRecommended() {
        guard let context else { return }
        manualSelection.removeValue(forKey: context.key)
        manualNoSelection.remove(context.key)
        isNoSelection = false
        pendingCandidate = nil
        progressMessage = ""
        loadExistingOrAutoTranslate(context)
    }

    public func select(versionID: UUID) {
        guard let context,
              let version = availableVersions.first(where: { $0.record.id == versionID }),
              version.record.sourceContentHash == context.sourceContentHash,
              version.record.targetLanguage == context.configuration.targetLanguage,
              version.isComplete,
              !version.isDraft,
              !version.isArchived else { return }
        requestTask?.cancel()
        requestTask = nil
        inFlightKey = nil
        manualSelection[context.key] = versionID
        manualNoSelection.remove(context.key)
        requestGeneration &+= 1
        isNoSelection = false
        selectedVersion = version
        state = .loaded(version.record.id)
        errorMessage = nil
        progressMessage = ""
    }

    /// Generated translations are candidates until the user explicitly
    /// adopts them. This prevents a successful request from silently
    /// replacing a locked/manual or no-selection choice.
    public func adoptTranslation(versionID: UUID) {
        guard let context,
              let candidate = availableVersions.first(where: { $0.record.id == versionID }),
              candidate.isComplete,
              candidate.isDraft,
              !candidate.record.isLocked,
              candidate.record.lyricsVersionID == context.lyricsVersionID,
              candidate.record.sourceContentHash == context.sourceContentHash else { return }
        Task { [weak self, repository] in
            do {
                try await repository.adoptTranslation(versionID: versionID)
                await MainActor.run { [weak self] in
                    guard let self, self.context?.key == context.key else { return }
                    let adopted = candidate.with(record: candidate.record.with(isDraft: false, isArchived: false))
                    self.availableVersions = self.availableVersions.map { $0.record.id == versionID ? adopted : $0 }
                    self.pendingCandidate = nil
                    self.manualSelection[context.key] = versionID
                    self.manualNoSelection.remove(context.key)
                    self.isNoSelection = false
                    self.selectedVersion = adopted
                    self.state = .loaded(versionID)
                    self.errorMessage = nil
                }
            } catch {
                await MainActor.run { [weak self] in self?.errorMessage = error.localizedDescription }
            }
        }
    }

    public func archiveTranslation(versionID: UUID) {
        guard let context,
              let version = availableVersions.first(where: { $0.record.id == versionID }),
              !version.record.isLocked else { return }
        Task { [weak self, repository] in
            do {
                try await repository.archiveTranslation(versionID: versionID, archived: true)
                await MainActor.run { [weak self] in
                    guard let self, self.context?.key == context.key else { return }
                    let archived = version.with(record: version.record.with(isArchived: true))
                    self.availableVersions = self.availableVersions.map { $0.record.id == versionID ? archived : $0 }
                    if self.pendingCandidate?.record.id == versionID { self.pendingCandidate = nil }
                    if self.selectedVersion?.record.id == versionID {
                        self.selectedVersion = nil
                        self.state = .idle
                    }
                }
            } catch {
                await MainActor.run { [weak self] in self?.errorMessage = error.localizedDescription }
            }
        }
    }

    public func lockSelected() {
        guard let selectedVersion else { return }
        let id = selectedVersion.record.id
        Task { [weak self] in
            do {
                try await self?.repository.markTranslationLocked(versionID: id, locked: true)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.reloadKeepingSelection(id: id)
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    public func deleteSelected() {
        guard let selectedVersion, !selectedVersion.record.isLocked else { return }
        let id = selectedVersion.record.id
        Task { [weak self] in
            do {
                try await self?.repository.deleteTranslation(versionID: id)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.selectedVersion = nil
                    self.loadExistingOrAutoTranslateIfContextExists()
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    /// Projects the selected version onto the existing LyricLine values. All
    /// original/kana/romaji/timeline fields remain untouched.
    public func project(onto lines: [LyricLine]) -> [LyricLine] {
        if isNoSelection {
            return lines.map { line in
                var cleared = line
                cleared.translationText = nil
                return cleared
            }
        }
        guard let selectedVersion,
              selectedVersion.isComplete,
              selectedVersion.lines.count == lines.count,
              selectedVersion.lines.map(\.lineIndex) == Array(lines.indices) else {
            return lines
        }
        var projected = lines
        for stored in selectedVersion.lines {
            projected[stored.lineIndex].translationText = stored.translatedText
        }
        return projected
    }

    /// Projects only when the selected translation belongs to the requested
    /// live lyric document.  Search previews share this controller, so a
    /// floating window must not accidentally render a preview translation on
    /// the currently playing song.
    public func project(
        onto lines: [LyricLine],
        identity: TrackIdentity,
        lyricsVersionID: UUID?,
        sourceContentHash: String?
    ) -> [LyricLine] {
        guard let context,
              context.identity == identity,
              context.lyricsVersionID == lyricsVersionID,
              context.sourceContentHash == sourceContentHash else {
            return lines
        }
        return project(onto: lines)
    }

    private func loadExistingOrAutoTranslate(_ context: TranslationContext) {
        requestTask?.cancel()
        requestTask = nil
        inFlightKey = nil
        progressMessage = ""
        requestGeneration &+= 1
        let loadGeneration = requestGeneration
        let key = context.key
        requestTask = Task { [weak self, repository] in
            do {
                let versions = try await repository.loadTranslationVersions(
                    lyricsVersionID: context.lyricsVersionID,
                    targetLanguage: context.configuration.targetLanguage,
                    sourceContentHash: context.sourceContentHash
                )
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    guard let self,
                          self.context?.key == key,
                          self.requestGeneration == loadGeneration else { return }
                    self.availableVersions = versions
                    self.pendingCandidate = versions.first(where: { $0.isDraft && !$0.isArchived })
                    if self.manualNoSelection.contains(key) {
                        self.selectedVersion = nil
                        self.isNoSelection = true
                        self.state = .idle
                        self.errorMessage = nil
                        return
                    }
                    self.isNoSelection = false
                    if let selected = self.chooseVersion(versions, context: context) {
                        self.selectedVersion = selected
                        self.state = .loaded(selected.record.id)
                        self.errorMessage = nil
                    } else if context.configuration.autoTranslateNewLyrics {
                        self.startTranslation(context, forceNewVersion: false)
                    } else {
                        self.state = .idle
                    }
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self,
                          self.context?.key == key,
                          self.requestGeneration == loadGeneration else { return }
                    self.state = .failed(error.localizedDescription)
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func loadExistingOrAutoTranslateIfContextExists() {
        guard let context else { return }
        loadExistingOrAutoTranslate(context)
    }

    private func chooseVersion(
        _ versions: [StoredTranslationVersion],
        context: TranslationContext
    ) -> StoredTranslationVersion? {
        let eligible = versions.filter {
            $0.isComplete &&
            !$0.isDraft &&
            !$0.isArchived &&
            $0.record.targetLanguage == context.configuration.targetLanguage &&
            $0.record.sourceContentHash == context.sourceContentHash
        }
        guard !manualNoSelection.contains(context.key) else { return nil }
        if let locked = eligible.first(where: { $0.record.isLocked }) { return locked }
        if let manualID = manualSelection[context.key],
           let manual = eligible.first(where: { $0.record.id == manualID }) { return manual }
        return eligible.first
    }

    private func startTranslation(_ context: TranslationContext, forceNewVersion: Bool) {
        let key = context.key
        if !forceNewVersion, inFlightKey == key { return }
        if !forceNewVersion,
           let pendingCandidate,
           pendingCandidate.record.lyricsVersionID == context.lyricsVersionID,
           pendingCandidate.record.sourceContentHash == context.sourceContentHash,
           !pendingCandidate.record.isArchived {
            // A completed candidate is already waiting for an explicit user
            // decision. A normal retry must not create duplicate versions;
            // the explicit “重新翻译” action uses forceNewVersion instead.
            return
        }
        requestTask?.cancel()
        requestGeneration &+= 1
        let translationGeneration = requestGeneration
        inFlightKey = key
        state = .loading
        errorMessage = nil
        progressMessage = engine?.metadata.stableID == TranslationEngineID.appleSystem.rawValue
            ? "正在检查 Apple 语言支持并准备系统翻译…"
            : "正在请求整首歌词翻译…"
        let originalLines = context.document.lines.map(\.originalText)
        let engine = self.engine
        requestTask = Task { [weak self, repository] in
            do {
                guard let engine else { throw AITranslationError.notConfigured }
                let sourceLines = context.document.lines.enumerated().map { index, line in
                    AITranslationSourceLine(
                        index: index,
                        original: line.originalText,
                        kana: line.kanaText,
                        romaji: line.romajiText
                    )
                }
                let aiContext = AITranslationContext(
                    title: context.document.title ?? "",
                    artist: context.document.artist ?? "",
                    album: context.document.album ?? "",
                    sourceLanguage: "ja",
                    targetLanguage: context.configuration.targetLanguage,
                    style: context.configuration.style,
                    lines: sourceLines
                )
                let draft: AITranslationDraft
                do {
                    draft = try await engine.translate(
                        context: aiContext,
                        sourceContentHash: context.sourceContentHash,
                        configuration: context.configuration
                    )
                } catch {
                    guard context.configuration.fallbackStrategy == .automaticSystem,
                          engine.metadata.stableID == TranslationEngineID.openAICompatible.rawValue else {
                        throw error
                    }
                    await MainActor.run { [weak self] in
                        guard let self,
                              self.context?.key == key,
                              self.requestGeneration == translationGeneration else { return }
                        self.progressMessage = "兼容接口失败，正在准备 Apple 系统翻译…"
                    }
                    draft = try await AppleSystemTranslationEngine().translate(
                        context: aiContext,
                        sourceContentHash: context.sourceContentHash,
                        configuration: context.configuration
                    )
                }
                guard !Task.isCancelled else { throw AITranslationError.cancelled }
                let saved = try await repository.saveTranslation(
                    lyricsVersionID: context.lyricsVersionID,
                    sourceContentHash: context.sourceContentHash,
                    originalLines: originalLines,
                    draft: draft.with(isDraft: true, isArchived: false),
                    forceNewVersion: forceNewVersion
                )
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    guard let self,
                          self.context?.key == key,
                          self.requestGeneration == translationGeneration else { return }
                    self.inFlightKey = nil
                    self.availableVersions.insert(saved, at: 0)
                    self.pendingCandidate = saved
                    self.state = .candidateReady(saved.record.id)
                    self.progressMessage = "翻译候选已生成，确认后再采用"
                }
            } catch is CancellationError {
                await MainActor.run { [weak self] in
                    guard let self,
                          self.context?.key == key,
                          self.requestGeneration == translationGeneration else { return }
                    self.inFlightKey = nil
                    self.state = .idle
                    self.progressMessage = ""
                }
            } catch let error as AITranslationError {
                await MainActor.run { [weak self] in
                    guard let self,
                          self.context?.key == key,
                          self.requestGeneration == translationGeneration else { return }
                    self.inFlightKey = nil
                    self.state = .failed(error.localizedDescription)
                    self.errorMessage = error.localizedDescription
                    self.progressMessage = "翻译失败：\(error.localizedDescription)"
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self,
                          self.context?.key == key,
                          self.requestGeneration == translationGeneration else { return }
                    self.inFlightKey = nil
                    self.state = .failed(error.localizedDescription)
                    self.errorMessage = error.localizedDescription
                    self.progressMessage = "翻译失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func reloadKeepingSelection(id: UUID) {
        guard let context else { return }
        manualSelection[context.key] = id
        loadExistingOrAutoTranslate(context)
    }
}

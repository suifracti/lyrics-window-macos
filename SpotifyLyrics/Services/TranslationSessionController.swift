import Combine
import Foundation

public enum TranslationSessionState: Equatable, Sendable {
    case idle
    case unavailable
    case loading
    case loaded(UUID)
    case failed(String)

    public var userFacingMessage: String {
        switch self {
        case .idle: return ""
        case .unavailable: return "未配置 AI 翻译"
        case .loading: return "正在翻译整首歌词…"
        case .loaded: return ""
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

    private let repository: any TranslationRepository
    private let service: (any AITranslationService)?
    private var requestTask: Task<Void, Never>?
    private var context: TranslationContext?
    private var inFlightKey: String?
    private var manualSelection: [String: UUID] = [:]

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
        self.service = service
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
        context = next
        selectedVersion = nil
        availableVersions = []
        errorMessage = nil
        state = .idle
        loadExistingOrAutoTranslate(next)
    }

    public func cancel() {
        requestTask?.cancel()
        requestTask = nil
        inFlightKey = nil
        state = .idle
    }

    public func resetForMissingLyrics() {
        requestTask?.cancel()
        requestTask = nil
        inFlightKey = nil
        context = nil
        selectedVersion = nil
        availableVersions = []
        errorMessage = nil
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

    public func select(versionID: UUID) {
        guard let context,
              let version = availableVersions.first(where: { $0.record.id == versionID }),
              version.record.sourceContentHash == context.sourceContentHash,
              version.record.targetLanguage == context.configuration.targetLanguage,
              version.isComplete else { return }
        manualSelection[context.key] = versionID
        selectedVersion = version
        state = .loaded(version.record.id)
        errorMessage = nil
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

    private func loadExistingOrAutoTranslate(_ context: TranslationContext) {
        requestTask?.cancel()
        requestTask = nil
        inFlightKey = nil
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
                    guard let self, self.context?.key == key else { return }
                    self.availableVersions = versions
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
                    guard let self, self.context?.key == key else { return }
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
            $0.record.targetLanguage == context.configuration.targetLanguage &&
            $0.record.sourceContentHash == context.sourceContentHash
        }
        if let locked = eligible.first(where: { $0.record.isLocked }) { return locked }
        if let manualID = manualSelection[context.key],
           let manual = eligible.first(where: { $0.record.id == manualID }) { return manual }
        return eligible.first
    }

    private func startTranslation(_ context: TranslationContext, forceNewVersion: Bool) {
        let key = context.key
        if !forceNewVersion, inFlightKey == key { return }
        requestTask?.cancel()
        inFlightKey = key
        state = .loading
        errorMessage = nil
        let originalLines = context.document.lines.map(\.originalText)
        let service = self.service
        requestTask = Task { [weak self, repository] in
            do {
                guard let service else { throw AITranslationError.notConfigured }
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
                let draft = try await service.translate(
                    context: aiContext,
                    sourceContentHash: context.sourceContentHash,
                    configuration: context.configuration
                )
                guard !Task.isCancelled else { throw AITranslationError.cancelled }
                let saved = try await repository.saveTranslation(
                    lyricsVersionID: context.lyricsVersionID,
                    sourceContentHash: context.sourceContentHash,
                    originalLines: originalLines,
                    draft: draft,
                    forceNewVersion: forceNewVersion
                )
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    guard let self, self.context?.key == key else { return }
                    self.inFlightKey = nil
                    self.availableVersions.insert(saved, at: 0)
                    self.selectedVersion = saved
                    self.manualSelection[key] = saved.record.id
                    self.state = .loaded(saved.record.id)
                }
            } catch is CancellationError {
                await MainActor.run { [weak self] in
                    guard let self, self.context?.key == key else { return }
                    self.inFlightKey = nil
                    self.state = .idle
                }
            } catch let error as AITranslationError {
                await MainActor.run { [weak self] in
                    guard let self, self.context?.key == key else { return }
                    self.inFlightKey = nil
                    self.state = .failed(error.localizedDescription)
                    self.errorMessage = error.localizedDescription
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self, self.context?.key == key else { return }
                    self.inFlightKey = nil
                    self.state = .failed(error.localizedDescription)
                    self.errorMessage = error.localizedDescription
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

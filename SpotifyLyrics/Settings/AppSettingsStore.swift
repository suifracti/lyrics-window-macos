import Combine
import Foundation

/// Persistent user-facing interaction mode for the shared floating lyrics
/// panel. It lives beside the settings boundary so lightweight contract
/// builds that compile AppSettingsStore without AppKit window code keep the
/// same model dependency as the production target.
public enum FloatingLyricsInteractionMode: String, CaseIterable, Codable, Sendable {
    case interactive
    case locked
    case passThrough

    public var title: String {
        switch self {
        case .interactive: return "可编辑 / 可拖动"
        case .locked: return "锁定展示"
        case .passThrough: return "鼠标穿透"
        }
    }

    public var detail: String {
        switch self {
        case .interactive: return "可以移动、缩放并操作窗口"
        case .locked: return "保持位置和尺寸，仍可响应窗口事件"
        case .passThrough: return "不接收普通鼠标事件，可从 App 菜单恢复"
        }
    }
}

/// The single UserDefaults boundary for user-facing configuration. Views bind
/// to this object; PlaybackState mirrors the display value and turns provider
/// IDs into the existing provider instances.
public final class AppSettingsStore: ObservableObject {
    public static let shared = AppSettingsStore()

    public enum Key {
        public static let settingsVersion = "settings.version"
        public static let mainWindowLayoutStyle = "mainWindowLayoutStyle"
        public static let automaticCompactLyricsFocus = "general.automaticCompactLyricsFocus"
        public static let connectSpotifyOnLaunch = "general.connectSpotifyOnLaunch"
        public static let autoSearchLyricsOnTrackChange = "general.autoSearchLyricsOnTrackChange"
        /// Product zero-operation automatic alignment (default off).
        public static let automaticAlignmentEnabled = "automaticAlignment.enabled.v1"
        public static let keepMainWindowOnTop = "general.keepMainWindowOnTop"
        public static let restoreWindowState = "general.restoreWindowState"
        public static let mainWindowFrame = "general.mainWindowFrame"
        public static let floatingWindowFrame = "general.floatingWindowFrame"
        public static let floatingWindowScreenID = "general.floatingWindowScreenID"
        public static let floatingWindowAlwaysOnTop = "general.floatingWindowAlwaysOnTop"
        public static let floatingWindowInteractionMode = "general.floatingWindowInteractionMode"
        public static let floatingWindowWasVisible = "general.floatingWindowWasVisible"
        public static let floatingWindowOpacity = "general.floatingWindowOpacity"
        public static let floatingLyricsPresentation = "general.floatingLyricsPresentation"
        public static let floatingLyricsSurfaceStyle = "general.floatingLyricsSurfaceStyle"
        public static let capsuleWindowHorizontalOffset = "general.capsuleWindowHorizontalOffset"
        public static let capsuleWindowScreenID = "general.capsuleWindowScreenID"
        public static let capsuleWindowWasVisible = "general.capsuleWindowWasVisible"
        public static let showOriginal = "display.showOriginal"
        public static let showTranslation = "display.showTranslation"
        public static let showRomaji = "display.showRomaji"
        public static let showPinyin = "display.showPinyin"
        public static let kanaDisplayMode = "display.kanaDisplayMode"
        public static let fontSize = "display.fontSize"
        public static let assistantFontSize = "display.assistantFontSize"
        public static let inactiveOpacity = "display.inactiveOpacity"
        public static let rubyFontSize = "display.rubyFontSize"
        public static let hideDistantAuxiliary = "display.hideDistantAuxiliary"
        public static let providerEnabled = "lyrics.providers.enabled"
        public static let providerOrder = "lyrics.providers.order"
        /// Single free lyrics source mode. Stable values:
        /// `lyricsSourceMode.standardFree.v1` / `lyricsSourceMode.experimentalFree.v1`.
        public static let lyricsSourceMode = "lyrics.sourceMode"
        public static let aiBaseURL = "ai.baseURL"
        public static let aiModel = "ai.model"
        public static let aiTargetLanguage = "ai.targetLanguage"
        public static let aiStyle = "ai.style"
        public static let aiCustomSystemPrompt = "ai.customSystemPrompt"
        public static let aiTemperature = "ai.temperature"
        public static let aiTimeout = "ai.timeout"
        public static let aiAutoTranslateNewLyrics = "ai.autoTranslateNewLyrics"
        public static let aiAPIKeyConfigured = "ai.apiKeyConfigured"
        public static let aiModelDirectoryCache = "ai.modelDirectory.cache"
        public static let aiModelDirectoryRefreshedAt = "ai.modelDirectory.refreshedAt"
        public static let aiEngineID = "ai.engineID"
        public static let aiPromptPresetID = "ai.promptPresetID"
        public static let aiProfileID = "ai.profileID"
        public static let aiProfileSnapshot = "ai.profileSnapshot"
        public static let aiFallbackStrategy = "ai.fallbackStrategy"
        public static let aiWorkflowID = "ai.workflowID"
        public static let settingsCenterPresentation = "settings.centerPresentation"
        public static let readingPreferences = "reading.preferences.v1"
        public static let v3BackdropBlurRadius = "v3.backdropBlurRadius"
        public static let v3ArtworkPosition = "v3.artworkPosition"
        public static let v3ArtworkSizeScale = "v3.artworkSizeScale"
        public static let v3InstrumentalPureImmersion = "v3.instrumentalPureImmersion"
    }

    public static let currentSettingsVersion = 1

    private let defaults: UserDefaults

    /// Presentation choices share this UserDefaults boundary with the rest
    /// of the settings store. The selection object is metadata/selection
    /// only; it never owns a playback or lyrics runtime.
    public let presentationSelections: PresentationSelectionStore
    public let translationProfiles: TranslationProfileStore
    public let readingUserDictionary: ReadingUserDictionaryStore

    @Published public var settingsCenterPresentationRawValue: String {
        didSet { defaults.set(settingsCenterPresentationRawValue, forKey: Key.settingsCenterPresentation) }
    }

    @Published public var mainWindowLayoutStyleRawValue: String {
        didSet { defaults.set(mainWindowLayoutStyleRawValue, forKey: Key.mainWindowLayoutStyle) }
    }

    @Published public var automaticCompactLyricsFocus: Bool {
        didSet { defaults.set(automaticCompactLyricsFocus, forKey: Key.automaticCompactLyricsFocus) }
    }

    @Published public var connectSpotifyOnLaunch: Bool {
        didSet { defaults.set(connectSpotifyOnLaunch, forKey: Key.connectSpotifyOnLaunch) }
    }

    @Published public var autoSearchLyricsOnTrackChange: Bool {
        didSet { defaults.set(autoSearchLyricsOnTrackChange, forKey: Key.autoSearchLyricsOnTrackChange) }
    }

    /// When enabled, playing an unsynced plain-lyrics track may auto-capture and align.
    @Published public var automaticAlignmentEnabled: Bool {
        didSet { defaults.set(automaticAlignmentEnabled, forKey: Key.automaticAlignmentEnabled) }
    }

    @Published public var keepMainWindowOnTop: Bool {
        didSet { defaults.set(keepMainWindowOnTop, forKey: Key.keepMainWindowOnTop) }
    }

    @Published public var restoreWindowState: Bool {
        didSet { defaults.set(restoreWindowState, forKey: Key.restoreWindowState) }
    }

    @Published public var floatingWindowAlwaysOnTop: Bool {
        didSet { defaults.set(floatingWindowAlwaysOnTop, forKey: Key.floatingWindowAlwaysOnTop) }
    }

    @Published public var floatingWindowInteractionModeRawValue: String {
        didSet { defaults.set(floatingWindowInteractionModeRawValue, forKey: Key.floatingWindowInteractionMode) }
    }

    @Published public var floatingWindowWasVisible: Bool {
        didSet { defaults.set(floatingWindowWasVisible, forKey: Key.floatingWindowWasVisible) }
    }

    @Published public var floatingWindowOpacity: Double {
        didSet { defaults.set(floatingWindowOpacity, forKey: Key.floatingWindowOpacity) }
    }

    @Published public var floatingLyricsPresentationRawValue: String {
        didSet { defaults.set(floatingLyricsPresentationRawValue, forKey: Key.floatingLyricsPresentation) }
    }

    @Published public var floatingLyricsSurfaceStyleRawValue: String {
        didSet { defaults.set(floatingLyricsSurfaceStyleRawValue, forKey: Key.floatingLyricsSurfaceStyle) }
    }

    /// Top-capsule state is intentionally internal persistence rather than a
    /// second user-facing settings store.  Only the horizontal offset and
    /// target display are restored; hover/expanded are transient.
    @Published public var capsuleWindowHorizontalOffset: Double {
        didSet { defaults.set(capsuleWindowHorizontalOffset, forKey: Key.capsuleWindowHorizontalOffset) }
    }

    @Published public var capsuleWindowScreenID: String? {
        didSet {
            if let capsuleWindowScreenID, !capsuleWindowScreenID.isEmpty {
                defaults.set(capsuleWindowScreenID, forKey: Key.capsuleWindowScreenID)
            } else {
                defaults.removeObject(forKey: Key.capsuleWindowScreenID)
            }
        }
    }

    @Published public var capsuleWindowWasVisible: Bool {
        didSet { defaults.set(capsuleWindowWasVisible, forKey: Key.capsuleWindowWasVisible) }
    }

    @Published public var displayPreferences: DisplayPreferences {
        didSet { persistDisplayPreferences(displayPreferences) }
    }

    @Published public var readingPreferences: ReadingPreferences {
        didSet { persistReadingPreferences(readingPreferences) }
    }

    @Published public var lyricsProviderConfiguration: LyricsProviderConfiguration {
        didSet { persistProviderConfiguration(lyricsProviderConfiguration) }
    }

    /// Free lyrics source mode (standard vs experimental). Defaults to
    /// standard free. Changing this rebuilds the online provider chain without
    /// touching SQLite versions or TrackIdentity.
    @Published public var lyricsSourceModeRawValue: String {
        didSet { defaults.set(lyricsSourceModeRawValue, forKey: Key.lyricsSourceMode) }
    }

    public var lyricsSourceMode: LyricsSourceMode {
        get { LyricsSourceMode(rawValue: lyricsSourceModeRawValue) ?? .standardFree }
        set { lyricsSourceModeRawValue = newValue.rawValue }
    }

    @Published public var aiTranslationConfiguration: AITranslationConfiguration {
        didSet { persistAITranslationConfiguration(aiTranslationConfiguration) }
    }

    /// This is only a non-secret status flag. The key material itself remains
    /// exclusively in Keychain and is never mirrored into UserDefaults.
    @Published public var aiTranslationAPIKeyConfigured: Bool {
        didSet { defaults.set(aiTranslationAPIKeyConfigured, forKey: Key.aiAPIKeyConfigured) }
    }

    @Published public var v3BackdropBlurRadius: Double {
        didSet { defaults.set(v3BackdropBlurRadius, forKey: Key.v3BackdropBlurRadius) }
    }

    @Published public var v3ArtworkPosition: String {
        didSet { defaults.set(v3ArtworkPosition, forKey: Key.v3ArtworkPosition) }
    }

    @Published public var v3ArtworkSizeScale: Double {
        didSet { defaults.set(v3ArtworkSizeScale, forKey: Key.v3ArtworkSizeScale) }
    }

    @Published public var v3InstrumentalPureImmersion: Bool {
        didSet { defaults.set(v3InstrumentalPureImmersion, forKey: Key.v3InstrumentalPureImmersion) }
    }

    /// Model names are non-secret metadata. The directory is cached so the
    /// settings page can be browsed without touching Keychain.
    @Published public private(set) var aiModelDirectoryStatus: TranslationModelDirectoryStatus
    @Published public private(set) var aiCachedModels: [TranslationModelDescriptor]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.v3BackdropBlurRadius = defaults.object(forKey: Key.v3BackdropBlurRadius) as? Double ?? 36.0
        self.v3ArtworkPosition = defaults.string(forKey: Key.v3ArtworkPosition) ?? "left"
        self.v3ArtworkSizeScale = defaults.object(forKey: Key.v3ArtworkSizeScale) as? Double ?? 1.0
        self.v3InstrumentalPureImmersion = defaults.object(forKey: Key.v3InstrumentalPureImmersion) as? Bool ?? true
        self.presentationSelections = PresentationSelectionStore(defaults: defaults)
        self.translationProfiles = TranslationProfileStore(defaults: defaults)
        self.readingUserDictionary = ReadingUserDictionaryStore(defaults: defaults)
        settingsCenterPresentationRawValue = defaults.string(forKey: Key.settingsCenterPresentation)
            ?? SettingsCenterPresentationID.recommended.rawValue
        let layout = defaults.string(forKey: Key.mainWindowLayoutStyle)
            ?? MainWindowLayoutStyle.appleMusicImmersiveV3.rawValue
        mainWindowLayoutStyleRawValue = layout
        automaticCompactLyricsFocus = defaults.object(forKey: Key.automaticCompactLyricsFocus) as? Bool ?? false
        connectSpotifyOnLaunch = defaults.object(forKey: Key.connectSpotifyOnLaunch) as? Bool ?? true
        autoSearchLyricsOnTrackChange = defaults.object(forKey: Key.autoSearchLyricsOnTrackChange) as? Bool ?? true
        automaticAlignmentEnabled = defaults.object(forKey: Key.automaticAlignmentEnabled) as? Bool ?? false
        // Keep the normal window behavior by default. Users can opt into
        // always-on-top explicitly in Settings; existing saved choices are
        // preserved because the fallback is only used when the key is absent.
        let keepOnTop = defaults.object(forKey: Key.keepMainWindowOnTop) as? Bool ?? false
        keepMainWindowOnTop = keepOnTop
        restoreWindowState = defaults.object(forKey: Key.restoreWindowState) as? Bool ?? true
        floatingWindowAlwaysOnTop = defaults.object(forKey: Key.floatingWindowAlwaysOnTop) as? Bool ?? true
        floatingWindowInteractionModeRawValue = defaults.string(forKey: Key.floatingWindowInteractionMode)
            ?? "interactive"
        floatingWindowWasVisible = defaults.object(forKey: Key.floatingWindowWasVisible) as? Bool ?? false
        floatingWindowOpacity = defaults.object(forKey: Key.floatingWindowOpacity) as? Double ?? 0.96
        floatingLyricsPresentationRawValue = defaults.string(forKey: Key.floatingLyricsPresentation)
            ?? FloatingLyricsPresentationVersion.current.rawValue
        floatingLyricsSurfaceStyleRawValue = defaults.string(forKey: Key.floatingLyricsSurfaceStyle)
            ?? FloatingLyricsSurfaceStyle.ultraTransparent.rawValue
        capsuleWindowHorizontalOffset = defaults.object(forKey: Key.capsuleWindowHorizontalOffset) as? Double ?? 0
        capsuleWindowScreenID = defaults.string(forKey: Key.capsuleWindowScreenID)
        capsuleWindowWasVisible = defaults.object(forKey: Key.capsuleWindowWasVisible) as? Bool ?? false
        displayPreferences = Self.loadDisplayPreferences(defaults: defaults, keepOnTop: keepOnTop)
        readingPreferences = Self.loadReadingPreferences(defaults: defaults)
        lyricsProviderConfiguration = Self.loadProviderConfiguration(defaults: defaults)
        lyricsSourceModeRawValue = defaults.string(forKey: Key.lyricsSourceMode)
            ?? LyricsSourceMode.standardFree.rawValue
        aiTranslationConfiguration = Self.loadAITranslationConfiguration(defaults: defaults)
        aiTranslationAPIKeyConfigured = defaults.object(forKey: Key.aiAPIKeyConfigured) as? Bool ?? false
        let cachedModels = Self.loadCachedModels(defaults: defaults)
        aiCachedModels = cachedModels
        aiModelDirectoryStatus = cachedModels.isEmpty ? .idle : .loaded(cachedModels)

        if defaults.object(forKey: Key.settingsVersion) == nil {
            defaults.set(Self.currentSettingsVersion, forKey: Key.settingsVersion)
        }
    }

    var mainWindowLayoutStyle: MainWindowLayoutStyle {
        MainWindowLayoutStyle(rawValue: mainWindowLayoutStyleRawValue) ?? .appleMusicImmersiveV3
    }

    public var settingsCenterPresentation: SettingsCenterPresentationID {
        get {
            SettingsCenterPresentationID(rawValue: settingsCenterPresentationRawValue)
                ?? SettingsCenterPresentationID.recommended
        }
        set { settingsCenterPresentationRawValue = newValue.rawValue }
    }

    public var floatingWindowInteractionMode: FloatingLyricsInteractionMode {
        get { FloatingLyricsInteractionMode(rawValue: floatingWindowInteractionModeRawValue) ?? .interactive }
        set { floatingWindowInteractionModeRawValue = newValue.rawValue }
    }

    public var floatingLyricsPresentation: FloatingLyricsPresentationVersion {
        get {
            FloatingLyricsPresentationVersion(rawValue: floatingLyricsPresentationRawValue)
                ?? .current
        }
        set { floatingLyricsPresentationRawValue = newValue.rawValue }
    }

    public var floatingLyricsSurfaceStyle: FloatingLyricsSurfaceStyle {
        get {
            FloatingLyricsSurfaceStyle(rawValue: floatingLyricsSurfaceStyleRawValue)
                ?? .ultraTransparent
        }
        set { floatingLyricsSurfaceStyleRawValue = newValue.rawValue }
    }

    public var savedFloatingWindowFrame: String? {
        defaults.string(forKey: Key.floatingWindowFrame)
    }

    public var savedFloatingWindowScreenID: String? {
        defaults.string(forKey: Key.floatingWindowScreenID)
    }

    public func saveFloatingWindowFrame(_ frame: String, screenID: String?) {
        defaults.set(frame, forKey: Key.floatingWindowFrame)
        if let screenID, !screenID.isEmpty {
            defaults.set(screenID, forKey: Key.floatingWindowScreenID)
        } else {
            defaults.removeObject(forKey: Key.floatingWindowScreenID)
        }
    }

    public var schemaVersion: Int { DatabaseMigrator.currentVersion }

    /// A manually entered model remains usable even when `/models` is empty,
    /// unsupported, or temporarily unavailable. The raw status is retained
    /// for diagnostics; this presentation status tells the settings UI that
    /// the current model is intentionally being kept as a manual fallback.
    public var aiModelDirectoryDisplayStatus: TranslationModelDirectoryStatus {
        let model = aiTranslationConfiguration.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { return aiModelDirectoryStatus }
        switch aiModelDirectoryStatus {
        case .idle, .empty, .unauthorized, .endpointUnsupported, .unavailable:
            return .manualFallback
        case .loading, .loaded, .manualFallback:
            return aiModelDirectoryStatus
        }
    }

    /// Explicit user action only. Reading model names is the only operation
    /// here that touches the API-key store; opening or browsing settings does
    /// not call this method.
    public func refreshAIModelDirectory() {
        let configuration = aiTranslationConfiguration
        guard configuration.engineID == TranslationEngineID.openAICompatible.rawValue else {
            aiModelDirectoryStatus = .unavailable("当前翻译引擎不提供在线模型目录")
            return
        }
        guard configuration.isConfigured else {
            aiModelDirectoryStatus = .unavailable("请先填写 Base URL 和模型")
            return
        }
        aiModelDirectoryStatus = .loading
        let client = OpenAICompatibleClient()
        let keyStore = KeychainAITranslationAPIKeyStore()
        Task { [weak self] in
            do {
                guard let key = keyStore.read(), !key.isEmpty else {
                    throw AITranslationError.missingAPIKey
                }
                let models = try await client.listModels(configuration: configuration, apiKey: key)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.aiCachedModels = models
                    self.aiModelDirectoryStatus = models.isEmpty ? .empty : .loaded(models)
                    if let data = try? JSONEncoder().encode(models) {
                        self.defaults.set(data, forKey: Key.aiModelDirectoryCache)
                    }
                    self.defaults.set(Date(), forKey: Key.aiModelDirectoryRefreshedAt)
                }
            } catch let error as AITranslationError {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    switch error {
                    case .server(404), .server(405):
                        self.aiModelDirectoryStatus = .endpointUnsupported
                    case .unauthorized:
                        self.aiModelDirectoryStatus = .unauthorized
                    default:
                        self.aiModelDirectoryStatus = .unavailable(error.localizedDescription)
                    }
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.aiModelDirectoryStatus = .unavailable("模型目录暂时不可用")
                }
            }
        }
    }

    /// Returns whether a catalog item can be applied to a live runtime
    /// setting. Design-only entries remain browseable but do not become
    /// formal selections. Debug-only entries are likewise rejected by their
    /// catalog availability; v4 is intentionally Release-capable.
    public func canApplyPresentation(
        category: PresentationCategory,
        stableID: String
    ) -> Bool {
        guard let metadata = presentationSelections.catalog.metadata(for: stableID),
              metadata.category == category,
              metadata.availability == .release else {
            return false
        }

        switch category {
        case .mainWindow:
            return [
                "mainWindow.lyricsFocus.v1",
                "mainWindow.immersiveSplit.v2",
                "mainWindow.appleMusicImmersiveV3.v3",
                "mainWindow.directionD.v4"
            ].contains(stableID)
        case .capsule:
            return CapsuleLyricsPresentationVersion(rawValue: stableID) != nil
        case .floatingLyrics:
            return FloatingLyricsPresentationVersion(rawValue: stableID) != nil
        case .backdrop, .lyricsTransition, .lyricsState, .progress, .responsiveLayout:
            return true
        case .fullscreen:
            // The current fullscreen controller has one maintained runtime
            // surface. Its catalog entry remains previewable, but there is no
            // second user-selectable fullscreen implementation yet.
            return false
        }
    }

    /// Applies a catalog selection to the existing runtime settings. This is
    /// the only bridge between the selection catalog and maintained runtime
    /// settings; it does not create a second state source.
    @discardableResult
    public func applyPresentationSelection(
        category: PresentationCategory,
        stableID: String
    ) -> Bool {
        guard canApplyPresentation(category: category, stableID: stableID),
              presentationSelections.apply(category: category, stableID: stableID) else {
            return false
        }

        switch category {
        case .mainWindow:
            let rawValue: String
            switch stableID {
            case "mainWindow.lyricsFocus.v1": rawValue = MainWindowLayoutStyle.lyricsFocus.rawValue
            case "mainWindow.immersiveSplit.v2": rawValue = MainWindowLayoutStyle.immersiveSplit.rawValue
            case "mainWindow.appleMusicImmersiveV3.v3": rawValue = MainWindowLayoutStyle.appleMusicImmersiveV3.rawValue
            case "mainWindow.directionD.v4": rawValue = MainWindowLayoutStyle.directionDV4.rawValue
            default: return false
            }
            mainWindowLayoutStyleRawValue = rawValue
        case .capsule:
            defaults.set(stableID, forKey: PresentationSelectionStore.runtimeKey(for: category))
        case .floatingLyrics:
            floatingLyricsPresentationRawValue = stableID
        case .backdrop, .lyricsTransition, .lyricsState, .progress, .responsiveLayout:
            defaults.set(stableID, forKey: PresentationSelectionStore.runtimeKey(for: category))
        case .fullscreen:
            break
        }
        return true
    }

    @discardableResult
    public func restoreRecommendedPresentation(for category: PresentationCategory) -> String {
        let stableID = presentationSelections.restoreRecommended(for: category)
        guard canApplyPresentation(category: category, stableID: stableID) else {
            return stableID
        }
        _ = applyRuntimePresentation(category: category, stableID: stableID)
        return stableID
    }

    private func applyRuntimePresentation(category: PresentationCategory, stableID: String) -> Bool {
        switch category {
        case .mainWindow:
            let rawValue: String
            switch stableID {
            case "mainWindow.lyricsFocus.v1": rawValue = MainWindowLayoutStyle.lyricsFocus.rawValue
            case "mainWindow.immersiveSplit.v2": rawValue = MainWindowLayoutStyle.immersiveSplit.rawValue
            case "mainWindow.appleMusicImmersiveV3.v3": rawValue = MainWindowLayoutStyle.appleMusicImmersiveV3.rawValue
            case "mainWindow.directionD.v4": rawValue = MainWindowLayoutStyle.directionDV4.rawValue
            default: return false
            }
            mainWindowLayoutStyleRawValue = rawValue
        case .floatingLyrics:
            guard FloatingLyricsPresentationVersion(rawValue: stableID) != nil else { return false }
            floatingLyricsPresentationRawValue = stableID
        case .capsule, .backdrop, .lyricsTransition, .lyricsState, .progress, .responsiveLayout:
            defaults.set(stableID, forKey: PresentationSelectionStore.runtimeKey(for: category))
        case .fullscreen:
            return false
        }
        return true
    }

    public func setProviderEnabled(_ id: LyricsProviderID, enabled: Bool) {
        guard !id.isLocal else { return }
        // Experimental providers cannot be "armed" while standard free is
        // selected — mode is the single gate. Preferences still keep order.
        if id.isExperimental, !lyricsSourceMode.allowsExperimentalProviders, enabled {
            return
        }
        var configuration = lyricsProviderConfiguration
        if enabled {
            configuration.enabled.insert(id)
        } else {
            configuration.enabled.remove(id)
        }
        configuration.normalize()
        lyricsProviderConfiguration = configuration
    }

    public func isProviderEnabled(_ id: LyricsProviderID) -> Bool {
        lyricsProviderConfiguration.enabled.contains(id)
    }

    /// Preference toggle on, and allowed by the active source mode.
    public func isProviderActiveInCurrentMode(_ id: LyricsProviderID) -> Bool {
        isProviderEnabled(id) && id.isAllowed(in: lyricsSourceMode)
    }

    public func moveProvider(_ id: LyricsProviderID, offset: Int) {
        var configuration = lyricsProviderConfiguration
        guard let index = configuration.order.firstIndex(of: id) else { return }
        let nextIndex = index + offset
        guard configuration.order.indices.contains(nextIndex) else { return }
        configuration.order.swapAt(index, nextIndex)
        lyricsProviderConfiguration = configuration
    }

    /// Restores the recommended free mode (standard). Does not wipe SQLite,
    /// provider order, or individual enable flags.
    public func restoreDefaultLyricsSourceMode() {
        lyricsSourceMode = .standardFree
    }

    public func resetWindowState() {
        defaults.removeObject(forKey: Key.mainWindowFrame)
        defaults.removeObject(forKey: Key.floatingWindowFrame)
        defaults.removeObject(forKey: Key.floatingWindowScreenID)
        defaults.removeObject(forKey: Key.capsuleWindowHorizontalOffset)
        defaults.removeObject(forKey: Key.capsuleWindowScreenID)
        floatingWindowWasVisible = false
        capsuleWindowHorizontalOffset = 0
        capsuleWindowScreenID = nil
        capsuleWindowWasVisible = false
        WindowStatePersistence.shared.resetWindowFrame()
    }

    public var savedWindowFrame: String? {
        defaults.string(forKey: Key.mainWindowFrame)
    }

    private func persistDisplayPreferences(_ preferences: DisplayPreferences) {
        defaults.set(preferences.showOriginal, forKey: Key.showOriginal)
        defaults.set(preferences.showTranslation, forKey: Key.showTranslation)
        defaults.set(preferences.showRomaji, forKey: Key.showRomaji)
        defaults.set(preferences.showPinyin, forKey: Key.showPinyin)
        defaults.set(preferences.kanaDisplayMode.rawValue, forKey: Key.kanaDisplayMode)
        defaults.set(Double(preferences.fontSize), forKey: Key.fontSize)
        defaults.set(Double(preferences.assistantFontSize), forKey: Key.assistantFontSize)
        defaults.set(preferences.opacity, forKey: Key.inactiveOpacity)
        defaults.set(Double(preferences.rubyFontSize), forKey: Key.rubyFontSize)
        defaults.set(preferences.hideDistantAuxiliary, forKey: Key.hideDistantAuxiliary)
    }

    private static func loadDisplayPreferences(defaults: UserDefaults, keepOnTop: Bool) -> DisplayPreferences {
        let rawMode = defaults.string(forKey: Key.kanaDisplayMode)
        let mode = rawMode.flatMap(KanaDisplayMode.init(rawValue:)) ?? .hidden
        return DisplayPreferences(
            showOriginal: defaults.object(forKey: Key.showOriginal) as? Bool ?? true,
            showTranslation: defaults.object(forKey: Key.showTranslation) as? Bool ?? true,
            showRomaji: defaults.object(forKey: Key.showRomaji) as? Bool ?? true,
            showPinyin: defaults.object(forKey: Key.showPinyin) as? Bool ?? true,
            kanaDisplayMode: mode,
            fontSize: CGFloat(defaults.object(forKey: Key.fontSize) as? Double ?? 18),
            opacity: defaults.object(forKey: Key.inactiveOpacity) as? Double ?? 0.85,
            alwaysOnTop: keepOnTop,
            assistantFontSize: CGFloat(defaults.object(forKey: Key.assistantFontSize) as? Double ?? 14),
            rubyFontSize: CGFloat(defaults.object(forKey: Key.rubyFontSize) as? Double ?? 10),
            hideDistantAuxiliary: defaults.object(forKey: Key.hideDistantAuxiliary) as? Bool ?? true
        )
    }

    private static func loadReadingPreferences(defaults: UserDefaults) -> ReadingPreferences {
        guard let data = defaults.data(forKey: Key.readingPreferences),
              let value = try? JSONDecoder().decode(ReadingPreferences.self, from: data) else {
            return ReadingPreferences()
        }
        return value
    }

    private func persistReadingPreferences(_ preferences: ReadingPreferences) {
        if let data = try? JSONEncoder().encode(preferences) {
            defaults.set(data, forKey: Key.readingPreferences)
        }
    }

    private static func loadProviderConfiguration(defaults: UserDefaults) -> LyricsProviderConfiguration {
        let order = (defaults.array(forKey: Key.providerOrder) as? [String] ?? [])
            .compactMap(LyricsProviderID.init(rawValue:))
        let enabled = (defaults.array(forKey: Key.providerEnabled) as? [String] ?? [])
            .compactMap(LyricsProviderID.init(rawValue:))
        if order.isEmpty && enabled.isEmpty {
            return .default
        }
        return LyricsProviderConfiguration(
            enabled: enabled.isEmpty ? Set(LyricsProviderID.allCases) : Set(enabled),
            order: order.isEmpty ? LyricsProviderConfiguration.default.order : order
        )
    }

    private func persistProviderConfiguration(_ configuration: LyricsProviderConfiguration) {
        defaults.set(configuration.order.map(\.rawValue), forKey: Key.providerOrder)
        defaults.set(configuration.enabled.map(\.rawValue).sorted(), forKey: Key.providerEnabled)
    }

    private static func loadAITranslationConfiguration(defaults: UserDefaults) -> AITranslationConfiguration {
        AITranslationConfiguration(
            baseURL: defaults.string(forKey: Key.aiBaseURL) ?? "",
            model: defaults.string(forKey: Key.aiModel) ?? "",
            targetLanguage: defaults.string(forKey: Key.aiTargetLanguage) ?? "zh-Hans",
            style: defaults.string(forKey: Key.aiStyle) ?? "natural_song",
            customSystemPrompt: defaults.string(forKey: Key.aiCustomSystemPrompt) ?? "",
            temperature: defaults.object(forKey: Key.aiTemperature) as? Double ?? 0.2,
            timeout: defaults.object(forKey: Key.aiTimeout) as? Double ?? 60,
            autoTranslateNewLyrics: defaults.object(forKey: Key.aiAutoTranslateNewLyrics) as? Bool ?? false,
            engineID: defaults.string(forKey: Key.aiEngineID) ?? TranslationEngineID.openAICompatible.rawValue,
            promptPresetID: defaults.string(forKey: Key.aiPromptPresetID) ?? TranslationPromptPresetID.naturalSong.rawValue,
            profileID: defaults.string(forKey: Key.aiProfileID).flatMap(UUID.init(uuidString:)),
            profileSnapshot: defaults.string(forKey: Key.aiProfileSnapshot) ?? "",
            fallbackStrategy: TranslationFallbackStrategy(rawValue: defaults.string(forKey: Key.aiFallbackStrategy) ?? "none") ?? .none,
            workflowID: defaults.string(forKey: Key.aiWorkflowID) ?? TranslationWorkflowID.contextualV2.rawValue
        )
    }

    private func persistAITranslationConfiguration(_ configuration: AITranslationConfiguration) {
        defaults.set(configuration.baseURL, forKey: Key.aiBaseURL)
        defaults.set(configuration.model, forKey: Key.aiModel)
        defaults.set(configuration.targetLanguage, forKey: Key.aiTargetLanguage)
        defaults.set(configuration.style, forKey: Key.aiStyle)
        defaults.set(configuration.customSystemPrompt, forKey: Key.aiCustomSystemPrompt)
        defaults.set(configuration.temperature, forKey: Key.aiTemperature)
        defaults.set(configuration.timeout, forKey: Key.aiTimeout)
        defaults.set(configuration.autoTranslateNewLyrics, forKey: Key.aiAutoTranslateNewLyrics)
        defaults.set(configuration.engineID, forKey: Key.aiEngineID)
        defaults.set(configuration.promptPresetID, forKey: Key.aiPromptPresetID)
        if let profileID = configuration.profileID {
            defaults.set(profileID.uuidString, forKey: Key.aiProfileID)
        } else {
            defaults.removeObject(forKey: Key.aiProfileID)
        }
        defaults.set(configuration.profileSnapshot, forKey: Key.aiProfileSnapshot)
        defaults.set(configuration.fallbackStrategy.rawValue, forKey: Key.aiFallbackStrategy)
        defaults.set(configuration.workflowID, forKey: Key.aiWorkflowID)
    }

    private static func loadCachedModels(defaults: UserDefaults) -> [TranslationModelDescriptor] {
        guard let data = defaults.data(forKey: Key.aiModelDirectoryCache),
              let models = try? JSONDecoder().decode([TranslationModelDescriptor].self, from: data) else { return [] }
        return models
    }
}

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
        public static let connectSpotifyOnLaunch = "general.connectSpotifyOnLaunch"
        public static let autoSearchLyricsOnTrackChange = "general.autoSearchLyricsOnTrackChange"
        public static let keepMainWindowOnTop = "general.keepMainWindowOnTop"
        public static let restoreWindowState = "general.restoreWindowState"
        public static let mainWindowFrame = "general.mainWindowFrame"
        public static let floatingWindowFrame = "general.floatingWindowFrame"
        public static let floatingWindowScreenID = "general.floatingWindowScreenID"
        public static let floatingWindowAlwaysOnTop = "general.floatingWindowAlwaysOnTop"
        public static let floatingWindowInteractionMode = "general.floatingWindowInteractionMode"
        public static let floatingWindowWasVisible = "general.floatingWindowWasVisible"
        public static let floatingWindowOpacity = "general.floatingWindowOpacity"
        public static let showOriginal = "display.showOriginal"
        public static let showTranslation = "display.showTranslation"
        public static let showRomaji = "display.showRomaji"
        public static let kanaDisplayMode = "display.kanaDisplayMode"
        public static let fontSize = "display.fontSize"
        public static let assistantFontSize = "display.assistantFontSize"
        public static let inactiveOpacity = "display.inactiveOpacity"
        public static let rubyFontSize = "display.rubyFontSize"
        public static let hideDistantAuxiliary = "display.hideDistantAuxiliary"
        public static let providerEnabled = "lyrics.providers.enabled"
        public static let providerOrder = "lyrics.providers.order"
        public static let aiBaseURL = "ai.baseURL"
        public static let aiModel = "ai.model"
        public static let aiTargetLanguage = "ai.targetLanguage"
        public static let aiStyle = "ai.style"
        public static let aiCustomSystemPrompt = "ai.customSystemPrompt"
        public static let aiTemperature = "ai.temperature"
        public static let aiTimeout = "ai.timeout"
        public static let aiAutoTranslateNewLyrics = "ai.autoTranslateNewLyrics"
    }

    public static let currentSettingsVersion = 1

    private let defaults: UserDefaults

    @Published public var mainWindowLayoutStyleRawValue: String {
        didSet { defaults.set(mainWindowLayoutStyleRawValue, forKey: Key.mainWindowLayoutStyle) }
    }

    @Published public var connectSpotifyOnLaunch: Bool {
        didSet { defaults.set(connectSpotifyOnLaunch, forKey: Key.connectSpotifyOnLaunch) }
    }

    @Published public var autoSearchLyricsOnTrackChange: Bool {
        didSet { defaults.set(autoSearchLyricsOnTrackChange, forKey: Key.autoSearchLyricsOnTrackChange) }
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

    @Published public var displayPreferences: DisplayPreferences {
        didSet { persistDisplayPreferences(displayPreferences) }
    }

    @Published public var lyricsProviderConfiguration: LyricsProviderConfiguration {
        didSet { persistProviderConfiguration(lyricsProviderConfiguration) }
    }

    @Published public var aiTranslationConfiguration: AITranslationConfiguration {
        didSet { persistAITranslationConfiguration(aiTranslationConfiguration) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let layout = defaults.string(forKey: Key.mainWindowLayoutStyle)
            ?? MainWindowLayoutStyle.appleMusicImmersiveV3.rawValue
        mainWindowLayoutStyleRawValue = layout
        connectSpotifyOnLaunch = defaults.object(forKey: Key.connectSpotifyOnLaunch) as? Bool ?? true
        autoSearchLyricsOnTrackChange = defaults.object(forKey: Key.autoSearchLyricsOnTrackChange) as? Bool ?? true
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
        displayPreferences = Self.loadDisplayPreferences(defaults: defaults, keepOnTop: keepOnTop)
        lyricsProviderConfiguration = Self.loadProviderConfiguration(defaults: defaults)
        aiTranslationConfiguration = Self.loadAITranslationConfiguration(defaults: defaults)

        if defaults.object(forKey: Key.settingsVersion) == nil {
            defaults.set(Self.currentSettingsVersion, forKey: Key.settingsVersion)
        }
    }

    var mainWindowLayoutStyle: MainWindowLayoutStyle {
        MainWindowLayoutStyle(rawValue: mainWindowLayoutStyleRawValue) ?? .appleMusicImmersiveV3
    }

    public var floatingWindowInteractionMode: FloatingLyricsInteractionMode {
        get { FloatingLyricsInteractionMode(rawValue: floatingWindowInteractionModeRawValue) ?? .interactive }
        set { floatingWindowInteractionModeRawValue = newValue.rawValue }
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

    public func setProviderEnabled(_ id: LyricsProviderID, enabled: Bool) {
        guard !id.isLocal else { return }
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

    public func moveProvider(_ id: LyricsProviderID, offset: Int) {
        var configuration = lyricsProviderConfiguration
        guard let index = configuration.order.firstIndex(of: id) else { return }
        let nextIndex = index + offset
        guard configuration.order.indices.contains(nextIndex) else { return }
        configuration.order.swapAt(index, nextIndex)
        lyricsProviderConfiguration = configuration
    }

    public func resetWindowState() {
        defaults.removeObject(forKey: Key.mainWindowFrame)
        defaults.removeObject(forKey: Key.floatingWindowFrame)
        defaults.removeObject(forKey: Key.floatingWindowScreenID)
        floatingWindowWasVisible = false
        WindowStatePersistence.shared.resetWindowFrame()
    }

    public var savedWindowFrame: String? {
        defaults.string(forKey: Key.mainWindowFrame)
    }

    private func persistDisplayPreferences(_ preferences: DisplayPreferences) {
        defaults.set(preferences.showOriginal, forKey: Key.showOriginal)
        defaults.set(preferences.showTranslation, forKey: Key.showTranslation)
        defaults.set(preferences.showRomaji, forKey: Key.showRomaji)
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
            kanaDisplayMode: mode,
            fontSize: CGFloat(defaults.object(forKey: Key.fontSize) as? Double ?? 18),
            opacity: defaults.object(forKey: Key.inactiveOpacity) as? Double ?? 0.85,
            alwaysOnTop: keepOnTop,
            assistantFontSize: CGFloat(defaults.object(forKey: Key.assistantFontSize) as? Double ?? 14),
            rubyFontSize: CGFloat(defaults.object(forKey: Key.rubyFontSize) as? Double ?? 10),
            hideDistantAuxiliary: defaults.object(forKey: Key.hideDistantAuxiliary) as? Bool ?? true
        )
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
            autoTranslateNewLyrics: defaults.object(forKey: Key.aiAutoTranslateNewLyrics) as? Bool ?? false
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
    }
}

import Combine
import Foundation

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

    @Published public var displayPreferences: DisplayPreferences {
        didSet { persistDisplayPreferences(displayPreferences) }
    }

    @Published public var lyricsProviderConfiguration: LyricsProviderConfiguration {
        didSet { persistProviderConfiguration(lyricsProviderConfiguration) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let layout = defaults.string(forKey: Key.mainWindowLayoutStyle)
            ?? MainWindowLayoutStyle.appleMusicImmersiveV3.rawValue
        mainWindowLayoutStyleRawValue = layout
        connectSpotifyOnLaunch = defaults.object(forKey: Key.connectSpotifyOnLaunch) as? Bool ?? true
        autoSearchLyricsOnTrackChange = defaults.object(forKey: Key.autoSearchLyricsOnTrackChange) as? Bool ?? true
        let keepOnTop = defaults.object(forKey: Key.keepMainWindowOnTop) as? Bool ?? true
        keepMainWindowOnTop = keepOnTop
        restoreWindowState = defaults.object(forKey: Key.restoreWindowState) as? Bool ?? true
        displayPreferences = Self.loadDisplayPreferences(defaults: defaults, keepOnTop: keepOnTop)
        lyricsProviderConfiguration = Self.loadProviderConfiguration(defaults: defaults)

        if defaults.object(forKey: Key.settingsVersion) == nil {
            defaults.set(Self.currentSettingsVersion, forKey: Key.settingsVersion)
        }
    }

    var mainWindowLayoutStyle: MainWindowLayoutStyle {
        MainWindowLayoutStyle(rawValue: mainWindowLayoutStyleRawValue) ?? .appleMusicImmersiveV3
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
}

import Foundation

/// Stable identities for the two settings-center shells.  They describe the
/// navigation presentation only; both versions read the same AppSettingsStore
/// and Keychain boundary.
public enum SettingsCenterPresentationID: String, CaseIterable, Sendable {
    case classicNavigationV1 = "settingsCenter.classicNavigation.v1"
    case experienceIntegratedV2 = "settingsCenter.experienceIntegrated.v2"

    public static let current: SettingsCenterPresentationID = .experienceIntegratedV2
    public static let recommended: SettingsCenterPresentationID = .experienceIntegratedV2
}

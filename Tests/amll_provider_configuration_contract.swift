import Foundation

@main
struct AMLLProviderConfigurationContract {
    static func main() {
        let legacyOrder: [LyricsProviderID] = [
            .localFiles,
            .sqliteDatabase,
            .lrclib,
            .netEaseExperimental,
            .qqExperimental
        ]
        let migrated = LyricsProviderConfiguration(
            enabled: Set(legacyOrder),
            order: legacyOrder
        )
        precondition(migrated.enabled.contains(.amll))
        precondition(
            migrated.order.firstIndex(of: .amll)! < migrated.order.firstIndex(of: .lrclib)!,
            "legacy settings must migrate AMLL ahead of LRCLIB"
        )

        let explicitDisabled = LyricsProviderConfiguration(
            enabled: [.localFiles, .sqliteDatabase, .lrclib],
            order: [.localFiles, .sqliteDatabase, .amll, .lrclib]
        )
        precondition(!explicitDisabled.enabled.contains(.amll), "explicit AMLL disable must persist")

        print("AMLL provider configuration contract passed")
    }
}

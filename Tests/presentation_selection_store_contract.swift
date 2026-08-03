import Foundation

@main
struct PresentationSelectionStoreContract {
    static func main() {
        let suiteName = "presentation-selection-contract-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // The legacy layout preference must migrate without silently choosing
        // a different presentation.
        defaults.set("appleMusicImmersiveV3", forKey: "mainWindowLayoutStyle")
        let store = PresentationSelectionStore(defaults: defaults)
        precondition(
            store.persistedSelectedStableID(for: .mainWindow) == "mainWindow.appleMusicImmersiveV3.v3",
            "legacy main-window selection was not migrated"
        )
        precondition(
            store.currentStableID(for: .mainWindow) == "mainWindow.appleMusicImmersiveV3.v3",
            "migrated main-window selection was not current"
        )

        let freshSuiteName = "presentation-selection-fresh-\(UUID().uuidString)"
        let freshDefaults = UserDefaults(suiteName: freshSuiteName)!
        freshDefaults.removePersistentDomain(forName: freshSuiteName)
        defer { freshDefaults.removePersistentDomain(forName: freshSuiteName) }
        let freshStore = PresentationSelectionStore(defaults: freshDefaults)
        precondition(
            freshStore.currentStableID(for: .capsule) == "capsule.controlFocused.v2",
            "recommended capsule v4 must not replace the current v2 runtime by default"
        )
        precondition(
            freshStore.recommendedStableID(for: .capsule) == "capsule.dynamicIslandDark.v4",
            "capsule v4 must remain the recommended presentation"
        )

        let persistedBeforePreview = defaults.data(forKey: PresentationSelectionStore.storageKey)
        precondition(
            store.beginPreview(category: .mainWindow, stableID: "mainWindow.lyricsFocus.v1"),
            "preview should accept a runnable catalog entry"
        )
        precondition(
            store.effectiveStableID(for: .mainWindow) == "mainWindow.lyricsFocus.v1",
            "preview did not change only the effective selection"
        )
        precondition(
            store.currentStableID(for: .mainWindow) == "mainWindow.appleMusicImmersiveV3.v3",
            "preview changed the persisted current selection"
        )
        precondition(
            defaults.data(forKey: PresentationSelectionStore.storageKey) == persistedBeforePreview,
            "preview wrote formal UserDefaults"
        )
        store.cancelPreview()
        precondition(
            store.effectiveStableID(for: .mainWindow) == "mainWindow.appleMusicImmersiveV3.v3",
            "cancel did not restore the applied selection"
        )

        precondition(store.beginPreview(category: .mainWindow, stableID: "mainWindow.lyricsFocus.v1"))
        precondition(store.applyPreview(), "explicit Apply should commit a runnable selection")
        let restarted = PresentationSelectionStore(defaults: defaults)
        precondition(
            restarted.currentStableID(for: .mainWindow) == "mainWindow.lyricsFocus.v1",
            "applied selection did not survive a new store instance"
        )

        let rawSelections = ["mainWindow": "unknown.future.v9"]
        defaults.set(try! JSONEncoder().encode(rawSelections), forKey: PresentationSelectionStore.storageKey)
        let unknown = PresentationSelectionStore(defaults: defaults)
        precondition(
            unknown.persistedSelectedStableID(for: .mainWindow) == "unknown.future.v9",
            "unknown persisted ID was discarded"
        )
        precondition(
            unknown.currentStableID(for: .mainWindow) == "mainWindow.appleMusicImmersiveV3.v3",
            "unknown ID did not safely fall back to the category recommendation"
        )

        precondition(
            !unknown.beginPreview(category: .backdrop, stableID: "backdrop.custom.v1"),
            "design-only presentation must not be applied as a runtime preview"
        )
        precondition(
            unknown.apply(category: .capsule, stableID: "capsule.dynamicIslandDark.v4"),
            "Release-capable capsule v4 should be explicitly applicable"
        )
        precondition(
            PresentationCatalog.shared.metadata(for: "capsule.dynamicIslandDark.v4")?.availability == .release,
            "capsule v4 must be marked Release-capable"
        )

        precondition(
            unknown.restoreRecommended(for: .backdrop) == "backdrop.default.v1",
            "Restore Recommended did not choose the backdrop recommendation"
        )
        print("presentation selection store contract: PASS")
    }

}

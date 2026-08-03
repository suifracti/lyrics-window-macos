import Foundation

@main
struct PresentationCatalogPreviewContract {
    static func main() {
        let catalog = PresentationCatalog.shared
        let entries = catalog.entries
        let ids = entries.map(\.stableID)
        let rendererRegistry = PresentationPreviewRendererRegistry.shared

        precondition(Set(ids).count == ids.count, "stable presentation IDs must be unique")
        precondition(catalog.validationIssues().isEmpty, catalog.validationIssues().joined(separator: "; "))

        for entry in entries where entry.supportsMockPreview {
            precondition(rendererRegistry.hasRenderer(for: entry.stableID),
                         "missing Preview Renderer for mock-capable ID \(entry.stableID)")
            precondition(rendererRegistry.descriptor(for: entry.stableID)?.category == entry.category,
                         "renderer category mismatch for \(entry.stableID)")
        }

        precondition(catalog.metadata(for: "capsule.immersiveCompact.v3")?.supportsMockPreview == false,
                     "design-only capsule v3 must not claim a runnable mock renderer")
        precondition(catalog.metadata(for: "capsule.dynamicIslandDark.v4")?.status == .recommended,
                     "v4 must be the recommended capsule presentation")
        precondition(catalog.metadata(for: "capsule.controlFocused.v2")?.status == .current,
                     "v2 must remain the current runtime capsule presentation")

        for category in PresentationCategory.allCases {
            let categoryEntries = catalog.entries(for: category)
            precondition(!categoryEntries.isEmpty, "missing catalog category \(category.rawValue)")
            precondition(categoryEntries.filter { $0.status == .recommended }.count <= 1,
                         "category has more than one recommended presentation")
        }

        for stableID in [
            "backdrop.legacyV3.v1",
            "backdrop.default.v1",
            "backdrop.clear.v1",
            "backdrop.immersive.v1",
            "backdrop.highContrast.v1",
            "backdrop.custom.v1",
            "lyricsTransition.system.v1",
            "lyricsTransition.smoothRelayout.v1",
            "lyricsTransition.none.v1",
            "lyricsStatePresentation.system.v1",
            "lyricsStatePresentation.contentFirst.v1",
            "capsule.controlFocused.v2",
            "capsule.dynamicIslandDark.v4"
        ] {
            precondition(catalog.metadata(for: stableID) != nil, "missing required stable ID \(stableID)")
        }

        let unknown = catalog.resolve(
            stableID: "unknown.presentation.v99",
            category: .capsule
        )
        precondition(unknown.category == .capsule, "unknown ID did not fall back within its category")

        let mock = PresentationPreviewContext.mock(
            surface: .preview,
            windowSize: PresentationPreviewSize(width: 960, height: 640)
        )
        precondition(mock.source == .mock, "mock context has the wrong source")
        precondition(!mock.lyrics.isEmpty, "mock context must contain lyric rows")
        precondition(mock.currentLineIndex != nil, "mock context must contain a current row")

        let engine = PresentationPreviewEngine(catalog: catalog)
        let comparison = engine.compare(
            leftID: "mainWindow.appleMusicImmersiveV3.v3",
            rightID: "mainWindow.lyricsFocus.v1",
            context: mock
        )
        precondition(comparison != nil, "preview comparison could not resolve catalog entries")
        precondition(comparison?.usesSameSnapshot == true, "A/B preview did not share one immutable snapshot")
        precondition(comparison?.leftSnapshotKey == mock.snapshotKey, "left preview changed the snapshot")
        precondition(comparison?.rightSnapshotKey == mock.snapshotKey, "right preview changed the snapshot")

        precondition(rendererRegistry.signature(for: "mainWindow.appleMusicImmersiveV3.v3")
            != rendererRegistry.signature(for: "mainWindow.lyricsFocus.v1"),
                     "Main Window preview signatures must differ")
        precondition(rendererRegistry.signature(for: "capsule.controlFocused.v2")
            != rendererRegistry.signature(for: "capsule.dynamicIslandDark.v4"),
                     "Capsule preview signatures must differ")
        precondition(rendererRegistry.signature(for: "backdrop.clear.v1")
            != rendererRegistry.signature(for: "backdrop.immersive.v1"),
                     "Backdrop preview signatures must differ")

        print("presentation catalog/preview contract: PASS")
    }
}

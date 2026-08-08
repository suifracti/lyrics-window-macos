import Foundation

@main
struct V3ResponsiveGeometryContract {
    static func main() {
        let narrowCover = V3ResponsiveGeometry.boundedCoverSize(
            availableWidth: 170,
            availableHeight: 120,
            desiredSize: 300,
            minimum: 180
        )
        precondition(narrowCover <= 120.001, "cover must not exceed the narrowest available dimension")

        let split = V3ResponsiveGeometry.splitColumns(
            containerWidth: 760,
            requestedArtworkRatio: 0.45,
            gap: 28,
            minimumArtworkWidth: 220,
            minimumLyricsWidth: 300
        )
        precondition(abs(split.artwork + split.lyrics + split.gap - 760) < 0.001, "columns must fill the container exactly")
        precondition(split.artwork >= 0 && split.lyrics >= 0 && split.gap >= 0, "columns must never be negative")
        precondition(split.lyrics >= 300 - 0.001, "lyrics must retain a readable minimum when the container allows it")

        let portrait = V3ResponsiveGeometry.stageArtworkRect(
            canvasSize: CGSize(width: 800, height: 500),
            artworkAspectRatio: 0.65,
            requestedScale: 1.4,
            position: "left"
        )
        precondition(portrait.minX >= 18 - 0.001 && portrait.maxX <= 782 + 0.001, "stage artwork must stay inside the horizontal canvas")
        precondition(portrait.minY >= 16 - 0.001 && portrait.maxY <= 484 + 0.001, "stage artwork must stay inside the vertical safe area")
        precondition(abs(portrait.width / portrait.height - 0.65) < 0.001, "stage artwork must preserve its source aspect ratio")

        print("V3 responsive geometry contract: PASS")
    }
}

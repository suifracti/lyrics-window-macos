import AppKit

@main
struct BackdropPaletteContract {
    static func main() {
        let vivid = BackdropPalette.from(image: solidImage(red: 0.98, green: 0.12, blue: 0.08))
        precondition(vivid.saturation > 0.5)
        precondition(vivid.readabilityVeilOpacity >= 0.24)
        precondition(vivid.textureOpacity > 0)
        precondition(vivid.primary.red > 0.5)

        let bright = BackdropPalette.from(image: solidImage(red: 0.98, green: 0.98, blue: 0.98))
        precondition(bright.readabilityVeilOpacity >= 0.30)

        let dark = BackdropPalette.from(image: solidImage(red: 0.01, green: 0.01, blue: 0.02))
        precondition(dark.readabilityVeilOpacity >= 0.15)

        let singleColor = BackdropPalette.from(image: solidImage(red: 0.32, green: 0.32, blue: 0.32))
        precondition(abs(singleColor.primary.red - singleColor.primary.green) < 0.08)
        precondition(abs(singleColor.primary.green - singleColor.primary.blue) < 0.08)
        print("backdrop palette contract passed")
    }

    private static func solidImage(red: CGFloat, green: CGFloat, blue: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: 16, height: 16))
        image.lockFocus()
        NSColor(red: red, green: green, blue: blue, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 16, height: 16).fill()
        image.unlockFocus()
        return image
    }
}

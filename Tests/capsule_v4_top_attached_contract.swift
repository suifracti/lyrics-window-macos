import Foundation
import CoreGraphics

@main
struct CapsuleV4TopAttachedContract {
    static func main() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let envelope = CapsuleDynamicIslandDarkV4.debugEnvelopeSize

        precondition(envelope == CGSize(width: 680, height: 240))

        let windowFrame = CapsuleDynamicIslandDarkV4.topAttachedEnvelopeFrame(
            screenFrame: screen
        )
        precondition(windowFrame.width == envelope.width)
        precondition(windowFrame.height == envelope.height)
        precondition(windowFrame.midX == screen.midX)
        precondition(windowFrame.maxY == screen.maxY)
        precondition(windowFrame.minY == screen.maxY - envelope.height)

        let collapsed = CapsuleDynamicIslandDarkV4.topAttachedIslandFrame(
            for: .collapsed,
            envelopeSize: envelope
        )
        let hover = CapsuleDynamicIslandDarkV4.topAttachedIslandFrame(
            for: .hover,
            envelopeSize: envelope
        )
        let expanded = CapsuleDynamicIslandDarkV4.topAttachedIslandFrame(
            for: .expanded,
            envelopeSize: envelope
        )

        for island in [collapsed, hover, expanded] {
            precondition(island.midX == envelope.width / 2)
            precondition(island.maxY == envelope.height)
        }
        precondition(expanded.minY < hover.minY)
        precondition(hover.minY < collapsed.minY)

        let narrowScreen = CGRect(x: -100, y: 20, width: 320, height: 150)
        let clampedFrame = CapsuleDynamicIslandDarkV4.topAttachedEnvelopeFrame(
            screenFrame: narrowScreen
        )
        precondition(clampedFrame.width == 320)
        precondition(clampedFrame.height == 150)
        precondition(clampedFrame.midX == narrowScreen.midX)
        precondition(clampedFrame.maxY == narrowScreen.maxY)

        print("capsule v4 top-attached contract passed")
    }
}

import Foundation

@main
struct CapsulePresentationInterfaceContract {
    static func main() {
        let v4 = CapsuleLyricsPresentationVersion.dynamicIslandDarkV4
        precondition(v4.id == "capsule.dynamicIslandDark.v4")

        // Phase 2.2 remains the active renderer until v4 is fully implemented
        // and accepted. Adding an ID must not change the current behavior.
        precondition(CapsuleLyricsPresentationVersion.current == .controlFocusedV2)

        let sharedPresentation: any CapsulePresentation = v4
        precondition(sharedPresentation.id == "capsule.dynamicIslandDark.v4")

        print("capsule presentation interface contract passed")
    }
}

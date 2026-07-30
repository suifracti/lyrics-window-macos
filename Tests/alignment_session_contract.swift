import Foundation

@main
struct AlignmentSessionContract {
    static func main() {
        let track = Track(
            id: "session-test",
            title: "TEST Track",
            artist: "TEST Artist",
            album: "TEST Album",
            duration: 120,
            spotifyId: "session-test"
        )
        let identity = TrackIdentity(track: track)
        let sourceID = UUID()
        let sourceHash = String(repeating: "a", count: 64)
        let guardToken = AlignmentSessionGuard(
            identity: identity,
            sourceVersionID: sourceID,
            sourceContentHash: sourceHash,
            revision: 7
        )

        precondition(guardToken.accepts(
            identity: identity,
            sourceVersionID: sourceID,
            sourceContentHash: sourceHash,
            revision: 7
        ))
        precondition(!guardToken.accepts(
            identity: TrackIdentity(title: "Other", artist: "TEST Artist", album: "TEST Album", duration: 120),
            sourceVersionID: sourceID,
            sourceContentHash: sourceHash,
            revision: 7
        ))
        precondition(!guardToken.accepts(
            identity: identity,
            sourceVersionID: UUID(),
            sourceContentHash: sourceHash,
            revision: 7
        ))
        precondition(!guardToken.accepts(
            identity: identity,
            sourceVersionID: sourceID,
            sourceContentHash: String(repeating: "b", count: 64),
            revision: 7
        ))
        precondition(!guardToken.accepts(
            identity: identity,
            sourceVersionID: sourceID,
            sourceContentHash: sourceHash,
            revision: 8
        ))

        print("alignment session contract passed (TEST guard; identity/revision/source hash)")
    }
}

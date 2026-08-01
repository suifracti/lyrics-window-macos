import Foundation

@main
struct CapsuleLyricsContract {
    static func main() {
        let identity = TrackIdentity(
            title: "Contract song",
            artist: "Contract artist",
            album: "Contract album",
            duration: 120,
            spotifyTrackID: "capsule-contract"
        )
        let lines = [
            LyricLine(timestamp: 10, originalText: "前奏後の一行", translationText: "first"),
            LyricLine(timestamp: 20, originalText: "現在の一行", translationText: "current"),
            LyricLine(timestamp: 30, originalText: "次の一行", translationText: "next"),
            LyricLine(timestamp: 40, originalText: "最後の一行", translationText: "last")
        ]
        let document = LyricsDocument(
            identity: identity,
            title: identity.metadataFingerprint,
            lines: lines,
            isSynchronized: true,
            source: .lrclib
        )

        let synced = CapsuleLyricsPresentation.selection(
            lines: lines,
            currentIndex: 1,
            isSynchronized: true,
            state: .loaded(document)
        )
        precondition(synced.current?.originalText == "現在の一行")
        precondition(synced.following?.originalText == "次の一行")
        precondition(synced.status == nil)

        let prelude = CapsuleLyricsPresentation.selection(
            lines: lines,
            currentIndex: nil,
            isSynchronized: true,
            state: .loaded(document)
        )
        precondition(prelude.current == nil && prelude.following == nil)
        precondition(prelude.status?.contains("前奏") == true)

        let plainDocument = LyricsDocument(
            identity: identity,
            lines: lines.map { LyricLine(timestamp: 0, originalText: $0.originalText) },
            isSynchronized: false,
            source: .qqExperimental
        )
        let plain = CapsuleLyricsPresentation.selection(
            lines: plainDocument.lines,
            currentIndex: nil,
            isSynchronized: false,
            state: .alignmentQueued(identity, plainDocument)
        )
        precondition(plain.current == nil && plain.following == nil)
        precondition(plain.status?.contains("未排轴") == true)

        // Fail closed for an old/manual record whose synchronized flag is
        // inconsistent with its untimed lines. The capsule must never turn a
        // zero-time row into pseudo-synchronized playback.
        let inconsistentPlainDocument = LyricsDocument(
            identity: identity,
            lines: plainDocument.lines,
            isSynchronized: true,
            source: .manualEdit
        )
        let inconsistentPlain = CapsuleLyricsPresentation.selection(
            lines: inconsistentPlainDocument.lines,
            currentIndex: 0,
            isSynchronized: true,
            state: .loaded(inconsistentPlainDocument)
        )
        precondition(inconsistentPlain.current == nil && inconsistentPlain.following == nil)
        precondition(inconsistentPlain.status?.contains("未排轴") == true)

        let loading = CapsuleLyricsPresentation.selection(
            lines: [],
            currentIndex: nil,
            isSynchronized: false,
            state: .loading(identity)
        )
        precondition(loading.status?.isEmpty == false)

        let noMatch = CapsuleLyricsPresentation.selection(
            lines: [],
            currentIndex: nil,
            isSynchronized: false,
            state: .noMatch(identity)
        )
        precondition(noMatch.current == nil && noMatch.following == nil)
        precondition(noMatch.status?.isEmpty == false)

        let candidate = LyricsCandidate(
            id: "candidate",
            identity: identity,
            title: "Contract song",
            artist: "Contract artist",
            album: "Contract album",
            duration: 120,
            lines: [],
            source: .qqExperimental,
            confidence: 0.5
        )
        let candidates = CapsuleLyricsPresentation.selection(
            lines: [],
            currentIndex: nil,
            isSynchronized: false,
            state: .candidates(identity, [candidate])
        )
        precondition(candidates.current == nil && candidates.following == nil)
        precondition(candidates.status?.contains("主窗口") == true)

        let failed = CapsuleLyricsPresentation.selection(
            lines: [],
            currentIndex: nil,
            isSynchronized: false,
            state: .failed(identity, .networkUnavailable)
        )
        precondition(failed.status?.isEmpty == false)

        // The projection must carry the original line values through unchanged.
        precondition(synced.current?.translationText == "current")
        precondition(synced.following?.timestamp == 30)
        print("capsule lyrics contract passed")
    }
}

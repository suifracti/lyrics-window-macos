import Foundation

@main
struct LineAlignmentContract {
    static func main() {
        // Synthetic timed tokens spelling the lyric pronunciations in order.
        let lines = [
            LyricLine(timestamp: 0, originalText: "「これでおわり」って言われた夜", kanaText: "これでおわりっていわれたよる"),
            LyricLine(timestamp: 0, originalText: "でもまだ　ほどけない心", kanaText: "でもまだほどけないこころ"),
            LyricLine(timestamp: 0, originalText: "言えなかった言葉だけ", kanaText: "いえなかったことばだけ"),
        ]
        let tokens: [LineForcedAligner.TimedToken] = [
            .init(surface: "これ", norm: "これ", start: 1.0, end: 1.2),
            .init(surface: "で", norm: "で", start: 1.2, end: 1.3),
            .init(surface: "おわり", norm: "おわり", start: 1.3, end: 1.7),
            .init(surface: "って", norm: "って", start: 1.7, end: 1.9),
            .init(surface: "いわれた", norm: "いわれた", start: 1.9, end: 2.4),
            .init(surface: "よる", norm: "よる", start: 2.4, end: 2.8),
            .init(surface: "でも", norm: "でも", start: 3.2, end: 3.4),
            .init(surface: "まだ", norm: "まだ", start: 3.4, end: 3.6),
            .init(surface: "ほどけない", norm: "ほどけない", start: 3.6, end: 4.2),
            .init(surface: "こころ", norm: "こころ", start: 4.2, end: 4.6),
            .init(surface: "いえなかった", norm: "いえなかった", start: 5.0, end: 5.6),
            .init(surface: "ことば", norm: "ことば", start: 5.6, end: 5.9),
            .init(surface: "だけ", norm: "だけ", start: 5.9, end: 6.2),
        ]
        let aligned = LineForcedAligner.align(lines: lines, tokens: tokens, audioDuration: 10)
        precondition(aligned.count == 3)
        precondition(aligned[0].startTime >= 0.9 && aligned[0].startTime <= 1.3)
        precondition(aligned[1].startTime >= aligned[0].startTime)
        precondition(aligned[2].startTime >= aligned[1].startTime)
        precondition(aligned[0].originalText.contains("これでおわり"))
        // originals preserved
        precondition(aligned[0].originalText == lines[0].originalText)
        precondition(aligned.allSatisfy { $0.confidence > 0 })

        // Unrecognized tail lines must receive distinct monotonic preview
        // positions; collapsing them to one timestamp breaks line following.
        let tailLines = [
            LyricLine(timestamp: 0, originalText: "先頭", kanaText: "せんとう"),
            LyricLine(timestamp: 0, originalText: "途中", kanaText: "とちゅう"),
            LyricLine(timestamp: 0, originalText: "尾部一", kanaText: "ぶいち"),
            LyricLine(timestamp: 0, originalText: "尾部二", kanaText: "ぶに"),
        ]
        let tailTokens: [LineForcedAligner.TimedToken] = [
            .init(surface: "せんとう", norm: "せんとう", start: 1, end: 2),
            .init(surface: "とちゅう", norm: "とちゅう", start: 3, end: 4),
        ]
        let tailAligned = LineForcedAligner.align(lines: tailLines, tokens: tailTokens, audioDuration: 12)
        precondition(tailAligned[2].startTime > tailAligned[1].startTime)
        precondition(tailAligned[3].startTime > tailAligned[2].startTime)
        precondition(tailAligned[3].startTime <= 12)

        // A leading unmatched run must never be scheduled before the first
        // timed recognition anchor. Doing so makes lyrics move before the
        // singer has started; low-confidence preview rows may share the
        // first anchor, but must not precede actual recognition evidence.
        let leadingLines = [
            LyricLine(timestamp: 0, originalText: "未识别前奏", kanaText: "みしきぜんそう"),
            LyricLine(timestamp: 0, originalText: "第一句", kanaText: "だいいちく"),
        ]
        let leadingTokens: [LineForcedAligner.TimedToken] = [
            .init(surface: "だいいちく", norm: "だいいちく", start: 4, end: 5),
        ]
        let leadingAligned = LineForcedAligner.align(
            lines: leadingLines,
            tokens: leadingTokens,
            audioDuration: 12
        )
        precondition(leadingAligned[0].startTime >= 4)

        // A short fixture must be rejected for a much longer live track;
        // otherwise its timestamps can appear before the real vocal onset
        // and finish long before Spotify reaches the end of the song.
        precondition(!AlignmentDurationValidator.isCompatible(audioDuration: 79.8255, trackDuration: 171.177))
        precondition(AlignmentDurationValidator.isCompatible(audioDuration: 169, trackDuration: 171.177))
        precondition(AlignmentDurationValidator.isCompatible(audioDuration: 79.8255, trackDuration: nil))
        print("line alignment contract passed")
    }
}

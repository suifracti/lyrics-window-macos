import Foundation

private func segment(_ index: Int, _ text: String, _ start: Double, _ end: Double, _ confidence: Double = 0.95) -> TimedTranscriptSegment {
    TimedTranscriptSegment(index: index, text: text, startTime: start, endTime: end, confidence: confidence)
}

@main
struct RealAudioLineAlignmentContract {
    static func main() {
        // TEST fixture only: a deterministic transcript stands in for a timed
        // recognizer response. It is not a commercial song and contains no
        // TTS/audio input.
        let lines = [
            LyricLine(timestamp: 0, originalText: "最初の歌", kanaText: "さいしょのうた"),
            LyricLine(timestamp: 0, originalText: "同じ歌", kanaText: "おなじうた"),
            LyricLine(timestamp: 0, originalText: "欠けた行", kanaText: "かけたぎょう"),
            LyricLine(timestamp: 0, originalText: "同じ歌", kanaText: "おなじうた"),
            LyricLine(timestamp: 0, originalText: "最後の歌", kanaText: "さいごのうた")
        ]
        let transcript = TimedTranscript(
            backendID: "TEST-timed-transcript",
            segments: [
                segment(0, "ピアノ", 0.0, 1.5), // intro; should be skipped
                segment(1, "さいしょのうた", 2.0, 3.0),
                segment(2, "あー", 3.1, 3.3), // inserted vocalization
                segment(3, "おなじうた", 4.0, 5.0),
                // The third lyric line is intentionally absent.
                segment(4, "おなじうた", 6.0, 7.0), // repeated chorus occurrence
                segment(5, "さいごのうた", 8.0, 9.0)
            ],
            audioDuration: 10
        )
        precondition(transcript.isValid)

        let result = LineForcedAligner.align(
            lines: lines,
            transcript: transcript,
            audioDuration: 10,
            parameters: AlignmentParameters(recognizerID: "TEST-timed-transcript")
        )
        precondition(result.isComplete, "bounded missing line should be materialized")
        precondition(result.lines.count == lines.count)
        precondition(result.unresolvedLineIndices.isEmpty)
        precondition(result.lines[0].evidence.kind == .directSpeech)
        precondition(result.lines[2].evidence.kind == .boundedInterpolation)
        precondition(result.lines[2].status == .interpolated)
        precondition(result.lines[2].confidence < result.lines[1].confidence)
        precondition(result.lines[0].startTime >= 1.9 && result.lines[0].startTime <= 2.1)
        precondition(result.lines[1].startTime < result.lines[2].startTime)
        precondition(result.lines[2].startTime < result.lines[3].startTime)
        precondition(result.lines[3].startTime >= 5.9 && result.lines[3].startTime <= 6.1)
        precondition(result.lines[4].startTime >= 7.9 && result.lines[4].startTime <= 8.1)
        precondition(result.skippedTranscriptSegmentIndices.contains(0))
        precondition(result.skippedTranscriptSegmentIndices.contains(2))
        precondition(result.lines[0].originalText == lines[0].originalText)

        // No transcript evidence must never become evenly spaced timestamps.
        let noEvidence = LineForcedAligner.align(
            lines: lines,
            transcript: TimedTranscript(backendID: "TEST-empty", segments: [], audioDuration: 10),
            audioDuration: 10
        )
        precondition(!noEvidence.isComplete)
        precondition(noEvidence.unresolvedLineIndices.count == lines.count)
        precondition(noEvidence.lines.allSatisfy { $0.startTime < 0 && $0.evidence.kind == .noEvidence })

        // Leading and trailing unmatched lines remain unresolved; they are
        // not assigned the first anchor or the end of the song.
        let leading = LineForcedAligner.align(
            lines: [
                LyricLine(timestamp: 0, originalText: "前奏后未识别", kanaText: "ぜんそうごみしきべつ"),
                LyricLine(timestamp: 0, originalText: "第一句", kanaText: "だいいちく")
            ],
            transcript: TimedTranscript(
                backendID: "TEST-leading",
                segments: [segment(0, "だいいちく", 4, 5)],
                audioDuration: 12
            ),
            audioDuration: 12
        )
        precondition(leading.unresolvedLineIndices == [0])
        precondition(leading.lines[0].startTime < 0)
        precondition(leading.lines[1].startTime == 4)

        let trailing = LineForcedAligner.align(
            lines: [
                LyricLine(timestamp: 0, originalText: "第一句", kanaText: "だいいちく"),
                LyricLine(timestamp: 0, originalText: "尾奏后未识别", kanaText: "びそうごみしきべつ")
            ],
            transcript: TimedTranscript(
                backendID: "TEST-trailing",
                segments: [segment(0, "だいいちく", 4, 5)],
                audioDuration: 12
            ),
            audioDuration: 12
        )
        precondition(trailing.unresolvedLineIndices == [1])
        precondition(trailing.lines[1].startTime < 0)

        precondition(!AlignmentDurationValidator.isCompatible(audioDuration: 79.8255, trackDuration: 171.177))
        precondition(AlignmentDurationValidator.isCompatible(audioDuration: 169, trackDuration: 171.177))
        print("real audio line alignment contract passed (TEST synthetic transcript only)")
    }
}

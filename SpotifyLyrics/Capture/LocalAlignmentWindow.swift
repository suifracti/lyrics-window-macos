#if DEBUG
import Foundation

/// Constrained local refinement between accepted anchors.
/// Does not replace global LineForcedAligner; only fills gaps with stronger evidence.
public enum LocalAlignmentWindow {
    public struct WindowResult: Equatable, Sendable {
        public let lines: [PartialAlignedLine]
        public let diagnostics: [String]
    }

    /// Refine unresolved/low lines strictly between two anchors using only
    /// transcript segments that fall in the absolute time window.
    public static func refineBetweenAnchors(
        plainLines: [LyricLine],
        bundles: [SegmentSpeechBundle],
        anchors: [AlignmentAnchor],
        existing: [PartialAlignedLine],
        locale: String
    ) -> WindowResult {
        guard anchors.count >= 2 else {
            return WindowResult(lines: existing, diagnostics: ["local_window skip: need>=2 anchors"])
        }
        let ordered = anchors.sorted { $0.absoluteStartTime < $1.absoluteStartTime }
        var byIndex = Dictionary(uniqueKeysWithValues: existing.map { ($0.sourceLineIndex, $0) })
        var diag: [String] = []

        for i in 0..<(ordered.count - 1) {
            let left = ordered[i]
            let right = ordered[i + 1]
            guard right.lyricLineIndex > left.lyricLineIndex + 1 else { continue }
            let lineStart = left.lyricLineIndex + 1
            let lineEnd = right.lyricLineIndex - 1
            let absStart = left.absoluteEndTime
            let absEnd = right.absoluteStartTime
            guard absEnd - absStart >= 0.4 else { continue }

            let sliceLines = Array(plainLines[lineStart...lineEnd])
            // Collect relative transcript pieces inside the absolute window.
            var segs: [TimedTranscriptSegment] = []
            for bundle in bundles {
                for s in bundle.transcript.segments {
                    let absS = bundle.positionStart + s.startTime
                    let absE = bundle.positionStart + s.endTime
                    if absE < absStart - 0.05 || absS > absEnd + 0.05 { continue }
                    let relStart = max(0, absS - absStart)
                    let relEnd = max(relStart + 0.02, absE - absStart)
                    segs.append(
                        TimedTranscriptSegment(
                            index: segs.count,
                            text: s.text,
                            startTime: relStart,
                            endTime: relEnd,
                            confidence: s.confidence
                        )
                    )
                }
            }
            guard segs.count >= 1 else {
                diag.append("local_window empty segs lines=\(lineStart)-\(lineEnd)")
                continue
            }
            let windowDur = max(0.2, absEnd - absStart)
            let transcript = TimedTranscript(
                backendID: "local-window",
                segments: segs,
                audioDuration: windowDur
            )
            // Guard: TimedTranscript.isValid requires monotonic non-overlap; ensure sorted.
            let sortedSegs = segs.enumerated().map { idx, s in
                TimedTranscriptSegment(
                    index: idx,
                    text: s.text,
                    startTime: s.startTime,
                    endTime: max(s.startTime + 0.02, s.endTime),
                    confidence: s.confidence
                )
            }.sorted { $0.startTime < $1.startTime }
            // Reindex monotonic
            var mono: [TimedTranscriptSegment] = []
            var last: TimeInterval = 0
            for (idx, s) in sortedSegs.enumerated() {
                let st = max(last, s.startTime)
                let en = max(st + 0.02, s.endTime)
                mono.append(
                    TimedTranscriptSegment(
                        index: idx,
                        text: s.text,
                        startTime: st,
                        endTime: en,
                        confidence: s.confidence
                    )
                )
                last = en
            }
            let safeTranscript = TimedTranscript(
                backendID: "local-window",
                segments: mono,
                audioDuration: max(windowDur, last)
            )
            _ = transcript

            let aligned = LineForcedAligner.align(
                lines: sliceLines,
                transcript: safeTranscript,
                audioDuration: safeTranscript.audioDuration,
                parameters: AlignmentParameters(
                    recognizerID: "local-window",
                    localeIdentifier: locale
                )
            )
            var filled = 0
            for (offset, row) in aligned.lines.enumerated() {
                let globalIndex = lineStart + offset
                guard row.startTime >= 0 else { continue }
                // Only fill if existing is weak/unresolved.
                if let cur = byIndex[globalIndex],
                   cur.status == .resolved || cur.status == .interpolated {
                    continue
                }
                // Local relative → absolute
                let absT = absStart + row.startTime
                guard absT + 0.05 < absEnd, absT > absStart - 0.05 else { continue }
                let status: PartialLineStatus = row.status == .aligned ? .resolved : .lowConfidence
                // Local window fills are constrained, not free observed.
                let evidence = "localWindow:constrainedInterpolated:\(row.evidence.kind.rawValue)"
                byIndex[globalIndex] = PartialAlignedLine(
                    sourceLineIndex: globalIndex,
                    text: plainLines[globalIndex].originalText,
                    status: status,
                    startTime: absT,
                    endTime: row.endTime.map { absStart + $0 },
                    confidence: min(row.confidence, 0.80),
                    segmentID: left.segmentID,
                    evidenceKind: evidence,
                    speechRelativeStart: row.startTime,
                    speechRelativeEnd: row.endTime
                )
                filled += 1
            }
            diag.append(
                "local_window left=\(left.lyricLineIndex) right=\(right.lyricLineIndex) filled=\(filled) segs=\(mono.count)"
            )
        }

        let lines = plainLines.indices.map { i in
            byIndex[i] ?? PartialAlignedLine(
                sourceLineIndex: i,
                text: plainLines[i].originalText,
                status: .unresolved,
                startTime: nil,
                endTime: nil,
                confidence: 0,
                segmentID: nil,
                evidenceKind: "noEvidence"
            )
        }
        return WindowResult(lines: lines, diagnostics: diag)
    }
}
#endif

#if DEBUG
import Foundation

/// S3B: conservative anchors from Speech + constrained region DP via
/// existing `LineForcedAligner`. Never uses held-out timestamps.
public enum AnchorConstrainedAligner {
    /// Build accepted/rejected anchors from speech bundles and plain lyrics.
    public static func selectAnchors(
        bundles: [SegmentSpeechBundle],
        plainLines: [LyricLine]
    ) -> (accepted: [AlignmentAnchor], rejected: [AlignmentAnchor]) {
        let lyricNorms = plainLines.map { LineForcedAligner.normalize($0.originalText) }
        var candidates: [AlignmentAnchor] = []
        var rejected: [AlignmentAnchor] = []

        for bundle in bundles {
            let segs = bundle.transcript.segments
            let norms = segs.map { LineForcedAligner.normalize($0.text) }
            for tStart in segs.indices {
                var combined = ""
                let endLimit = min(segs.count - 1, tStart + AnchorAlignmentPolicy.maxTranscriptWindow - 1)
                for tEnd in tStart...endLimit {
                    combined += norms[tEnd]
                    let combinedLen = combined.count
                    guard combinedLen >= AnchorAlignmentPolicy.minimumNormalizedLength else { continue }

                    // Score against every lyric line.
                    var scores: [(line: Int, score: Double)] = []
                    for (lineIndex, lyricNorm) in lyricNorms.enumerated() {
                        guard lyricNorm.count >= AnchorAlignmentPolicy.minimumNormalizedLength else { continue }
                        let sim = textSimilarity(combined, lyricNorm)
                        if sim >= AnchorAlignmentPolicy.minimumTextSimilarity - 0.05 {
                            scores.append((lineIndex, sim))
                        }
                    }
                    scores.sort { $0.score > $1.score }
                    guard let best = scores.first else { continue }

                    let speechConf = segs[tStart...tEnd].map(\.confidence).reduce(0, +)
                        / Double(tEnd - tStart + 1)
                    let second = scores.dropFirst().first?.score ?? 0
                    let unique = best.score - second >= AnchorAlignmentPolicy.uniquenessGap
                        || scores.count == 1

                    let relStart = segs[tStart].startTime
                    let relEnd = segs[tEnd].endTime
                    let absStart = bundle.positionStart + relStart
                    let absEnd = bundle.positionStart + relEnd
                    let overall = AnchorAlignmentPolicy.textWeight * best.score
                        + AnchorAlignmentPolicy.speechWeight * speechConf

                    let transcriptText = segs[tStart...tEnd].map(\.text).joined()
                    var reason: String? = nil
                    var accepted = true
                    if combinedLen < AnchorAlignmentPolicy.minimumNormalizedLength {
                        accepted = false
                        reason = "too_short"
                    } else if best.score < AnchorAlignmentPolicy.minimumTextSimilarity {
                        accepted = false
                        reason = "text_similarity_below_threshold"
                    } else if overall < AnchorAlignmentPolicy.minimumOverallConfidence {
                        accepted = false
                        reason = "overall_confidence_below_threshold"
                    } else if !unique {
                        accepted = false
                        reason = "ambiguous_multiple_lyric_matches"
                    }

                    let anchor = AlignmentAnchor(
                        transcriptStartIndex: tStart,
                        transcriptEndIndex: tEnd,
                        lyricLineIndex: best.line,
                        transcriptText: transcriptText,
                        lyricText: plainLines[best.line].originalText,
                        segmentID: bundle.segment.segmentID,
                        absoluteStartTime: absStart,
                        absoluteEndTime: absEnd,
                        relativeStartTime: relStart,
                        relativeEndTime: relEnd,
                        textConfidence: best.score,
                        temporalConfidence: speechConf,
                        overallConfidence: overall,
                        evidence: "textSim=\(fmt(best.score));speech=\(fmt(speechConf));window=\(tStart)-\(tEnd)",
                        accepted: accepted,
                        rejectionReason: reason
                    )
                    if accepted {
                        candidates.append(anchor)
                    } else {
                        rejected.append(anchor)
                    }

                    if combined.count > (lyricNorms[best.line].count * 2 + 12) { break }
                }
            }
        }

        // Monotonic selection of accepted candidates (prefer higher confidence).
        let sorted = candidates.sorted {
            if $0.overallConfidence != $1.overallConfidence {
                return $0.overallConfidence > $1.overallConfidence
            }
            return $0.absoluteStartTime < $1.absoluteStartTime
        }
        var accepted: [AlignmentAnchor] = []
        var usedLines = Set<Int>()
        for cand in sorted {
            if usedLines.contains(cand.lyricLineIndex) {
                rejected.append(
                    withRejection(cand, "duplicate_lyric_line")
                )
                continue
            }
            // Temporal + lyric order vs already accepted.
            var conflict: String?
            for a in accepted {
                if cand.absoluteStartTime + AnchorAlignmentPolicy.minimumTemporalSeparation <= a.absoluteStartTime
                    && cand.lyricLineIndex > a.lyricLineIndex {
                    conflict = "time_lyric_order_conflict"
                    break
                }
                if cand.absoluteStartTime >= a.absoluteEndTime - 0.05
                    && cand.lyricLineIndex < a.lyricLineIndex {
                    conflict = "time_lyric_order_conflict"
                    break
                }
                if abs(cand.absoluteStartTime - a.absoluteStartTime) < AnchorAlignmentPolicy.minimumTemporalSeparation
                    && cand.lyricLineIndex != a.lyricLineIndex {
                    conflict = "temporal_collision"
                    break
                }
            }
            if let conflict {
                rejected.append(withRejection(cand, conflict))
                continue
            }
            usedLines.insert(cand.lyricLineIndex)
            accepted.append(cand)
        }
        accepted.sort {
            if $0.absoluteStartTime != $1.absoluteStartTime {
                return $0.absoluteStartTime < $1.absoluteStartTime
            }
            return $0.lyricLineIndex < $1.lyricLineIndex
        }
        // Final monotonic filter (safety).
        var mono: [AlignmentAnchor] = []
        for a in accepted {
            if let last = mono.last {
                if a.lyricLineIndex <= last.lyricLineIndex
                    || a.absoluteStartTime + 0.01 < last.absoluteStartTime {
                    rejected.append(withRejection(a, "failed_final_monotonic_filter"))
                    continue
                }
            }
            mono.append(a)
        }
        return (mono, rejected)
    }

    /// Region-constrained alignment using accepted anchors. Falls back to nil
    /// when anchors are insufficient (caller should use S3A).
    public static func alignConstrained(
        bundles: [SegmentSpeechBundle],
        plainLines: [LyricLine],
        acceptedAnchors: [AlignmentAnchor],
        capturedRanges: [CapturedTimeRange],
        locale: String
    ) -> [PartialAlignedLine]? {
        guard acceptedAnchors.count >= AnchorAlignmentPolicy.minimumAnchorsForConstrained else {
            return nil
        }

        // Flatten transcript with absolute times for region slicing.
        struct AbsSeg {
            let text: String
            let absStart: TimeInterval
            let absEnd: TimeInterval
            let conf: Double
            let segmentID: UUID
            let relStart: TimeInterval
            let relEnd: TimeInterval
        }
        var absSegs: [AbsSeg] = []
        for b in bundles {
            for s in b.transcript.segments {
                absSegs.append(
                    AbsSeg(
                        text: s.text,
                        absStart: b.positionStart + s.startTime,
                        absEnd: b.positionStart + s.endTime,
                        conf: s.confidence,
                        segmentID: b.segment.segmentID,
                        relStart: s.startTime,
                        relEnd: s.endTime
                    )
                )
            }
        }
        absSegs.sort { $0.absStart < $1.absStart }

        var bestByLine: [Int: PartialAlignedLine] = [:]

        // Pin anchors first as resolved.
        for a in acceptedAnchors {
            bestByLine[a.lyricLineIndex] = PartialAlignedLine(
                sourceLineIndex: a.lyricLineIndex,
                text: plainLines[a.lyricLineIndex].originalText,
                status: .resolved,
                startTime: a.absoluteStartTime,
                endTime: a.absoluteEndTime,
                confidence: a.overallConfidence,
                segmentID: a.segmentID,
                evidenceKind: "anchor",
                speechRelativeStart: a.relativeStartTime,
                speechRelativeEnd: a.relativeEndTime
            )
        }

        // Regions: before first, between, after last.
        let anchors = acceptedAnchors
        var regions: [(lineStart: Int, lineEnd: Int, tStart: TimeInterval, tEnd: TimeInterval)] = []
        // Before first anchor: lines [0, a0) time (-inf, a0.start)
        if let first = anchors.first, first.lyricLineIndex > 0 {
            regions.append((0, first.lyricLineIndex - 1, 0, first.absoluteStartTime))
        }
        for i in 0..<(anchors.count - 1) {
            let a = anchors[i]
            let b = anchors[i + 1]
            let lineStart = a.lyricLineIndex + 1
            let lineEnd = b.lyricLineIndex - 1
            if lineStart <= lineEnd {
                regions.append((lineStart, lineEnd, a.absoluteEndTime, b.absoluteStartTime))
            }
        }
        if let last = anchors.last, last.lyricLineIndex + 1 < plainLines.count {
            let capEnd = capturedRanges.map(\.end).max() ?? (last.absoluteEndTime + 30)
            regions.append((last.lyricLineIndex + 1, plainLines.count - 1, last.absoluteEndTime, capEnd + 1))
        }

        for region in regions {
            let regionLines = Array(plainLines[region.lineStart...region.lineEnd])
            let regionAbs = absSegs.filter {
                $0.absStart >= region.tStart - 0.05 && $0.absEnd <= region.tEnd + 0.05
            }
            guard !regionLines.isEmpty, !regionAbs.isEmpty else { continue }

            // Build a relative transcript starting at 0 for LineForcedAligner.
            let t0 = regionAbs.first!.absStart
            let t1 = regionAbs.last!.absEnd
            let relSegments = regionAbs.enumerated().map { idx, s in
                TimedTranscriptSegment(
                    index: idx,
                    text: s.text,
                    startTime: max(0, s.absStart - t0),
                    endTime: max(0.02, s.absEnd - t0),
                    confidence: s.conf
                )
            }
            let transcript = TimedTranscript(
                backendID: "s3b-region",
                segments: relSegments,
                audioDuration: max(0.1, t1 - t0)
            )
            let result = LineForcedAligner.align(
                lines: regionLines,
                transcript: transcript,
                audioDuration: max(0.1, t1 - t0),
                parameters: AlignmentParameters(
                    recognizerID: "s3b-constrained",
                    localeIdentifier: locale,
                    sampleRate: 16_000,
                    channels: 1
                )
            )
            for (offset, aligned) in result.lines.enumerated() {
                let lineIndex = region.lineStart + offset
                if aligned.startTime < 0 {
                    if bestByLine[lineIndex] == nil {
                        bestByLine[lineIndex] = PartialAlignedLine(
                            sourceLineIndex: lineIndex,
                            text: plainLines[lineIndex].originalText,
                            status: .unresolved,
                            startTime: nil,
                            endTime: nil,
                            confidence: aligned.confidence,
                            segmentID: regionAbs.first?.segmentID,
                            evidenceKind: "s3b-region-unresolved"
                        )
                    }
                    continue
                }
                let absStart = t0 + aligned.startTime
                let absEnd = aligned.endTime.map { t0 + $0 }
                // Clamp to region bounds (no cross-anchor).
                let clampedStart = min(max(absStart, region.tStart), region.tEnd)
                let status: PartialLineStatus
                switch aligned.status {
                case .aligned: status = .resolved
                case .lowConfidence: status = .lowConfidence
                case .interpolated: status = .interpolated
                case .unmatched: status = .unresolved
                }
                let row = PartialAlignedLine(
                    sourceLineIndex: lineIndex,
                    text: plainLines[lineIndex].originalText,
                    status: status,
                    startTime: status == .unresolved ? nil : clampedStart,
                    endTime: status == .unresolved ? nil : absEnd,
                    confidence: aligned.confidence,
                    segmentID: regionAbs.first?.segmentID,
                    evidenceKind: "s3b-region-\(aligned.evidence.kind.rawValue)",
                    speechRelativeStart: aligned.startTime,
                    speechRelativeEnd: aligned.endTime
                )
                if let existing = bestByLine[lineIndex] {
                    // Prefer anchors over region fills.
                    if existing.evidenceKind == "anchor" { continue }
                    if row.confidence > existing.confidence { bestByLine[lineIndex] = row }
                } else {
                    bestByLine[lineIndex] = row
                }
            }
        }

        // Fill remaining lines.
        var lines: [PartialAlignedLine] = []
        for index in plainLines.indices {
            if let row = bestByLine[index] {
                lines.append(row)
            } else {
                lines.append(
                    PartialAlignedLine(
                        sourceLineIndex: index,
                        text: plainLines[index].originalText,
                        status: .unresolved,
                        startTime: nil,
                        endTime: nil,
                        confidence: 0,
                        segmentID: nil,
                        evidenceKind: "s3b-noEvidence"
                    )
                )
            }
        }
        return lines.sorted { $0.sourceLineIndex < $1.sourceLineIndex }
    }

    // MARK: - helpers

    private static func withRejection(_ a: AlignmentAnchor, _ reason: String) -> AlignmentAnchor {
        AlignmentAnchor(
            transcriptStartIndex: a.transcriptStartIndex,
            transcriptEndIndex: a.transcriptEndIndex,
            lyricLineIndex: a.lyricLineIndex,
            transcriptText: a.transcriptText,
            lyricText: a.lyricText,
            segmentID: a.segmentID,
            absoluteStartTime: a.absoluteStartTime,
            absoluteEndTime: a.absoluteEndTime,
            relativeStartTime: a.relativeStartTime,
            relativeEndTime: a.relativeEndTime,
            textConfidence: a.textConfidence,
            temporalConfidence: a.temporalConfidence,
            overallConfidence: a.overallConfidence,
            evidence: a.evidence,
            accepted: false,
            rejectionReason: reason
        )
    }

    /// Public-ish similarity aligned with LineForcedAligner spirit (LCS + dice).
    private static func textSimilarity(_ a: String, _ b: String) -> Double {
        if a == b { return 1 }
        if a.isEmpty || b.isEmpty { return 0 }
        let ac = Array(a)
        let bc = Array(b)
        let lcs = lcsLength(ac, bc)
        let lcsScore = (2.0 * Double(lcs)) / Double(ac.count + bc.count)
        let dice = diceCoefficient(a, b)
        return 0.65 * lcsScore + 0.35 * dice
    }

    private static func lcsLength(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty || b.isEmpty { return 0 }
        var prev = [Int](repeating: 0, count: b.count + 1)
        var cur = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            for j in 1...b.count {
                if a[i - 1] == b[j - 1] {
                    cur[j] = prev[j - 1] + 1
                } else {
                    cur[j] = max(prev[j], cur[j - 1])
                }
            }
            swap(&prev, &cur)
            cur = [Int](repeating: 0, count: b.count + 1)
        }
        return prev[b.count]
    }

    private static func diceCoefficient(_ a: String, _ b: String) -> Double {
        func bigrams(_ s: String) -> [String] {
            let chars = Array(s)
            guard chars.count >= 2 else { return chars.map(String.init) }
            return (0..<(chars.count - 1)).map { String(chars[$0]) + String(chars[$0 + 1]) }
        }
        let ba = bigrams(a)
        let bb = bigrams(b)
        if ba.isEmpty || bb.isEmpty { return 0 }
        var counts: [String: Int] = [:]
        for g in ba { counts[g, default: 0] += 1 }
        var inter = 0
        for g in bb {
            if let c = counts[g], c > 0 {
                inter += 1
                counts[g] = c - 1
            }
        }
        return (2.0 * Double(inter)) / Double(ba.count + bb.count)
    }

    private static func fmt(_ v: Double) -> String { String(format: "%.3f", v) }
}
#endif

#if DEBUG
import Foundation

/// Thin merge layer over existing S3A/S3B outputs.
/// Priority: S3B anchors → S3B high-conf resolved → S3A high-conf resolved (no conflict).
/// Never lowers S3A/S3B thresholds; never adopts lowConfidence or interpolation.
public enum AssistedCandidateMerger {
    public static func merge(report: PartialAlignmentReport, plainLines: [LyricLine]) -> AssistedAlignmentDraft {
        let primary = report.candidate
        let s3a = report.s3aCandidate
        let lineCount = max(plainLines.count, primary.lines.count, s3a?.lines.count ?? 0)

        var byIndex: [Int: AssistedLineSuggestion] = [:]
        for index in 0..<lineCount {
            let text = index < plainLines.count ? plainLines[index].originalText : (primary.lines.first { $0.sourceLineIndex == index }?.text ?? "")
            byIndex[index] = AssistedLineSuggestion(
                lyricLineIndex: index,
                text: text,
                status: .unresolved
            )
        }

        // 1) S3B accepted anchors (highest trust).
        for anchor in report.acceptedAnchors where anchor.accepted {
            guard byIndex[anchor.lyricLineIndex] != nil else { continue }
            byIndex[anchor.lyricLineIndex] = AssistedLineSuggestion(
                lyricLineIndex: anchor.lyricLineIndex,
                text: plainLines.indices.contains(anchor.lyricLineIndex)
                    ? plainLines[anchor.lyricLineIndex].originalText
                    : anchor.lyricText,
                suggestedStartTime: anchor.absoluteStartTime,
                suggestedEndTime: anchor.absoluteEndTime,
                source: .anchor,
                confidenceClass: confidenceClass(anchor.overallConfidence),
                segmentID: anchor.segmentID,
                evidenceSummary: "anchor",
                status: .suggested
            )
        }

        // 2) S3B high-confidence resolved (non-interpolation).
        for line in primary.lines {
            guard line.status == .resolved else {
                if line.status == .outsideCapturedRange, byIndex[line.sourceLineIndex]?.status == .unresolved {
                    byIndex[line.sourceLineIndex] = AssistedLineSuggestion(
                        lyricLineIndex: line.sourceLineIndex,
                        text: line.text,
                        evidenceSummary: "outsideCapturedRange",
                        status: .outsideCapturedRange
                    )
                }
                continue
            }
            guard line.confidence >= AssistedCandidateMergePolicy.s3bResolvedMinimumConfidence else { continue }
            guard isAcceptableEvidence(line.evidenceKind) else { continue }
            guard let start = line.startTime else { continue }
            if let existing = byIndex[line.sourceLineIndex], existing.status == .suggested, existing.source == .anchor {
                continue
            }
            if conflictsWithExisting(byIndex: byIndex, index: line.sourceLineIndex, start: start) {
                continue
            }
            byIndex[line.sourceLineIndex] = AssistedLineSuggestion(
                lyricLineIndex: line.sourceLineIndex,
                text: line.text,
                suggestedStartTime: start,
                suggestedEndTime: line.endTime,
                source: .speechResolved,
                confidenceClass: confidenceClass(line.confidence),
                segmentID: line.segmentID,
                evidenceSummary: "s3b:\(line.evidenceKind)",
                status: .suggested
            )
        }

        // 3) S3A high-confidence resolved if no conflict and not interpolation.
        if let s3a {
            for line in s3a.lines {
                guard line.status == .resolved else { continue }
                guard line.confidence >= AssistedCandidateMergePolicy.s3aResolvedMinimumConfidence else { continue }
                guard isAcceptableEvidence(line.evidenceKind) else { continue }
                guard let start = line.startTime else { continue }
                if let existing = byIndex[line.sourceLineIndex], existing.isTimed {
                    continue
                }
                if conflictsWithExisting(byIndex: byIndex, index: line.sourceLineIndex, start: start) {
                    continue
                }
                byIndex[line.sourceLineIndex] = AssistedLineSuggestion(
                    lyricLineIndex: line.sourceLineIndex,
                    text: line.text,
                    suggestedStartTime: start,
                    suggestedEndTime: line.endTime,
                    source: .speechResolved,
                    confidenceClass: confidenceClass(line.confidence),
                    segmentID: line.segmentID,
                    evidenceSummary: "s3a:\(line.evidenceKind)",
                    status: .suggested
                )
            }
        }

        // Enforce global monotonicity on suggested times: drop later conflicts.
        var ordered = (0..<lineCount).compactMap { byIndex[$0] }
        ordered = enforceMonotonic(ordered)

        return AssistedAlignmentDraft(
            trackIdentityDigest: primary.trackIdentityDigest,
            captureSessionID: primary.captureSessionID,
            plainLineCount: lineCount,
            lines: ordered,
            usedConstrainedAlignment: report.usedConstrainedAlignment,
            s3bFallbackReason: report.s3bFallbackReason,
            judgment: report.judgment
        )
    }

    // MARK: - helpers

    private static func isAcceptableEvidence(_ kind: String) -> Bool {
        let lower = kind.lowercased()
        for bad in AssistedCandidateMergePolicy.rejectedEvidenceSubstrings {
            if lower.contains(bad.lowercased()) { return false }
        }
        // Prefer direct speech / anchor styles.
        if lower.contains("directspeech") || lower.contains("anchor") || lower.contains("s3b-region-direct") {
            return true
        }
        // Allow plain "resolved" evidence without interpolation keywords.
        return !lower.contains("interpol")
    }

    private static func confidenceClass(_ value: Double) -> AssistedConfidenceClass {
        if value >= 0.85 { return .high }
        if value >= 0.72 { return .medium }
        if value > 0 { return .low }
        return .none
    }

    private static func conflictsWithExisting(
        byIndex: [Int: AssistedLineSuggestion],
        index: Int,
        start: TimeInterval
    ) -> Bool {
        // Earlier timed line must not start after this; later must not start before.
        for (otherIndex, other) in byIndex {
            guard let otherStart = other.suggestedStartTime, other.isTimed else { continue }
            if otherIndex < index, otherStart > start + 0.05 { return true }
            if otherIndex > index, otherStart + 0.05 < start { return true }
        }
        return false
    }

    private static func enforceMonotonic(_ lines: [AssistedLineSuggestion]) -> [AssistedLineSuggestion] {
        var result = lines
        var lastStart: TimeInterval = -1
        for i in result.indices {
            guard let start = result[i].suggestedStartTime, result[i].isTimed else { continue }
            if start + 0.001 < lastStart {
                // Drop this suggestion rather than reorder lyrics.
                result[i] = AssistedLineSuggestion(
                    lyricLineIndex: result[i].lyricLineIndex,
                    text: result[i].text,
                    evidenceSummary: "dropped_non_monotonic",
                    status: .unresolved
                )
            } else {
                lastStart = start
            }
        }
        return result
    }
}
#endif

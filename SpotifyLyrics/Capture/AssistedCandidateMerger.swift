#if DEBUG
import Foundation

/// Thin merge layer over existing S3A/S3B outputs.
/// Priority: S3B anchors → S3B high-conf resolved → S3A high-conf resolved (no conflict).
/// Never adopts interpolation. Missing ASR confidence does not auto-reject high lexical matches.
public enum AssistedCandidateMerger {
    public struct MergeOutput: Equatable, Sendable {
        public let draft: AssistedAlignmentDraft
        public let decisions: [AssistedMergeDecision]
    }

    public static func merge(report: PartialAlignmentReport, plainLines: [LyricLine]) -> AssistedAlignmentDraft {
        mergeWithExplanation(report: report, plainLines: plainLines).draft
    }

    public static func mergeWithExplanation(
        report: PartialAlignmentReport,
        plainLines: [LyricLine]
    ) -> MergeOutput {
        let primary = report.candidate
        let s3a = report.s3aCandidate
        let lineCount = max(plainLines.count, primary.lines.count, s3a?.lines.count ?? 0)
        var decisions: [AssistedMergeDecision] = []

        var byIndex: [Int: AssistedLineSuggestion] = [:]
        for index in 0..<lineCount {
            let text = index < plainLines.count
                ? plainLines[index].originalText
                : (primary.lines.first { $0.sourceLineIndex == index }?.text ?? "")
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
                evidenceSummary: "anchor:\(anchor.evidence)",
                status: .suggested
            )
            decisions.append(
                AssistedMergeDecision(
                    lyricLineIndex: anchor.lyricLineIndex,
                    decision: "accepted",
                    reason: "anchor",
                    source: "anchor",
                    confidence: anchor.overallConfidence,
                    startTime: anchor.absoluteStartTime
                )
            )
        }

        // 2) S3B resolved (+ lexical recovery when ASR missing).
        for line in primary.lines {
            if line.status == .outsideCapturedRange, byIndex[line.sourceLineIndex]?.status == .unresolved {
                byIndex[line.sourceLineIndex] = AssistedLineSuggestion(
                    lyricLineIndex: line.sourceLineIndex,
                    text: line.text,
                    evidenceSummary: "outsideCapturedRange",
                    status: .outsideCapturedRange
                )
                decisions.append(
                    AssistedMergeDecision(
                        lyricLineIndex: line.sourceLineIndex,
                        decision: "rejected",
                        reason: "outside_captured_range",
                        source: "s3b",
                        confidence: line.confidence,
                        startTime: line.startTime
                    )
                )
                continue
            }
            let outcome = evaluateResolvedCandidate(
                line: line,
                tier: .s3b,
                byIndex: byIndex
            )
            decisions.append(outcome.decision)
            if let suggestion = outcome.suggestion {
                byIndex[line.sourceLineIndex] = suggestion
            }
        }

        // 3) S3A resolved if no timed suggestion yet.
        if let s3a {
            for line in s3a.lines {
                let outcome = evaluateResolvedCandidate(
                    line: line,
                    tier: .s3a,
                    byIndex: byIndex
                )
                decisions.append(outcome.decision)
                if let suggestion = outcome.suggestion {
                    byIndex[line.sourceLineIndex] = suggestion
                }
            }
        }

        // Global monotonicity: drop later conflicts.
        var ordered = (0..<lineCount).compactMap { byIndex[$0] }
        let beforeMono = ordered
        ordered = enforceMonotonic(ordered)
        for (before, after) in zip(beforeMono, ordered) where before.isTimed && !after.isTimed {
            decisions.append(
                AssistedMergeDecision(
                    lyricLineIndex: before.lyricLineIndex,
                    decision: "rejected",
                    reason: "dropped_non_monotonic",
                    source: before.source.rawValue,
                    confidence: nil,
                    startTime: before.suggestedStartTime
                )
            )
        }

        let draft = AssistedAlignmentDraft(
            trackIdentityDigest: primary.trackIdentityDigest,
            captureSessionID: primary.captureSessionID,
            plainLineCount: lineCount,
            lines: ordered,
            usedConstrainedAlignment: report.usedConstrainedAlignment,
            s3bFallbackReason: report.s3bFallbackReason,
            judgment: report.judgment
        )
        return MergeOutput(draft: draft, decisions: decisions)
    }

    // MARK: - helpers

    private enum Tier { case s3a, s3b }

    private struct Eval {
        let suggestion: AssistedLineSuggestion?
        let decision: AssistedMergeDecision
    }

    private static func evaluateResolvedCandidate(
        line: PartialAlignedLine,
        tier: Tier,
        byIndex: [Int: AssistedLineSuggestion]
    ) -> Eval {
        let idx = line.sourceLineIndex
        let sourceTag = tier == .s3a ? "s3a" : "s3b"
        guard line.status == .resolved else {
            return Eval(
                suggestion: nil,
                decision: AssistedMergeDecision(
                    lyricLineIndex: idx,
                    decision: "rejected",
                    reason: "status_\(line.status.rawValue)",
                    source: sourceTag,
                    confidence: line.confidence,
                    startTime: line.startTime
                )
            )
        }
        guard isAcceptableEvidence(line.evidenceKind) else {
            return Eval(
                suggestion: nil,
                decision: AssistedMergeDecision(
                    lyricLineIndex: idx,
                    decision: "rejected",
                    reason: "low_evidence_kind:\(line.evidenceKind)",
                    source: sourceTag,
                    confidence: line.confidence,
                    startTime: line.startTime
                )
            )
        }
        guard let start = line.startTime else {
            return Eval(
                suggestion: nil,
                decision: AssistedMergeDecision(
                    lyricLineIndex: idx,
                    decision: "rejected",
                    reason: "missing_start_time",
                    source: sourceTag,
                    confidence: line.confidence,
                    startTime: nil
                )
            )
        }

        let minConf = tier == .s3a
            ? AssistedCandidateMergePolicy.s3aResolvedMinimumConfidence
            : AssistedCandidateMergePolicy.s3bResolvedMinimumConfidence
        let lexicalOK = line.confidence >= AssistedCandidateMergePolicy.lexicalRecoveryMinimum
        let hardOK = line.confidence >= minConf
        // Lexical recovery: high match score with direct speech, even if slightly
        // below the historical ASR-weighted gate (Whisper missing ASR conf).
        let accept: Bool
        let reason: String
        if hardOK {
            accept = true
            reason = "confidence_gate"
        } else if lexicalOK && line.evidenceKind.lowercased().contains("direct") {
            accept = true
            reason = "lexical_recovery_missing_or_low_asr"
        } else {
            return Eval(
                suggestion: nil,
                decision: AssistedMergeDecision(
                    lyricLineIndex: idx,
                    decision: "rejected",
                    reason: "low_confidence:\(String(format: "%.3f", line.confidence))<gate",
                    source: sourceTag,
                    confidence: line.confidence,
                    startTime: start
                )
            )
        }

        if let existing = byIndex[idx], existing.status == .suggested {
            return Eval(
                suggestion: nil,
                decision: AssistedMergeDecision(
                    lyricLineIndex: idx,
                    decision: "rejected",
                    reason: existing.source == .anchor ? "already_anchor" : "already_suggested",
                    source: sourceTag,
                    confidence: line.confidence,
                    startTime: start
                )
            )
        }
        if conflictsWithExisting(byIndex: byIndex, index: idx, start: start) {
            return Eval(
                suggestion: nil,
                decision: AssistedMergeDecision(
                    lyricLineIndex: idx,
                    decision: "rejected",
                    reason: "time_order_conflict",
                    source: sourceTag,
                    confidence: line.confidence,
                    startTime: start
                )
            )
        }

        _ = accept
        let suggestion = AssistedLineSuggestion(
            lyricLineIndex: idx,
            text: line.text,
            suggestedStartTime: start,
            suggestedEndTime: line.endTime,
            source: .speechResolved,
            confidenceClass: confidenceClass(line.confidence),
            segmentID: line.segmentID,
            evidenceSummary: "\(sourceTag):\(line.evidenceKind);reason=\(reason)",
            status: .suggested
        )
        return Eval(
            suggestion: suggestion,
            decision: AssistedMergeDecision(
                lyricLineIndex: idx,
                decision: "accepted",
                reason: reason,
                source: sourceTag,
                confidence: line.confidence,
                startTime: start
            )
        )
    }

    private static func isAcceptableEvidence(_ kind: String) -> Bool {
        let lower = kind.lowercased()
        for bad in AssistedCandidateMergePolicy.rejectedEvidenceSubstrings {
            if lower.contains(bad.lowercased()) { return false }
        }
        if lower.contains("directspeech") || lower.contains("anchor") || lower.contains("s3b-region-direct") {
            return true
        }
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

import Foundation

/// Product-level gate for zero-operation automatic alignment.
/// Prefer accumulate / deferred / reject over partial auto-adopt.
public enum AutomaticAlignmentQualityGate {
    public enum Decision: String, Sendable, Equatable, Codable {
        case accumulate
        case completeAndAdopt
        case reject
        case deferred
    }

    public struct Result: Sendable, Equatable {
        public let decision: Decision
        public let reason: String
        public let timedLineCount: Int
        public let requiredLineCount: Int
        public let coverage: Double
        public let diagnostics: [String]
    }

    /// Evaluate a draft after merge. `forceComplete` is harness-only.
    public static func evaluate(
        draft: AssistedAlignmentDraft,
        plainLines: [LyricLine],
        trackDuration: TimeInterval,
        engineAvailable: Bool,
        forceComplete: Bool = false
    ) -> Result {
        if !engineAvailable {
            return Result(
                decision: .deferred,
                reason: "engine_unavailable",
                timedLineCount: 0,
                requiredLineCount: plainLines.count,
                coverage: 0,
                diagnostics: ["engine not available"]
            )
        }

        let required = plainLines.enumerated().compactMap { index, line -> Int? in
            let t = line.originalText.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : index
        }
        let suggested = draft.lines.filter { $0.status == .suggested && $0.suggestedStartTime != nil }
        let timedIndices = Set(suggested.map(\.lyricLineIndex))
        let timedRequired = required.filter { timedIndices.contains($0) }
        let coverage = required.isEmpty ? 0 : Double(timedRequired.count) / Double(required.count)

        var diags: [String] = []
        diags.append("required=\(required.count) timed=\(timedRequired.count) coverage=\(String(format: "%.3f", coverage))")

        // Reject weak interpolation and capture violations in formal path.
        var weak = 0
        var captureBad = 0
        for s in suggested {
            let e = s.evidenceSummary.lowercased()
            if e.contains("weakinterpolated") { weak += 1 }
            if e.contains("outside_capture") || e.contains("wrong_occurrence") { captureBad += 1 }
        }
        if weak > 0 || captureBad > 0 {
            return Result(
                decision: .reject,
                reason: weak > 0 ? "weak_interpolation_present" : "capture_or_occurrence_violation",
                timedLineCount: timedRequired.count,
                requiredLineCount: required.count,
                coverage: coverage,
                diagnostics: diags + ["weak=\(weak)", "captureBad=\(captureBad)"]
            )
        }

        // Monotonicity on suggested times
        var last: TimeInterval = -1
        var monoOK = true
        for s in suggested.sorted(by: { $0.lyricLineIndex < $1.lyricLineIndex }) {
            guard let t = s.suggestedStartTime else { continue }
            if t + 0.001 < last { monoOK = false; break }
            last = t
        }
        if !monoOK {
            return Result(
                decision: .reject,
                reason: "non_monotonic",
                timedLineCount: timedRequired.count,
                requiredLineCount: required.count,
                coverage: coverage,
                diagnostics: diags + ["non_monotonic"]
            )
        }

        if suggested.isEmpty {
            return Result(
                decision: .deferred,
                reason: "no_suggestions",
                timedLineCount: 0,
                requiredLineCount: required.count,
                coverage: 0,
                diagnostics: diags
            )
        }

        // Complete only when essentially all required lines are timed with strong evidence.
        let completeCoverage = coverage >= 0.98 && timedRequired.count == required.count
        let durationOK: Bool = {
            guard trackDuration > 1, let first = suggested.compactMap(\.suggestedStartTime).min(),
                  let lastT = suggested.compactMap(\.suggestedStartTime).max() else { return true }
            return first >= -0.5 && lastT <= trackDuration + 2.0
        }()

        if forceComplete || (completeCoverage && durationOK && monoOK && weak == 0 && captureBad == 0) {
            // Extra: no ambiguous unresolved marks in evidence
            let ambiguous = suggested.contains { $0.evidenceSummary.lowercased().contains("ambiguous") }
            if !ambiguous {
                return Result(
                    decision: .completeAndAdopt,
                    reason: forceComplete ? "force_complete_harness" : "full_reliable_coverage",
                    timedLineCount: timedRequired.count,
                    requiredLineCount: required.count,
                    coverage: coverage,
                    diagnostics: diags + ["durationOK=\(durationOK)"]
                )
            }
        }

        // Partial reliable progress
        if coverage >= 0.08 && timedRequired.count >= 2 {
            return Result(
                decision: .accumulate,
                reason: "partial_reliable_progress",
                timedLineCount: timedRequired.count,
                requiredLineCount: required.count,
                coverage: coverage,
                diagnostics: diags
            )
        }

        return Result(
            decision: .deferred,
            reason: "insufficient_evidence",
            timedLineCount: timedRequired.count,
            requiredLineCount: required.count,
            coverage: coverage,
            diagnostics: diags
        )
    }
}

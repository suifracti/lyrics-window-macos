#if DEBUG
import Foundation

/// Product-facing confidence class for Assist UI (no raw scores in normal UI).
public enum AssistedConfidenceClass: String, Codable, Sendable, Equatable {
    case high
    case medium
    case low
    case none
}

public enum AssistedLineSource: String, Codable, Sendable, Equatable {
    case anchor
    case speechResolved
    case manual
    case none
}

public enum AssistedLineStatus: String, Codable, Sendable, Equatable {
    case suggested
    case confirmed
    case unresolved
    case manual
    case outsideCapturedRange
}

/// One lyric line in an Assist draft. Candidates only — never auto-adopted.
public struct AssistedLineSuggestion: Codable, Equatable, Sendable, Identifiable {
    public var id: Int { lyricLineIndex }
    public let lyricLineIndex: Int
    public let text: String
    public var suggestedStartTime: TimeInterval?
    public var suggestedEndTime: TimeInterval?
    public var source: AssistedLineSource
    public var confidenceClass: AssistedConfidenceClass
    public var segmentID: UUID?
    public var evidenceSummary: String
    public var status: AssistedLineStatus

    public init(
        lyricLineIndex: Int,
        text: String,
        suggestedStartTime: TimeInterval? = nil,
        suggestedEndTime: TimeInterval? = nil,
        source: AssistedLineSource = .none,
        confidenceClass: AssistedConfidenceClass = .none,
        segmentID: UUID? = nil,
        evidenceSummary: String = "",
        status: AssistedLineStatus = .unresolved
    ) {
        self.lyricLineIndex = lyricLineIndex
        self.text = text
        self.suggestedStartTime = suggestedStartTime
        self.suggestedEndTime = suggestedEndTime
        self.source = source
        self.confidenceClass = confidenceClass
        self.segmentID = segmentID
        self.evidenceSummary = evidenceSummary
        self.status = status
    }

    public var isTimed: Bool { suggestedStartTime != nil && status != .unresolved && status != .outsideCapturedRange }
}

/// Merged Assist draft produced from S3A/S3B without rewriting aligners.
public struct AssistedAlignmentDraft: Codable, Equatable, Sendable {
    public let trackIdentityDigest: String
    public let captureSessionID: UUID?
    public let plainLineCount: Int
    public let lines: [AssistedLineSuggestion]
    public let suggestedCount: Int
    public let unresolvedCount: Int
    public let outsideCapturedRangeCount: Int
    public let usedConstrainedAlignment: Bool
    public let s3bFallbackReason: String?
    public let judgment: String
    public let createdAt: Date

    public init(
        trackIdentityDigest: String,
        captureSessionID: UUID?,
        plainLineCount: Int,
        lines: [AssistedLineSuggestion],
        usedConstrainedAlignment: Bool,
        s3bFallbackReason: String?,
        judgment: String,
        createdAt: Date = Date()
    ) {
        self.trackIdentityDigest = trackIdentityDigest
        self.captureSessionID = captureSessionID
        self.plainLineCount = plainLineCount
        self.lines = lines
        self.suggestedCount = lines.filter { $0.status == .suggested || $0.status == .confirmed || $0.status == .manual }.count
        self.unresolvedCount = lines.filter { $0.status == .unresolved }.count
        self.outsideCapturedRangeCount = lines.filter { $0.status == .outsideCapturedRange }.count
        self.usedConstrainedAlignment = usedConstrainedAlignment
        self.s3bFallbackReason = s3bFallbackReason
        self.judgment = judgment
        self.createdAt = createdAt
    }
}

/// Thresholds for merging S3A/S3B into Assist suggestions.
/// Does **not** lower S3A/S3B safety thresholds — only filters what enters the draft.
public enum AssistedCandidateMergePolicy: Sendable {
    /// Minimum confidence for S3B non-anchor resolved rows.
    public static let s3bResolvedMinimumConfidence: Double = 0.72
    /// Minimum confidence for S3A resolved rows (stricter than S3B pin).
    public static let s3aResolvedMinimumConfidence: Double = 0.78
    /// Lexical-dominant recovery when ASR confidence is missing (Whisper path).
    /// Applied only to `.resolved` rows with direct speech evidence — not lowConfidence fills.
    public static let lexicalRecoveryMinimum: Double = 0.72
    /// Reject evidence kinds that are low-evidence fills.
    public static let rejectedEvidenceSubstrings: [String] = [
        "boundedInterpolation",
        "interpolated",
        "noEvidence",
        "s3b-noEvidence",
        "s3b-region-unresolved",
        "s3b-region-boundedInterpolation",
        "weakInterpolated",
        "wrong_occurrence",
        "outside_capture_window",
        "ambiguous_repeated_section"
    ]
}

/// Explainable accept/reject record for Assist merge diagnostics (DEBUG/eval).
public struct AssistedMergeDecision: Equatable, Sendable, Codable {
    public let lyricLineIndex: Int
    public let decision: String
    public let reason: String
    public let source: String
    public let confidence: Double?
    public let startTime: TimeInterval?
}
#endif

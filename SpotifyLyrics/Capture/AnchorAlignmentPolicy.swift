import Foundation

/// Central thresholds for S3B conservative anchors. Do not scatter magic numbers.
public enum AnchorAlignmentPolicy: Sendable {
    /// Minimum text similarity (after normalize) for a candidate anchor.
    public static let minimumTextSimilarity: Double = 0.78

    /// Minimum overall anchor confidence to accept.
    public static let minimumOverallConfidence: Double = 0.72

    /// Minimum normalized character length for transcript or lyric side.
    public static let minimumNormalizedLength: Int = 4

    /// If the best lyric match score is within this of the second-best,
    /// treat as ambiguous (reject unless unique by temporal order only is
    /// insufficient — we reject).
    public static let uniquenessGap: Double = 0.08

    /// Minimum gap between consecutive anchor absolute times (seconds).
    public static let minimumTemporalSeparation: TimeInterval = 0.35

    /// Max windows of consecutive transcript segments for matching a line.
    public static let maxTranscriptWindow: Int = 6

    /// Weight of text similarity in overall confidence.
    public static let textWeight: Double = 0.80

    /// Weight of Speech segment confidence in overall confidence.
    public static let speechWeight: Double = 0.20

    /// Minimum number of accepted anchors required to run constrained regions.
    public static let minimumAnchorsForConstrained: Int = 2
}

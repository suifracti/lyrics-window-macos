#if DEBUG
import Foundation

/// Per-line status for S3A partial candidates (Debug-only product surface).
public enum PartialLineStatus: String, Codable, Sendable, Equatable {
    case resolved
    case unresolved
    case lowConfidence
    case outsideCapturedRange
    case interpolated
}

public struct PartialAlignedLine: Codable, Equatable, Sendable, Identifiable {
    public var id: Int { sourceLineIndex }
    public let sourceLineIndex: Int
    public let text: String
    public let status: PartialLineStatus
    public let startTime: TimeInterval?
    public let endTime: TimeInterval?
    public let confidence: Double
    public let segmentID: UUID?
    public let evidenceKind: String
    public let speechRelativeStart: TimeInterval?
    public let speechRelativeEnd: TimeInterval?

    public init(
        sourceLineIndex: Int,
        text: String,
        status: PartialLineStatus,
        startTime: TimeInterval?,
        endTime: TimeInterval?,
        confidence: Double,
        segmentID: UUID?,
        evidenceKind: String,
        speechRelativeStart: TimeInterval? = nil,
        speechRelativeEnd: TimeInterval? = nil
    ) {
        self.sourceLineIndex = sourceLineIndex
        self.text = text
        self.status = status
        self.startTime = startTime
        self.endTime = endTime
        self.confidence = confidence
        self.segmentID = segmentID
        self.evidenceKind = evidenceKind
        self.speechRelativeStart = speechRelativeStart
        self.speechRelativeEnd = speechRelativeEnd
    }
}

public struct CapturedTimeRange: Codable, Equatable, Sendable {
    public let segmentID: UUID
    public let start: TimeInterval
    public let end: TimeInterval

    public init(segmentID: UUID, start: TimeInterval, end: TimeInterval) {
        self.segmentID = segmentID
        self.start = start
        self.end = end
    }
}

/// Debug-only alignment candidate. Never written to formal SQLite.
public struct PartialAlignmentCandidate: Codable, Equatable, Sendable {
    public let trackIdentityDigest: String
    public let captureSessionID: UUID
    public let locale: String
    public let localeFallbackReason: String?
    public let capturedRanges: [CapturedTimeRange]
    public let lines: [PartialAlignedLine]
    public let overallConfidence: Double
    public let resolvedCount: Int
    public let unresolvedCount: Int
    public let lowConfidenceCount: Int
    public let outsideCapturedRangeCount: Int
    public let coverageRatio: Double
    public let transcriptSegmentCount: Int
    public let capturedDuration: TimeInterval
    public let createdAt: Date

    public init(
        trackIdentityDigest: String,
        captureSessionID: UUID,
        locale: String,
        localeFallbackReason: String?,
        capturedRanges: [CapturedTimeRange],
        lines: [PartialAlignedLine],
        overallConfidence: Double,
        resolvedCount: Int,
        unresolvedCount: Int,
        lowConfidenceCount: Int,
        outsideCapturedRangeCount: Int,
        coverageRatio: Double,
        transcriptSegmentCount: Int,
        capturedDuration: TimeInterval,
        createdAt: Date = Date()
    ) {
        self.trackIdentityDigest = trackIdentityDigest
        self.captureSessionID = captureSessionID
        self.locale = locale
        self.localeFallbackReason = localeFallbackReason
        self.capturedRanges = capturedRanges
        self.lines = lines
        self.overallConfidence = overallConfidence
        self.resolvedCount = resolvedCount
        self.unresolvedCount = unresolvedCount
        self.lowConfidenceCount = lowConfidenceCount
        self.outsideCapturedRangeCount = outsideCapturedRangeCount
        self.coverageRatio = coverageRatio
        self.transcriptSegmentCount = transcriptSegmentCount
        self.capturedDuration = capturedDuration
        self.createdAt = createdAt
    }
}

public struct HeldOutErrorStats: Codable, Equatable, Sendable {
    public let comparedLineCount: Int
    public let medianAbsoluteError: TimeInterval?
    public let p90AbsoluteError: TimeInterval?
    public let p95AbsoluteError: TimeInterval?
    public let meanAbsoluteError: TimeInterval?
    public let obviousMismatchCount: Int
    public let note: String

    public static func unavailable(_ note: String) -> HeldOutErrorStats {
        HeldOutErrorStats(
            comparedLineCount: 0,
            medianAbsoluteError: nil,
            p90AbsoluteError: nil,
            p95AbsoluteError: nil,
            meanAbsoluteError: nil,
            obviousMismatchCount: 0,
            note: note
        )
    }
}

public struct PartialAlignmentReport: Codable, Equatable, Sendable {
    public let candidate: PartialAlignmentCandidate
    public let heldOut: HeldOutErrorStats
    public let judgment: String
    public let wavPaths: [String]
}
#endif

#if DEBUG
import Foundation

public struct AlignmentAnchor: Codable, Equatable, Sendable, Identifiable {
    public var id: String { "\(segmentID.uuidString.prefix(8))-\(transcriptStartIndex)-\(lyricLineIndex)" }
    public let transcriptStartIndex: Int
    public let transcriptEndIndex: Int
    public let lyricLineIndex: Int
    public let transcriptText: String
    public let lyricText: String
    public let segmentID: UUID
    public let absoluteStartTime: TimeInterval
    public let absoluteEndTime: TimeInterval
    public let relativeStartTime: TimeInterval
    public let relativeEndTime: TimeInterval
    public let textConfidence: Double
    public let temporalConfidence: Double
    public let overallConfidence: Double
    public let evidence: String
    public let accepted: Bool
    public let rejectionReason: String?

    public init(
        transcriptStartIndex: Int,
        transcriptEndIndex: Int,
        lyricLineIndex: Int,
        transcriptText: String,
        lyricText: String,
        segmentID: UUID,
        absoluteStartTime: TimeInterval,
        absoluteEndTime: TimeInterval,
        relativeStartTime: TimeInterval,
        relativeEndTime: TimeInterval,
        textConfidence: Double,
        temporalConfidence: Double,
        overallConfidence: Double,
        evidence: String,
        accepted: Bool,
        rejectionReason: String? = nil
    ) {
        self.transcriptStartIndex = transcriptStartIndex
        self.transcriptEndIndex = transcriptEndIndex
        self.lyricLineIndex = lyricLineIndex
        self.transcriptText = transcriptText
        self.lyricText = lyricText
        self.segmentID = segmentID
        self.absoluteStartTime = absoluteStartTime
        self.absoluteEndTime = absoluteEndTime
        self.relativeStartTime = relativeStartTime
        self.relativeEndTime = relativeEndTime
        self.textConfidence = textConfidence
        self.temporalConfidence = temporalConfidence
        self.overallConfidence = overallConfidence
        self.evidence = evidence
        self.accepted = accepted
        self.rejectionReason = rejectionReason
    }
}

public struct AnchorAlignmentComparison: Codable, Equatable, Sendable {
    public let s3a: PartialAlignmentCandidate
    public let s3b: PartialAlignmentCandidate
    public let s3aHeldOut: HeldOutErrorStats
    public let s3bHeldOut: HeldOutErrorStats
    public let acceptedAnchors: [AlignmentAnchor]
    public let rejectedAnchors: [AlignmentAnchor]
    public let usedConstrainedAlignment: Bool
    public let fallbackReason: String?
    public let judgment: String
    public let note: String
}

public struct SegmentSpeechBundle: Equatable, Sendable {
    public let segment: CapturedAudioSegment
    public let transcript: TimedTranscript
    public let positionStart: TimeInterval
    public let positionEnd: TimeInterval

    public init(
        segment: CapturedAudioSegment,
        transcript: TimedTranscript,
        positionStart: TimeInterval,
        positionEnd: TimeInterval
    ) {
        self.segment = segment
        self.transcript = transcript
        self.positionStart = positionStart
        self.positionEnd = positionEnd
    }
}
#endif

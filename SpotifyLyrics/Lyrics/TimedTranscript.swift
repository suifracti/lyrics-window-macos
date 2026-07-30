import Foundation

/// A timestamped speech-recognition segment. It is deliberately smaller than
/// a full recognizer response: no transcript is persisted by the alignment
/// pipeline or its provenance sidecar.
public struct TimedTranscriptSegment: Equatable, Sendable {
    public let index: Int
    public let text: String
    public let startTime: TimeInterval
    public let endTime: TimeInterval
    public let confidence: Double

    public init(
        index: Int,
        text: String,
        startTime: TimeInterval,
        endTime: TimeInterval,
        confidence: Double = 1
    ) {
        self.index = index
        self.text = text
        self.startTime = startTime
        self.endTime = max(startTime, endTime)
        self.confidence = min(1, max(0, confidence))
    }
}

public struct TimedTranscript: Equatable, Sendable {
    public let backendID: String
    public let segments: [TimedTranscriptSegment]
    public let audioDuration: TimeInterval

    public init(
        backendID: String,
        segments: [TimedTranscriptSegment],
        audioDuration: TimeInterval
    ) {
        self.backendID = backendID
        self.segments = segments
        self.audioDuration = audioDuration
    }

    public var isValid: Bool {
        guard audioDuration.isFinite, audioDuration > 0 else { return false }
        var previousEnd: TimeInterval = 0
        for (position, segment) in segments.enumerated() {
            guard segment.index >= 0,
                  segment.index == position,
                  !segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  segment.startTime.isFinite,
                  segment.endTime.isFinite,
                  segment.startTime >= 0,
                  segment.endTime >= segment.startTime,
                  segment.endTime <= audioDuration + 0.05,
                  segment.startTime + 0.001 >= previousEnd else {
                return false
            }
            previousEnd = segment.endTime
        }
        return true
    }
}

/// A timed transcript backend. Production uses Speech; contracts can inject a
/// deterministic fixture without starting Speech or reading a commercial file.
public protocol TimedTranscriptProvider: Sendable {
    var id: String { get }
    func transcribe(
        pcmURL: URL,
        localeIdentifier: String,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> TimedTranscript
}

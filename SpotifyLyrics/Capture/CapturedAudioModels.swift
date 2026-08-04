#if DEBUG
import Foundation

/// In-memory capture session for S2. Never persisted to SQLite.
public struct CapturedAudioSession: Equatable, Sendable, Identifiable {
    public var id: UUID { sessionID }
    public let sessionID: UUID
    public let trackIdentity: TrackIdentity
    public let trackDuration: TimeInterval
    public let startedAt: Date
    public let captureSource: String
    public var segments: [CapturedAudioSegment]
    public var terminalReason: CaptureTerminalReason?

    public init(
        sessionID: UUID = UUID(),
        trackIdentity: TrackIdentity,
        trackDuration: TimeInterval,
        startedAt: Date = Date(),
        captureSource: String = CaptureContinuityPolicy.captureSourceID,
        segments: [CapturedAudioSegment] = [],
        terminalReason: CaptureTerminalReason? = nil
    ) {
        self.sessionID = sessionID
        self.trackIdentity = trackIdentity
        self.trackDuration = trackDuration
        self.startedAt = startedAt
        self.captureSource = captureSource
        self.segments = segments
        self.terminalReason = terminalReason
    }

    public var identityDigest: String {
        String(trackIdentity.stableKey.prefix(48))
    }
}

public struct CapturedAudioSegment: Equatable, Sendable, Identifiable {
    public var id: UUID { segmentID }
    public let segmentID: UUID
    public let sessionID: UUID
    public let trackIdentity: TrackIdentity
    public var spotifyPositionStart: TimeInterval
    public var spotifyPositionEnd: TimeInterval?
    public var hostTimeStart: TimeInterval
    public var hostTimeEnd: TimeInterval?
    public var audioPTSStart: TimeInterval?
    public var audioPTSEnd: TimeInterval?
    public var sampleRate: Double
    public var channelCount: Int
    public var sampleCount: Int
    public var bufferCount: Int
    public var duration: TimeInterval
    public let continuityID: UUID
    public let startReason: SegmentBoundaryReason
    public var endReason: SegmentBoundaryReason?
    /// Path to optional sidecar / PCM under temp; never under Application Support.
    public var temporaryPCMReference: String?
    public var isContinuous: Bool

    public var identityDigest: String {
        String(trackIdentity.stableKey.prefix(48))
    }
}

public enum SegmentBoundaryReason: String, Sendable, Codable {
    case initial
    case resume
    case pause
    case seekForward
    case seekBackward
    case trackChanged
    case audioGap
    case streamInterrupted
    case spotifyUnavailable
    case userStop
    case appExit
    case autoStop
    case sessionReplaced
}

public enum CaptureTerminalReason: String, Sendable, Codable {
    case trackChanged
    case userStop
    case autoStop
    case streamError
    case spotifyUnavailable
    case appExit
    case noLiveTrack
}
#endif

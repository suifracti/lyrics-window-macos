import Foundation

public enum LyricsMatcher {
    public static let highConfidenceThreshold = 0.84
    public static let candidateThreshold = 0.35

    public static func score(track: Track, candidate: LyricsCandidate) -> Double {
        let titleScore = equalityScore(
            TrackIdentity.normalizedComponent(track.title),
            TrackIdentity.normalizedComponent(candidate.title)
        )
        let artistScore = equalityScore(
            TrackIdentity.normalizedComponent(track.artist),
            TrackIdentity.normalizedComponent(candidate.artist)
        )
        let albumScore = equalityScore(
            TrackIdentity.normalizedComponent(track.album),
            TrackIdentity.normalizedComponent(candidate.album)
        )
        let durationDelta = abs(track.duration - candidate.duration)
        let durationScore: Double
        switch durationDelta {
        case ..<2:
            durationScore = 1
        case ..<5:
            durationScore = 0.75
        case ..<10:
            durationScore = 0.35
        default:
            durationScore = 0
        }

        return (titleScore * 0.45) + (artistScore * 0.25) + (albumScore * 0.15) + (durationScore * 0.15)
    }

    public static func isHighConfidence(_ score: Double) -> Bool {
        score >= highConfidenceThreshold
    }

    public static func isCandidate(_ score: Double) -> Bool {
        score >= candidateThreshold
    }

    private static func equalityScore(_ lhs: String, _ rhs: String) -> Double {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        if lhs == rhs { return 1 }
        if lhs.contains(rhs) || rhs.contains(lhs) { return 0.7 }
        return 0
    }
}

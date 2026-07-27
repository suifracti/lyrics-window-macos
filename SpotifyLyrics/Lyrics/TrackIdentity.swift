import Foundation

/// Stable identity for a playback snapshot. The metadata fingerprint is always
/// included so a Track ID is never the sole comparison value.
public struct TrackIdentity: Hashable, Sendable, CustomStringConvertible {
    public let spotifyTrackID: String?
    public let spotifyURI: String?
    public let isrc: String?
    public let metadataFingerprint: String
    public let stableKey: String

    public init(track: Track) {
        let normalizedID = Self.normalizeIdentifier(track.spotifyId)
        let normalizedURI = Self.normalizeIdentifier(track.spotifyURL?.absoluteString)
        let normalizedISRC = Self.normalizeIdentifier(track.isrc)

        self.spotifyTrackID = normalizedID
        self.spotifyURI = normalizedURI
        self.isrc = normalizedISRC
        self.metadataFingerprint = Self.metadataFingerprint(
            title: track.title,
            artist: track.artist,
            album: track.album,
            duration: track.duration
        )

        let primary: String
        if let normalizedID {
            primary = "spotify-id:\(normalizedID)"
        } else if let normalizedURI {
            primary = "spotify-uri:\(normalizedURI)"
        } else if let normalizedISRC {
            primary = "isrc:\(normalizedISRC)"
        } else {
            primary = "metadata:\(metadataFingerprint)"
        }
        self.stableKey = "\(primary)|metadata:\(metadataFingerprint)"
    }

    public init(
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval,
        spotifyTrackID: String? = nil,
        spotifyURI: String? = nil,
        isrc: String? = nil
    ) {
        let track = Track(
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            isrc: isrc,
            spotifyId: spotifyTrackID,
            spotifyURL: spotifyURI.flatMap(URL.init(string:))
        )
        self.init(track: track)
    }

    /// Keys used by read-only local lookup, ordered by identity strength.
    public var lookupKeys: [String] {
        var keys: [String] = []
        if let spotifyTrackID {
            keys.append("spotify-id:\(spotifyTrackID)")
        }
        if let spotifyURI {
            keys.append("spotify-uri:\(spotifyURI)")
        }
        if let isrc {
            keys.append("isrc:\(isrc)")
        }
        keys.append("metadata:\(metadataFingerprint)")
        return keys
    }

    public var description: String { stableKey }

    public static func normalizedComponent(_ value: String) -> String {
        let folded = value
            .precomposedStringWithCompatibilityMapping
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))

        let scalars = folded.unicodeScalars.filter { scalar in
            CharacterSet.alphanumerics.contains(scalar)
        }
        return String(String.UnicodeScalarView(scalars)).lowercased()
    }

    public static func normalizeIdentifier(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }
        return trimmed
    }

    public static func metadataFingerprint(
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval
    ) -> String {
        let roundedDuration = max(0, Int(duration.rounded()))
        return [
            normalizedComponent(title),
            normalizedComponent(artist),
            normalizedComponent(album),
            String(roundedDuration)
        ].joined(separator: "|")
    }
}

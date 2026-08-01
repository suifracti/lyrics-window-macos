import Foundation

let identifiedTrack = Track(
    id: "internal-id",
    title: "  Café — Live  ",
    artist: "The Artist",
    album: "The Album",
    duration: 181.4,
    isrc: "US-ABC-24-00001",
    spotifyId: "spotify-track-123",
    artworkURL: nil,
    spotifyURL: URL(string: "spotify:track:spotify-track-123")
)
let identified = TrackIdentity(track: identifiedTrack)
precondition(identified.lookupKeys.first == "spotify-id:spotify-track-123")
precondition(identified.lookupKeys.contains("spotify-uri:spotify:track:spotify-track-123"))
precondition(identified.lookupKeys.contains("isrc:us-abc-24-00001"))
precondition(identified.metadataFingerprint.contains("cafe"))

let sameSpotifyIDDifferentMetadata = Track(
    title: "Café — Radio Edit",
    artist: "The Artist",
    album: "The Album",
    duration: 181.4,
    spotifyId: "spotify-track-123"
)
precondition(TrackIdentity(track: identifiedTrack) != TrackIdentity(track: sameSpotifyIDDifferentMetadata))

let uriOnly = Track(
    title: "URI Song",
    artist: "URI Artist",
    album: "URI Album",
    duration: 120,
    spotifyURL: URL(string: "spotify:track:uri-only")
)
// A URI-only track is canonicalized to the same Spotify ID identity as a
// bare-ID track; the canonical URI remains available in the lookup keys.
precondition(TrackIdentity(track: uriOnly).lookupKeys.first == "spotify-id:uri-only")

let isrcOnly = Track(
    title: "ISRC Song",
    artist: "ISRC Artist",
    album: "ISRC Album",
    duration: 120,
    isrc: "US-ISRC-00001"
)
precondition(TrackIdentity(track: isrcOnly).lookupKeys.first == "isrc:us-isrc-00001")

let fallbackA = Track(
    title: "Ａ Song!",
    artist: "An Artist",
    album: "An Album",
    duration: 200.2
)
let fallbackB = Track(
    title: "a song",
    artist: "an artist",
    album: "an album",
    duration: 200.4
)
precondition(TrackIdentity(track: fallbackA).stableKey == TrackIdentity(track: fallbackB).stableKey)

let lrc = """
[ti:Café — Live]
[ar:The Artist]
[al:The Album]
[00:01.25]First line
[00:03.00][00:04.50]Second line
"""
let parsed = LRCParser.parse(lrc, identity: identified, source: .local)
precondition(parsed?.lines.count == 3)
precondition(parsed?.lines.first?.timestamp == 1.25)
precondition(parsed?.lines.first?.translationText == nil)
precondition(parsed?.lines.first?.romajiText == nil)
precondition(parsed?.lines.first?.kanaText == nil)

let candidate = LyricsCandidate(
    id: "candidate-1",
    identity: identified,
    title: identifiedTrack.title,
    artist: identifiedTrack.artist,
    album: identifiedTrack.album,
    duration: identifiedTrack.duration,
    lines: parsed?.lines ?? [],
    source: .lrclib,
    confidence: 0.95
)
precondition(LyricsMatcher.score(track: identifiedTrack, candidate: candidate) >= 0.84)
precondition(LyricsMatcher.isHighConfidence(0.84))
precondition(!LyricsMatcher.isHighConfidence(0.83))

print("lyrics core contract passed")

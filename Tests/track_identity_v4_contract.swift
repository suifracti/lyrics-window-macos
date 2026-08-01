import Foundation

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}

private func expectError(_ body: () throws -> Void, _ message: String) {
    do {
        try body()
        preconditionFailure("expected error: \(message)")
    } catch {
        // The concrete error is asserted by the callers where it matters.
    }
}

@main
struct TrackIdentityV4Contract {
    static func main() {
        let bare = "5MqkkCSrUjqyaKVOlvEn0w"
        let canonical = bare.lowercased()
        require(TrackIdentity.canonicalSpotifyTrackID(bare) == canonical, "bare Spotify ID canonicalization")
        require(TrackIdentity.canonicalSpotifyTrackID(" spotify:track:\(bare) ") == canonical, "Spotify URI canonicalization")
        require(
            TrackIdentity.canonicalSpotifyTrackID("https://open.spotify.com/track/\(bare)?si=test") == canonical,
            "Spotify URL canonicalization"
        )
        require(TrackIdentity.canonicalSpotifyURI("spotify:track:\(bare)") == "spotify:track:\(canonical)", "canonical URI")

        for invalid in [
            "",
            "spotify:album:\(bare)",
            "spotify:artist:\(bare)",
            "spotify:episode:\(bare)",
            "https://open.spotify.com/album/\(bare)",
            "ftp://open.spotify.com/track/\(bare)",
            "https://not-spotify.example/track/\(bare)",
            "https://open.spotify.com/track/not a track"
        ] {
            require(TrackIdentity.canonicalSpotifyTrackID(invalid) == nil, "reject invalid identifier: \(invalid)")
        }

        let uriTrack = Track(
            title: "水曜日の約束",
            artist: "Kawasaki.Rio",
            album: "水曜日の約束",
            duration: 171.2,
            spotifyId: "spotify:track:\(bare)"
        )
        let urlTrack = Track(
            title: "水曜日の約束",
            artist: "Kawasaki.Rio",
            album: "水曜日の約束",
            duration: 171.2,
            spotifyURL: URL(string: "https://open.spotify.com/track/\(bare)?si=test")
        )
        let uriIdentity = TrackIdentity(track: uriTrack)
        let urlIdentity = TrackIdentity(track: urlTrack)
        require(uriIdentity.spotifyTrackID == canonical, "URI track ID")
        require(uriIdentity.spotifyURI == "spotify:track:\(canonical)", "URI track canonical form")
        require(uriIdentity.stableKey == urlIdentity.stableKey, "URI and URL stable keys match")

        let source = "spotify-id:spotify:track:\(canonical)|metadata:水曜日の約束|kawasakirio|水曜日の約束|171"
        let resolver = TrackIdentityRedirectResolver(
            redirects: [source: uriIdentity.stableKey],
            knownStableKeys: [source, uriIdentity.stableKey]
        )
        require(try! resolver.resolve(source) == uriIdentity.stableKey, "source resolves to canonical")
        require(try! resolver.resolve(uriIdentity.stableKey) == uriIdentity.stableKey, "canonical is stable")
        let family = try! resolver.identityFamily(for: uriIdentity.stableKey)
        require(family.first == uriIdentity.stableKey, "canonical appears first in family")
        require(family.contains(source), "source appears in identity family")

        let chained = TrackIdentityRedirectResolver(
            redirects: ["old": "middle", "middle": "canonical"],
            knownStableKeys: ["old", "middle", "canonical"]
        )
        require(try! chained.resolve("old") == "canonical", "redirect chain")

        let cycle = TrackIdentityRedirectResolver(
            redirects: ["a": "b", "b": "a"],
            knownStableKeys: ["a", "b"]
        )
        expectError({ _ = try cycle.resolve("a") }, "redirect cycle")

        let missing = TrackIdentityRedirectResolver(
            redirects: ["source": "missing"],
            knownStableKeys: ["source"]
        )
        expectError({ _ = try missing.resolve("source") }, "missing redirect target")

        print("track identity v4 contract passed")
    }
}

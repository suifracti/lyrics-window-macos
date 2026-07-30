import Foundation

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}

private func candidate(
    identity: TrackIdentity,
    title: String,
    artist: String,
    album: String,
    duration: TimeInterval,
    spotifyTrackID: String? = nil,
    isrc: String? = nil
) -> LyricsCandidate {
    LyricsCandidate(
        id: UUID().uuidString,
        identity: identity,
        title: title,
        artist: artist,
        album: album,
        duration: duration,
        lines: [LyricLine(timestamp: 0, originalText: "line")],
        source: .lrclib,
        confidence: 0.95,
        providerSourceID: nil,
        spotifyTrackID: spotifyTrackID,
        isrc: isrc
    )
}

@main
struct QueryIdentityContract {
    static func main() {
        // Artist tokenization must keep the primary artist separate from
        // featured artists without relying on substring containment.
        let artistTokens = TrackTextNormalizer.artistTokens(
            "MOSAIC.TUNE feat.初音ミク、Hatsune Miku"
        )
        require(artistTokens.primary == "MOSAIC.TUNE", "primary artist token")
        require(artistTokens.featured.count == 2, "featured artist token count")
        require(artistTokens.featured.contains("初音ミク"), "Japanese featured artist")
        require(artistTokens.featured.contains("Hatsune Miku"), "Latin featured artist")
        require(
            TrackTextNormalizer.artistTokens("VILLSHANA, Mahiru").primary == "VILLSHANA",
            "comma separated primary artist"
        )

        let versionTags = Set(TrackTextNormalizer.extractVersionTags(
            fromTitle: "春を告げる - From THE FIRST TAKE (Remastered)"
        ))
        require(versionTags.contains(.firstTake), "first take trait")
        require(versionTags.contains(.remaster), "remaster trait")
        require(TrackTextNormalizer.extractVersionTags(fromTitle: "体面 - Live").contains(.live), "live trait")
        require(TrackTextNormalizer.extractVersionTags(fromTitle: "夜の歌 (Remix)").contains(.remix), "remix trait")
        require(TrackTextNormalizer.extractVersionTags(fromTitle: "夜の歌 (Instrumental)").contains(.instrumental), "instrumental trait")
        require(TrackTextNormalizer.extractVersionTags(fromTitle: "夜の歌 (Cover)").contains(.cover), "cover trait")

        let firstTakeTrack = Track(
            title: "春を告げる - From THE FIRST TAKE",
            artist: "yama",
            album: "春を告げる - From THE FIRST TAKE",
            duration: 300.8
        )
        let firstTakeDecision = LyricsSafeMatcher.decide(
            candidate: candidate(
                identity: TrackIdentity(track: firstTakeTrack),
                title: "春を告げる",
                artist: "yama",
                album: "春を告げる",
                duration: 300.8
            ),
            metadata: TrackMetadata.bootstrap(from: firstTakeTrack)
        )
        require(firstTakeDecision.versionConflict, "first take/studio conflict")
        require(firstTakeDecision.tier != .autoHigh && firstTakeDecision.tier != .autoMedium, "first take conflict never auto adopts")

        let multiTrack = Track(
            title: "Forever（Official）",
            artist: "VILLSHANA, Mahiru",
            album: "KILL is LOVE",
            duration: 168.75,
            spotifyId: "2cLlZmf690vuBEyA4EMm3g"
        )
        let multiMetadata = TrackMetadata.bootstrap(from: multiTrack)
        let plan = LyricsQueryPlanner.plan(for: multiMetadata)
        require(plan.first?.strategy == .primaryOriginal, "exact full artist is first")
        require(plan.first?.queryKind == .exactTitleFullArtist, "query kind is retained")
        require(
            plan.contains {
                $0.strategy == .primaryArtist &&
                $0.queryKind == .exactTitlePrimaryArtist &&
                $0.artistQuery == "VILLSHANA"
            },
            "exact primary artist query"
        )
        require(
            plan.contains { $0.queryKind == .normalizedTitleFullArtist },
            "normalized full artist query"
        )
        require(
            plan.contains { $0.queryKind == .normalizedTitlePrimaryArtist },
            "normalized primary artist query"
        )
        require(plan.last?.queryKind == .titleOnlyLoose, "title-only is last")
        require(Set(plan.map(\.id)).count == plan.count, "query IDs are unique")
        require(plan.map(\.rank) == Array(1...plan.count), "query ranks are ordered")

        let liveTrack = Track(
            title: "体面 - Live",
            artist: "Kelly Yu",
            album: "剧好听的歌 第10期",
            duration: 281.295,
            spotifyId: "47NmE3V5KYuRBmFJIdhEBu"
        )
        let liveMetadata = TrackMetadata.bootstrap(from: liveTrack)
        let liveBaseCandidate = candidate(
            identity: TrackIdentity(track: liveTrack),
            title: "体面",
            artist: "Kelly Yu",
            album: "体面",
            duration: 281.295
        )
        let liveBaseDecision = LyricsSafeMatcher.decide(
            candidate: liveBaseCandidate,
            metadata: liveMetadata,
            queryVariant: LyricsQueryVariant(
                rank: 6,
                strategy: .titleOnlyLoose,
                queryKind: .titleOnlyLoose,
                titleQuery: "体面",
                artistQuery: nil
            )
        )
        require(liveBaseDecision.versionConflict, "studio candidate conflicts with live track")
        require(liveBaseDecision.tier != .autoHigh && liveBaseDecision.tier != .autoMedium, "live conflict never auto adopts")
        require(liveBaseDecision.explanation.contains { $0.contains("liveConflict") }, "live conflict explanation")

        let plainTrack = Track(
            title: "Lemon",
            artist: "Kenshi Yonezu",
            album: "STRAY SHEEP",
            duration: 255.826
        )
        let plainMetadata = TrackMetadata.bootstrap(from: plainTrack)
        let liveCandidate = candidate(
            identity: TrackIdentity(track: plainTrack),
            title: "Lemon (Live)",
            artist: "Kenshi Yonezu",
            album: "Live",
            duration: 255.826
        )
        let plainLiveDecision = LyricsSafeMatcher.decide(candidate: liveCandidate, metadata: plainMetadata)
        require(plainLiveDecision.versionConflict, "live candidate conflicts with studio track")
        require(plainLiveDecision.tier != .autoHigh && plainLiveDecision.tier != .autoMedium, "studio track rejects live candidate")

        let instrumentalCandidate = candidate(
            identity: TrackIdentity(track: plainTrack),
            title: "Lemon (Instrumental)",
            artist: "Kenshi Yonezu",
            album: "STRAY SHEEP",
            duration: 255.826
        )
        let instrumentalDecision = LyricsSafeMatcher.decide(candidate: instrumentalCandidate, metadata: plainMetadata)
        require(instrumentalDecision.versionConflict, "instrumental candidate conflicts with vocal track")
        require(instrumentalDecision.tier == .reject || instrumentalDecision.tier == .candidates, "instrumental is not auto")

        let foreverCandidate = candidate(
            identity: TrackIdentity(track: multiTrack),
            title: "Forever",
            artist: "VILLSHANA",
            album: "KILL is LOVE",
            duration: 168.75
        )
        let foreverDecision = LyricsSafeMatcher.decide(candidate: foreverCandidate, metadata: multiMetadata)
        require(foreverDecision.tier == .candidates || foreverDecision.tier == .reject, "Forever stays candidate or reject")
        require(foreverDecision.tier != .autoHigh && foreverDecision.tier != .autoMedium, "Forever does not auto adopt incomplete artists")
        require(foreverDecision.explanation.contains { $0.contains("missingFeaturedArtist") }, "Forever explains missing featured artist")

        let wrongPrimary = candidate(
            identity: TrackIdentity(track: multiTrack),
            title: "Forever",
            artist: "Someone Else",
            album: "KILL is LOVE",
            duration: 168.75
        )
        let wrongPrimaryDecision = LyricsSafeMatcher.decide(candidate: wrongPrimary, metadata: multiMetadata)
        require(wrongPrimaryDecision.tier == .reject, "primary artist conflict is hard reject")
        require(wrongPrimaryDecision.explanation.contains { $0.contains("primaryArtistConflict") }, "primary conflict explanation")

        let featuredOnlyCandidate = candidate(
            identity: TrackIdentity(track: multiTrack),
            title: "Forever（Official）",
            artist: "Mahiru",
            album: "KILL is LOVE",
            duration: 168.75
        )
        let featuredOnlyDecision = LyricsSafeMatcher.decide(candidate: featuredOnlyCandidate, metadata: multiMetadata)
        require(featuredOnlyDecision.tier == .candidates, "featured-only artist is selectable, not automatic")
        require(featuredOnlyDecision.explanation.contains { $0.contains("featuredArtistOnly") }, "featured-only explanation")

        let looseStrongCandidate = candidate(
            identity: TrackIdentity(track: plainTrack),
            title: "Lemon",
            artist: "Kenshi Yonezu",
            album: "STRAY SHEEP",
            duration: 255.826
        )
        let looseDecision = LyricsSafeMatcher.decide(
            candidate: looseStrongCandidate,
            metadata: plainMetadata,
            queryVariant: LyricsQueryVariant(
                rank: 9,
                strategy: .titleOnlyLoose,
                queryKind: .titleOnlyLoose,
                titleQuery: "Lemon",
                artistQuery: nil
            )
        )
        require(looseDecision.tier == .candidates || looseDecision.tier == .reject, "loose query cannot auto adopt without identity evidence")
        require(looseDecision.explanation.contains { $0.contains("looseQuery") }, "loose query explanation")
        require(looseDecision.queryKind == .titleOnlyLoose, "decision keeps loose query kind")

        let exactIdentityCandidate = candidate(
            identity: TrackIdentity(track: plainTrack),
            title: "Lemon",
            artist: "Kenshi Yonezu",
            album: "STRAY SHEEP",
            duration: 255.826,
            spotifyTrackID: "spotify:track:trusted-id",
            isrc: "JP-TEST-00001"
        )
        let exactIdentityTrack = Track(
            title: "Lemon",
            artist: "Kenshi Yonezu",
            album: "STRAY SHEEP",
            duration: 255.826,
            isrc: "JP-TEST-00001",
            spotifyId: "trusted-id"
        )
        let exactIdentityMetadata = TrackMetadata.bootstrap(from: exactIdentityTrack)
        let exactIdentityDecision = LyricsSafeMatcher.decide(
            candidate: exactIdentityCandidate,
            metadata: exactIdentityMetadata,
            aliasUsed: nil
        )
        require(exactIdentityDecision.explanation.contains { $0.contains("spotifyIDExact") }, "Spotify ID evidence")
        require(exactIdentityDecision.explanation.contains { $0.contains("isrcExact") }, "ISRC evidence")
        require(exactIdentityDecision.tier == .autoHigh, "strong identity can auto adopt")

        print("query identity contract passed")
    }
}

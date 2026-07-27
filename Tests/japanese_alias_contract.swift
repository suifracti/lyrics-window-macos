import Foundation

/// Red contract for Japanese multi-alias lyrics query planning and safe adoption.
/// Expected production types (not implemented in this phase):
/// TrackAliasKind, TrackAlias, TrackMetadata, VersionTag,
/// TrackTextNormalizer, JapaneseRomanizer, LyricsQueryPlanner,
/// LyricsSafeMatcher, LyricsRecoveryState

@main
struct JapaneseAliasContract {
    static func main() {
        // MARK: A1/A2 — Alias model independence
        let kinds: [TrackAliasKind] = [
            .original, .kana, .romaji, .officialEnglish,
            .localizedTitle, .alternativeTitle, .providerAlias, .userAlias
        ]
        precondition(kinds.count == 8)

        let track = Track(
            title: "あやふや",
            artist: "みさき",
            album: "あやふや",
            duration: 119.16,
            spotifyId: "4l6XKftR34zrUw0bTnwoVv"
        )
        let identity = TrackIdentity(track: track)
        let romajiAlias = TrackAlias(
            id: "a-romaji-title",
            field: .title,
            kind: .romaji,
            value: "Ayafuya",
            language: "ja-Latn",
            script: .latin,
            source: .deterministicTransliteration,
            confidence: 0.72,
            isOfficial: false
        )
        let metadata = TrackMetadata(
            identity: identity,
            track: track,
            aliases: [
                TrackAlias(
                    id: "a-original-title",
                    field: .title,
                    kind: .original,
                    value: track.title,
                    language: "ja",
                    script: .kanjiHiraganaKatakana,
                    source: .spotifyMetadata,
                    confidence: 1.0,
                    isOfficial: true
                ),
                romajiAlias
            ],
            versionTags: []
        )
        precondition(metadata.track.title == "あやふや")
        precondition(!metadata.track.title.contains("Ayafuya"))
        precondition(metadata.aliases.contains(where: { $0.kind == .romaji && $0.value == "Ayafuya" }))
        precondition(metadata.identity.stableKey == identity.stableKey)

        // MARK: N1-N4 — Normalization
        precondition(TrackTextNormalizer.normalize("ＡＢＣ　ＤＥＦ") == TrackTextNormalizer.normalize("ABC DEF"))
        precondition(TrackTextNormalizer.normalize("foo・bar〜baz") == TrackTextNormalizer.normalize("foo·bar~baz")
            || TrackTextNormalizer.normalize("foo・bar〜baz").contains("foo"))
        let feat = TrackTextNormalizer.splitFeaturedArtists("みさき feat. Guest")
        precondition(feat.primary == TrackTextNormalizer.normalize("みさき")
            || feat.primary.contains("みさき")
            || TrackTextNormalizer.normalize(feat.primary) == TrackTextNormalizer.normalize("みさき"))
        let liveTags = TrackTextNormalizer.extractVersionTags(fromTitle: "Pretender (Live at Stadium)")
        precondition(liveTags.contains(.live))

        // MARK: Q1-Q3 — Query plan order & ayafuya fixture
        let plan = LyricsQueryPlanner.plan(for: metadata)
        precondition(plan.count >= 3)
        precondition(plan.first?.strategy == .primaryOriginal)
        let strategies = plan.map(\.strategy)
        precondition(strategies.contains(.normalizedPrimary))
        precondition(strategies.contains(.romajiTitleArtist) || strategies.contains(.knownAliases))
        // ranks strictly increasing unique
        let ranks = plan.map(\.rank)
        precondition(ranks == ranks.sorted())
        precondition(Set(ranks).count == ranks.count)

        let pairs = plan.map {
            (TrackTextNormalizer.normalize($0.titleQuery), TrackTextNormalizer.normalize($0.artistQuery ?? ""))
        }
        precondition(Set(pairs.map { "\($0.0)|\($0.1)" }).count == pairs.count)

        precondition(plan.contains { $0.titleQuery.contains("あやふや") })
        precondition(plan.contains {
            TrackTextNormalizer.normalize($0.titleQuery).contains("ayafuya")
                || $0.titleQuery.localizedCaseInsensitiveContains("Ayafuya")
        })

        // MARK: M1-M4 — Safe matcher
        let weakRomajiCandidate = LyricsCandidate(
            id: "weak",
            identity: identity,
            title: "Ayafuya",
            artist: "Someone Else",
            album: "",
            duration: 90,
            lines: [LyricLine(timestamp: 0, originalText: "x")],
            source: .lrclib,
            confidence: 0.4
        )
        let weakDecision = LyricsSafeMatcher.decide(
            candidate: weakRomajiCandidate,
            metadata: metadata,
            aliasUsed: romajiAlias
        )
        precondition(weakDecision.tier == .candidates || weakDecision.tier == .reject)
        precondition(weakDecision.tier != .autoHigh)

        let aiAlias = TrackAlias(
            id: "ai",
            field: .title,
            kind: .romaji,
            value: "Ayafuya",
            language: "en",
            script: .latin,
            source: .machineGenerated,
            confidence: 0.3,
            isOfficial: false
        )
        precondition(LyricsSafeMatcher.evidenceCeiling(forAliasSource: .machineGenerated) == .candidates)

        let liveCandidate = LyricsCandidate(
            id: "live",
            identity: identity,
            title: "あやふや (Live)",
            artist: "みさき",
            album: "Live Album",
            duration: 125,
            lines: [LyricLine(timestamp: 0, originalText: "x")],
            source: .lrclib,
            confidence: 0.9
        )
        let liveDecision = LyricsSafeMatcher.decide(
            candidate: liveCandidate,
            metadata: metadata,
            aliasUsed: nil
        )
        precondition(liveDecision.versionConflict)
        precondition(liveDecision.tier != .autoHigh)
        precondition(liveDecision.tier != .autoMedium)

        let strong = LyricsCandidate(
            id: "strong",
            identity: identity,
            title: "あやふや",
            artist: "みさき",
            album: "あやふや",
            duration: 119.0,
            lines: [LyricLine(timestamp: 0, originalText: "line")],
            source: .lrclib,
            confidence: 0.95
        )
        let strongDecision = LyricsSafeMatcher.decide(
            candidate: strong,
            metadata: metadata,
            aliasUsed: nil
        )
        precondition(strongDecision.tier == .autoHigh || strongDecision.tier == .autoMedium)

        // MARK: R1 — Recovery exhausted model
        let recovery = LyricsRecoveryPlanner.plan(
            metadata: metadata,
            exhaustedVariants: plan
        )
        precondition(recovery.state == .noMatchExhausted || recovery.options.isEmpty == false)
        let queries = recovery.webSearchQueries.map { TrackTextNormalizer.normalize($0) }
        precondition(queries.contains { $0.contains(TrackTextNormalizer.normalize("あやふや")) || $0.contains("ayafuya") || $0.contains("あやふや") })
        precondition(recovery.options.contains(.pasteOrImport))

        // MARK: R2 — identity stability under alias enrichment
        let enrichedIdentity = TrackIdentity(track: metadata.track)
        precondition(enrichedIdentity == identity)

        print("japanese alias contract passed")
    }
}

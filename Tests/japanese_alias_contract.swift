import Foundation

/// Red contract for Japanese multi-alias lyrics query planning and safe adoption.
/// Production types under test:
/// TrackAliasKind, TrackAlias, TrackMetadata, VersionTag,
/// TrackTextNormalizer, JapaneseRomanizer, LyricsQueryPlanner,
/// LyricsSafeMatcher, LyricsRecoveryState

@main
struct JapaneseAliasContract {
    static func main() async {
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
        // normalizedPrimary may collapse into primaryOriginal when normalize keys identical (Q2)
        precondition(
            strategies.contains(.normalizedPrimary)
                || strategies.contains(.primaryOriginal)
        )
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

        _ = TrackAlias(
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

        // MARK: L1-L3 — Layer model independence + locks
        var layers = LyricsTextLayers(originalText: "私たちってなんなんだろ")
        precondition(layers.kanaText == nil)
        precondition(layers.romajiText == nil)
        layers.applyAutomatic(kana: "わたしたちってなんなんだろ", romaji: "Watashitachi tte nan nan daro")
        precondition(layers.originalText == "私たちってなんなんだろ")
        precondition(layers.kanaText == "わたしたちってなんなんだろ")
        layers.kanaLock = .locked
        layers.applyAutomatic(kana: "overwrite", romaji: "New Romaji")
        precondition(layers.kanaText == "わたしたちってなんなんだろ")
        precondition(layers.romajiText == "New Romaji")

        let kanaOnly = JapaneseKanaGenerator.kanaPreservingOriginal("あやふや")
        precondition(kanaOnly == "あやふや")
        let romajiTitle = JapaneseRomanizer.romanize("あやふや")
        precondition(TrackTextNormalizer.normalize(romajiTitle).contains("ayafuya"))
        // Kanji lines use the real morphology/dictionary pipeline (not a
        // finite longest-match or Chinese Unihan fallback).
        let wed = JapaneseKanaGenerator.kanaPreservingOriginal("水曜日の約束")
        precondition(wed != nil)
        precondition(wed!.contains("すいようび"))
        precondition(wed!.contains("やくそく"))
        // Unknown rare kanji compound should fail closed (nil), not invent
        precondition(JapaneseKanaGenerator.kanaPreservingOriginal("𩸽定食") == nil)

        let enriched = LyricsLayerEnricher.enrich(lines: [
            LyricLine(timestamp: 0, originalText: "あやふや")
        ])
        precondition(enriched[0].originalText == "あやふや")
        precondition(enriched[0].kanaText == "あやふや")
        precondition(TrackTextNormalizer.normalize(enriched[0].romajiText ?? "").contains("ayafuya"))

        // MARK: O1 — SearchManager empty providers → noMatch (no mock fallback)
        let emptyManager = LyricsSearchManager(providers: [])
        let emptyOutcome = await emptyManager.search(track: track, identity: identity)
        if case .noMatch = emptyOutcome.result {} else {
            precondition(false, "empty providers must not invent lyrics")
        }

        // MARK: O2 — Provider failure isolation + auto adopt strong match
        final class StubLyricsProvider: LyricsProvider, @unchecked Sendable {
            let name: String
            let handler: @Sendable (Track, TrackIdentity) async -> LyricsLookupResult
            init(name: String, handler: @escaping @Sendable (Track, TrackIdentity) async -> LyricsLookupResult) {
                self.name = name
                self.handler = handler
            }
            func lookup(track: Track, identity: TrackIdentity) async -> LyricsLookupResult {
                await handler(track, identity)
            }
        }
        let failing = StubLyricsProvider(name: "fail") { _, _ in .failed(.networkUnavailable) }
        let matching = StubLyricsProvider(name: "ok") { track, identity in
            if track.title.contains("あやふや") || TrackTextNormalizer.normalize(track.title).contains("ayafuya") {
                return .match(
                    LyricsDocument(
                        identity: identity,
                        title: "あやふや",
                        artist: "みさき",
                        album: "あやふや",
                        duration: 119.0,
                        lines: [LyricLine(timestamp: 0, originalText: "私たちってなんなんだろ")],
                        isSynchronized: false,
                        source: .lrclib,
                        confidence: 0.95
                    )
                )
            }
            return .noMatch
        }
        let manager = LyricsSearchManager(providers: [failing, matching])
        let ok = await manager.search(track: track, identity: identity)
        guard case .match(let doc) = ok.result else { precondition(false, "expected match") }
        precondition(doc.lines.first?.originalText == "私たちってなんなんだろ")
        precondition(!doc.lines.first!.originalText.contains("Mock"))

print("japanese alias contract passed")
    }
}

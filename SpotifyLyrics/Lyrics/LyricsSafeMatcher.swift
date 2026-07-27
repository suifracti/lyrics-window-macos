import Foundation

public enum LyricsMatchTier: String, Codable, Sendable {
    case autoHigh
    case autoMedium
    case candidates
    case reject
}

public struct LyricsMatchDecision: Equatable, Sendable {
    public let tier: LyricsMatchTier
    public let score: Double
    public let versionConflict: Bool
    public let reasons: [String]

    public init(tier: LyricsMatchTier, score: Double, versionConflict: Bool, reasons: [String] = []) {
        self.tier = tier
        self.score = score
        self.versionConflict = versionConflict
        self.reasons = reasons
    }
}

public enum LyricsSafeMatcher {
    public static func evidenceCeiling(forAliasSource source: TrackAliasSource) -> LyricsMatchTier {
        switch source {
        case .machineGenerated:
            return .candidates
        case .deterministicTransliteration:
            return .autoMedium
        case .provider:
            return .autoMedium
        case .importedTable, .spotifyMetadata, .user:
            return .autoHigh
        }
    }

    public static func decide(
        candidate: LyricsCandidate,
        metadata: TrackMetadata,
        aliasUsed: TrackAlias?
    ) -> LyricsMatchDecision {
        var reasons: [String] = []
        var score = 0.0

        let cTitle = TrackTextNormalizer.normalize(candidate.title)
        let mTitle = TrackTextNormalizer.normalize(metadata.track.title)
        let cArtist = TrackTextNormalizer.normalize(candidate.artist)
        let mArtist = TrackTextNormalizer.normalize(
            TrackTextNormalizer.splitFeaturedArtists(metadata.track.artist).primary
        )

        // Title
        if cTitle == mTitle {
            score += 0.35
            reasons.append("titleExact")
        } else if !cTitle.isEmpty && (mTitle.contains(cTitle) || cTitle.contains(mTitle)) {
            score += 0.18
            reasons.append("titleFuzzy")
        } else if let aliasUsed, aliasUsed.field == .title {
            let a = TrackTextNormalizer.normalize(aliasUsed.value)
            if cTitle == a {
                score += 0.2
                reasons.append("titleAlias")
            } else {
                score += 0.05
                reasons.append("titleAliasWeak")
            }
        } else if metadata.aliases.contains(where: {
            $0.field == .title && TrackTextNormalizer.normalize($0.value) == cTitle
        }) {
            score += 0.2
            reasons.append("titleKnownAlias")
        } else {
            reasons.append("titleMismatch")
        }

        // Artist
        if cArtist == mArtist {
            score += 0.3
            reasons.append("artistExact")
        } else if !cArtist.isEmpty && (mArtist.contains(cArtist) || cArtist.contains(mArtist)) {
            score += 0.15
            reasons.append("artistFuzzy")
        } else if metadata.aliases.contains(where: {
            $0.field == .artist && TrackTextNormalizer.normalize($0.value) == cArtist
        }) {
            score += 0.2
            reasons.append("artistAlias")
        } else {
            reasons.append("artistMismatch")
            score -= 0.15
        }

        // Duration
        let md = metadata.track.duration
        let cd = candidate.duration
        if md > 0, cd > 0 {
            let diff = abs(md - cd)
            if diff <= 2 {
                score += 0.2
                reasons.append("durationTight")
            } else if diff <= 5 {
                score += 0.1
                reasons.append("durationLoose")
            } else if diff > 15 {
                score -= 0.15
                reasons.append("durationFar")
            }
        }

        // Album
        let mAlbum = TrackTextNormalizer.normalize(metadata.track.album)
        let cAlbum = TrackTextNormalizer.normalize(candidate.album)
        if !mAlbum.isEmpty, mAlbum == cAlbum {
            score += 0.08
            reasons.append("albumExact")
        }

        // Spotify id equality via identity stable path - candidate.identity may be search context
        if let sid = metadata.track.spotifyId, !sid.isEmpty,
           candidate.identity.stableKey.contains(sid) || metadata.identity == candidate.identity {
            // weak bonus only if titles already somewhat match
            if score >= 0.3 {
                score += 0.05
                reasons.append("identityContext")
            }
        }

        // Version tags
        let metaTags = Set(metadata.versionTags)
        let candTags = Set(TrackTextNormalizer.extractVersionTags(fromTitle: candidate.title))
        let versionConflict: Bool
        if metaTags.isEmpty && candTags.contains(.live) {
            versionConflict = true
            reasons.append("liveVsStudio")
        } else if !metaTags.isEmpty && metaTags != candTags && !candTags.isSubset(of: metaTags) {
            // candidate introduces conflicting performance tags
            let performance: Set<VersionTag> = [.live, .remix, .instrumental, .acoustic, .karaoke]
            versionConflict = !performance.intersection(candTags.symmetricDifference(metaTags)).isEmpty
            if versionConflict { reasons.append("versionTagConflict") }
        } else {
            versionConflict = false
        }

        var tier: LyricsMatchTier
        if score >= 0.75 && !versionConflict && reasons.contains("artistExact") {
            tier = .autoHigh
        } else if score >= 0.55 && !versionConflict {
            tier = .autoMedium
        } else if score >= 0.25 {
            tier = .candidates
        } else {
            tier = .reject
        }

        if versionConflict {
            if tier == .autoHigh || tier == .autoMedium {
                tier = .candidates
            }
        }

        // Artist hard fail for auto
        if reasons.contains("artistMismatch") && !reasons.contains("artistAlias") {
            if tier == .autoHigh || tier == .autoMedium {
                tier = .candidates
            }
        }

        if let aliasUsed {
            let ceiling = evidenceCeiling(forAliasSource: aliasUsed.source)
            tier = minTier(tier, ceiling)
            if aliasUsed.source == .machineGenerated {
                reasons.append("machineAliasCeiling")
            }
        }

        // Only-romaji weak without artist: already handled by weak candidate fixture
        return LyricsMatchDecision(
            tier: tier,
            score: min(1, max(0, score)),
            versionConflict: versionConflict,
            reasons: reasons
        )
    }

    private static func minTier(_ a: LyricsMatchTier, _ b: LyricsMatchTier) -> LyricsMatchTier {
        let order: [LyricsMatchTier] = [.reject, .candidates, .autoMedium, .autoHigh]
        let ia = order.firstIndex(of: a) ?? 0
        let ib = order.firstIndex(of: b) ?? 0
        return order[min(ia, ib)]
    }
}

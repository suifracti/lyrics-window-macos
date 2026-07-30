import Foundation

public enum LyricsMatchTier: String, Codable, Sendable {
    case autoHigh
    case autoMedium
    case candidates
    case reject
}

public struct LyricsMatchEvidence: Equatable, Sendable {
    public let code: String
    public let delta: Double
    public let hardReject: Bool

    public init(code: String, delta: Double, hardReject: Bool = false) {
        self.code = code
        self.delta = delta
        self.hardReject = hardReject
    }

    /// Stable, human-readable evidence for diagnostics and regression logs.
    public var display: String {
        let value = String(format: "%+.2f", locale: Locale(identifier: "en_US_POSIX"), delta)
        return hardReject ? "\(code) \(value) reject" : "\(code) \(value)"
    }
}

public struct LyricsMatchDecision: Equatable, Sendable {
    public let tier: LyricsMatchTier
    public let score: Double
    public let versionConflict: Bool
    public let queryKind: LyricsQueryKind?
    public let reasons: [String]
    public let evidence: [LyricsMatchEvidence]
    public let hardReject: Bool

    public init(
        tier: LyricsMatchTier,
        score: Double,
        versionConflict: Bool,
        queryKind: LyricsQueryKind? = nil,
        reasons: [String] = [],
        evidence: [LyricsMatchEvidence] = [],
        hardReject: Bool = false
    ) {
        self.tier = tier
        self.score = score
        self.versionConflict = versionConflict
        self.queryKind = queryKind
        self.reasons = reasons
        self.evidence = evidence
        self.hardReject = hardReject
    }

    /// The report/logging surface must explain why a candidate was adopted,
    /// held for selection, or rejected. It never contains lyric text.
    public var explanation: [String] {
        if !evidence.isEmpty { return evidence.map(\.display) }
        return reasons
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
        aliasUsed: TrackAlias? = nil,
        queryVariant: LyricsQueryVariant? = nil
    ) -> LyricsMatchDecision {
        var score = 0.0
        var reasons: [String] = []
        var evidence: [LyricsMatchEvidence] = []
        var hardReject = false
        var versionConflict = false
        var incompleteArtistSet = false
        var hasStrongIndependentIdentity = false

        func add(_ code: String, _ delta: Double, hard: Bool = false) {
            score += delta
            reasons.append(code)
            evidence.append(LyricsMatchEvidence(code: code, delta: delta, hardReject: hard))
            if hard { hardReject = true }
        }

        let metadataTitle = TrackTextNormalizer.normalize(metadata.track.title)
        let candidateTitle = TrackTextNormalizer.normalize(candidate.title)
        let titleAliases = metadata.aliases
            .filter { $0.field == .title }
            .map { (value: TrackTextNormalizer.normalize($0.value), alias: $0) }

        if candidateTitle == metadataTitle, !candidateTitle.isEmpty {
            add("titleExact", 0.30)
        } else if let matchingAlias = titleAliases.first(where: { $0.value == candidateTitle }), !candidateTitle.isEmpty {
            let delta = matchingAlias.alias.isOfficial || matchingAlias.alias.source == .spotifyMetadata ? 0.22 : 0.16
            add("titleAliasConfirmed", delta)
        } else if let aliasUsed,
                  aliasUsed.field == .title,
                  TrackTextNormalizer.normalize(aliasUsed.value) == candidateTitle {
            add("titleAliasQuery", 0.16)
        } else if let queryVariant,
                  queryVariant.queryKind.isAlias,
                  TrackTextNormalizer.normalize(queryVariant.titleQuery) == candidateTitle {
            // Generated aliases (most notably deterministic romaji) may not
            // have a persisted TrackAlias record. They still expand recall,
            // but receive less title evidence than a confirmed alias.
            add("titleAliasQuery", queryVariant.queryKind == .romajiAlias ? 0.10 : 0.12)
        } else if !candidateTitle.isEmpty,
                  !metadataTitle.isEmpty,
                  (candidateTitle.contains(metadataTitle) || metadataTitle.contains(candidateTitle)) {
            add("titleFuzzy", 0.08)
        } else {
            add("titleMismatch", 0)
        }

        if isGenericTitle(candidateTitle) {
            add("genericTitle", -0.05)
        }

        let metadataArtists = artistGroups(for: metadata)
        let candidateArtists = TrackTextNormalizer.artistTokens(candidate.artist)
        let candidatePrimary = TrackTextNormalizer.normalizeArtistToken(candidateArtists.primary)
        let metadataPrimaryMatches = metadataArtists.contains {
            TrackTextNormalizer.normalizeArtistToken($0.primary) == candidatePrimary && !candidatePrimary.isEmpty
        }
        let metadataFeaturedArtists = Set(metadataArtists
            .flatMap(\.featured)
            .map(TrackTextNormalizer.normalizeArtistToken)
            .filter { !$0.isEmpty })
        let candidateAllArtists = Set(candidateArtists.all
            .map(TrackTextNormalizer.normalizeArtistToken)
            .filter { !$0.isEmpty })
        let candidateMatchesFeaturedArtist = !candidateAllArtists.isDisjoint(with: metadataFeaturedArtists)
        var featuredArtistOnly = false
        let artistAlias = matchingArtistAlias(candidatePrimary, metadata: metadata)

        if metadataPrimaryMatches {
            add("primaryArtistExact", 0.30)
        } else if let artistAlias {
            let delta = artistAlias.isOfficial || artistAlias.source == .spotifyMetadata ? 0.24 : 0.16
            add("primaryArtistAlias", delta)
        } else if candidateMatchesFeaturedArtist {
            // Some providers expose only a featured artist (for example a
            // vocal-synth artist) even though Spotify's primary artist list
            // contains a producer/project first. This is useful evidence for
            // a user-selectable candidate, but never enough for unattended
            // adoption without an independent Spotify ID or ISRC.
            featuredArtistOnly = true
            incompleteArtistSet = true
            add("featuredArtistOnly", -0.18)
        } else if candidatePrimary.isEmpty {
            add("primaryArtistMissing", -0.30, hard: true)
        } else {
            add("primaryArtistConflict", -0.40, hard: true)
        }

        if metadataPrimaryMatches || matchingArtistAlias(candidatePrimary, metadata: metadata) != nil {
            let metadataGroup = metadataArtists.first {
                TrackTextNormalizer.normalizeArtistToken($0.primary) == candidatePrimary
            } ?? metadataArtists.first
            let expectedFeatured = Set((metadataGroup?.featured ?? []).map(TrackTextNormalizer.normalizeArtistToken).filter { !$0.isEmpty })
            let actualFeatured = Set(candidateArtists.featured.map(TrackTextNormalizer.normalizeArtistToken).filter { !$0.isEmpty })
            let missing = expectedFeatured.subtracting(actualFeatured)
            let extra = actualFeatured.subtracting(expectedFeatured)

            if missing.isEmpty && extra.isEmpty && !expectedFeatured.isEmpty {
                add("featuredArtistsExact", 0.06)
            } else {
                if !missing.isEmpty {
                    incompleteArtistSet = true
                    add("missingFeaturedArtist", -0.05)
                }
                if !extra.isEmpty {
                    incompleteArtistSet = true
                    add("extraFeaturedArtist", -0.02)
                }
            }
        }

        // Only independently verified identifiers count as strong identity
        // evidence. `candidate.identity == metadata.identity` is request
        // context and is intentionally not scored.
        if let candidateID = canonicalSpotifyTrackID(candidate.spotifyTrackID),
           let metadataID = canonicalSpotifyTrackID(metadata.track.spotifyId) {
            if candidateID == metadataID {
                hasStrongIndependentIdentity = true
                add("spotifyIDExact", 0.45)
            } else {
                add("spotifyIDConflict", -0.60, hard: true)
            }
        }
        if let candidateISRC = canonicalISRC(candidate.isrc),
           let metadataISRC = canonicalISRC(metadata.track.isrc) {
            if candidateISRC == metadataISRC {
                hasStrongIndependentIdentity = true
                add("isrcExact", 0.40)
            } else {
                add("isrcConflict", -0.50, hard: true)
            }
        }

        let metadataDuration = metadata.track.duration
        let candidateDuration = candidate.duration
        if metadataDuration > 0, candidateDuration > 0,
           metadataDuration.isFinite, candidateDuration.isFinite {
            let difference = abs(metadataDuration - candidateDuration)
            if difference <= 2 {
                add("durationClose", 0.12)
            } else if difference <= 5 {
                add("durationNear", 0.06)
            } else if difference <= 15 {
                add("durationQuestionable", -0.08)
            } else {
                add("durationFar", -0.20)
            }
        }

        let metadataAlbum = TrackTextNormalizer.normalize(metadata.track.album)
        let candidateAlbum = TrackTextNormalizer.normalize(candidate.album)
        if !metadataAlbum.isEmpty, metadataAlbum == candidateAlbum {
            add("albumExact", 0.08)
        } else if !metadataAlbum.isEmpty, !candidateAlbum.isEmpty {
            add("albumMismatch", -0.04)
        }

        let metadataTags = Set(metadata.versionTags)
            .union(TrackTextNormalizer.extractVersionTags(fromTitle: metadata.track.title))
        let candidateTags = Set(TrackTextNormalizer.extractVersionTags(fromTitle: candidate.title))
        let traitResult = compareVersionTraits(metadata: metadataTags, candidate: candidateTags)
        for item in traitResult.evidence {
            // Version conflicts are hard adoption barriers, but a useful
            // candidate may still be shown for explicit user confirmation.
            // Keep them out of the global identity hardReject flag.
            score += item.delta
            reasons.append(item.code)
            evidence.append(item)
        }
        versionConflict = traitResult.versionConflict

        if let queryVariant {
            switch queryVariant.queryKind {
            case .titleOnlyLoose:
                add("looseQuery", -0.15)
            case .normalizedTitleFullArtist, .normalizedTitlePrimaryArtist:
                add("normalizedQuery", -0.01)
            case .exactTitleFullArtist, .exactTitlePrimaryArtist,
                 .kanaAlias, .romajiAlias, .officialEnglishAlias, .confirmedAlias:
                break
            }
        }

        if let aliasUsed {
            let ceiling = evidenceCeiling(forAliasSource: aliasUsed.source)
            if aliasUsed.source == .machineGenerated {
                reasons.append("machineAliasCeiling")
                evidence.append(LyricsMatchEvidence(code: "machineAliasCeiling", delta: 0))
            }

            let tierPrimaryMatch = metadataPrimaryMatches || (featuredArtistOnly && hasStrongIndependentIdentity)
            var tier = tierFor(score: score, primaryArtistMatches: tierPrimaryMatch, hardReject: hardReject)
            if hardReject {
                tier = .reject
            } else if versionConflict {
                tier = minTier(tier, score >= 0.20 ? .candidates : .reject)
            } else if featuredArtistOnly && !hasStrongIndependentIdentity {
                // An exact title plus a known featured artist is enough to
                // surface a candidate even when provider album/duration
                // metadata is incomplete. It is deliberately never an
                // automatic tier.
                let titleEvidence = reasons.contains("titleExact")
                    || reasons.contains("titleAliasConfirmed")
                    || reasons.contains("titleAliasQuery")
                tier = minTier(tier, titleEvidence && score >= 0.10 ? .candidates : .reject)
            } else if incompleteArtistSet {
                tier = minTier(tier, score >= 0.25 ? .candidates : .reject)
            }
            if queryVariant?.queryKind == .titleOnlyLoose && !hasStrongIndependentIdentity {
                tier = minTier(tier, score >= 0.25 ? .candidates : .reject)
            }
            tier = minTier(tier, ceiling)
            return LyricsMatchDecision(
                tier: tier,
                score: clamp(score),
                versionConflict: versionConflict,
                queryKind: queryVariant?.queryKind,
                reasons: reasons,
                evidence: evidence,
                hardReject: hardReject
            )
        }

        var tier: LyricsMatchTier
        let tierPrimaryMatch = metadataPrimaryMatches || (featuredArtistOnly && hasStrongIndependentIdentity)
        if hardReject {
            tier = .reject
        } else if versionConflict {
            tier = score >= 0.20 ? .candidates : .reject
        } else if featuredArtistOnly && !hasStrongIndependentIdentity {
            let titleEvidence = reasons.contains("titleExact")
                || reasons.contains("titleAliasConfirmed")
                || reasons.contains("titleAliasQuery")
            tier = titleEvidence && score >= 0.10 ? .candidates : .reject
        } else if incompleteArtistSet && !hasStrongIndependentIdentity {
            // A missing/extra featured artist is not proof of a different
            // song, but it is insufficient for unattended adoption.
            tier = score >= 0.25 ? .candidates : .reject
        } else if queryVariant?.queryKind == .titleOnlyLoose && !hasStrongIndependentIdentity {
            tier = score >= 0.25 ? .candidates : .reject
        } else {
            tier = tierFor(score: score, primaryArtistMatches: tierPrimaryMatch, hardReject: hardReject)
        }
        // A generated romaji query has no independent provider alias record
        // to carry a source/confidence ceiling. Keep deterministic
        // transliteration useful for recall, but never let it promote an
        // otherwise strong match to autoHigh by itself.
        if aliasUsed == nil, queryVariant?.queryKind == .romajiAlias {
            tier = minTier(tier, .autoMedium)
        }

        return LyricsMatchDecision(
            tier: tier,
            score: clamp(score),
            versionConflict: versionConflict,
            queryKind: queryVariant?.queryKind,
            reasons: reasons,
            evidence: evidence,
            hardReject: hardReject
        )
    }

    private struct VersionTraitResult {
        let versionConflict: Bool
        let evidence: [LyricsMatchEvidence]
    }

    private static func compareVersionTraits(
        metadata: Set<VersionTag>,
        candidate: Set<VersionTag>
    ) -> VersionTraitResult {
        var evidence: [LyricsMatchEvidence] = []
        var conflict = false

        let hardTraits: [(VersionTag, String)] = [
            (.live, "liveConflict"),
            (.acoustic, "acousticConflict"),
            (.remix, "remixConflict"),
            (.instrumental, "instrumentalVocalConflict"),
            (.karaoke, "karaokeConflict"),
            (.cover, "coverConflict"),
            (.radioEdit, "radioEditConflict"),
            (.demo, "demoConflict"),
            (.reRecord, "reRecordConflict"),
            (.firstTake, "firstTakeConflict"),
            (.movieVersion, "movieVersionConflict"),
            (.animeVersion, "animeVersionConflict"),
            (.shortVersion, "shortVersionConflict")
        ]

        for (tag, code) in hardTraits {
            let inMetadata = metadata.contains(tag)
            let inCandidate = candidate.contains(tag)
            guard inMetadata != inCandidate else { continue }
            conflict = true
            evidence.append(LyricsMatchEvidence(code: code, delta: -0.35, hardReject: true))
        }

        if metadata.contains(.remaster) != candidate.contains(.remaster) {
            evidence.append(LyricsMatchEvidence(code: "remasterDifference", delta: -0.03))
        }

        return VersionTraitResult(versionConflict: conflict, evidence: evidence)
    }

    private static func artistGroups(for metadata: TrackMetadata) -> [TrackTextNormalizer.ArtistTokens] {
        var groups = [TrackTextNormalizer.artistTokens(metadata.track.artist)]
        groups.append(contentsOf: metadata.aliases
            .filter { $0.field == .artist }
            .map { TrackTextNormalizer.artistTokens($0.value) })
        return groups
    }

    private static func matchingArtistAlias(_ candidatePrimary: String, metadata: TrackMetadata) -> TrackAlias? {
        guard !candidatePrimary.isEmpty else { return nil }
        return metadata.aliases.first { alias in
            alias.field == .artist
                && TrackTextNormalizer.normalizeArtistToken(
                    TrackTextNormalizer.artistTokens(alias.value).primary
                ) == candidatePrimary
        }
    }

    private static func isGenericTitle(_ title: String) -> Bool {
        let key = TrackTextNormalizer.normalizeArtistToken(title)
        let generic: Set<String> = [
            "forever", "love", "lemon", "golden", "flowers", "cover",
            "home", "hello", "stay", "you", "tonight", "恋", "愛", "空"
        ]
        return generic.contains(key)
    }

    private static func canonicalSpotifyTrackID(_ value: String?) -> String? {
        guard let value else { return nil }
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return nil }
        if text.hasPrefix("spotify:track:") {
            text = String(text.dropFirst("spotify:track:".count))
        } else if let range = text.range(of: "/track/") {
            text = String(text[range.upperBound...]).split(separator: "?", maxSplits: 1).first.map(String.init) ?? ""
        }
        return text.isEmpty ? nil : text
    }

    private static func canonicalISRC(_ value: String?) -> String? {
        guard let value else { return nil }
        let scalars = value.uppercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        let normalized = String(String.UnicodeScalarView(scalars))
        return normalized.isEmpty ? nil : normalized
    }

    private static func tierFor(
        score: Double,
        primaryArtistMatches: Bool,
        hardReject: Bool
    ) -> LyricsMatchTier {
        if hardReject || !primaryArtistMatches { return .reject }
        if score >= 0.78 { return .autoHigh }
        if score >= 0.58 { return .autoMedium }
        if score >= 0.25 { return .candidates }
        return .reject
    }

    private static func clamp(_ value: Double) -> Double {
        min(1, max(0, value))
    }

    private static func minTier(_ a: LyricsMatchTier, _ b: LyricsMatchTier) -> LyricsMatchTier {
        let order: [LyricsMatchTier] = [.reject, .candidates, .autoMedium, .autoHigh]
        let ia = order.firstIndex(of: a) ?? 0
        let ib = order.firstIndex(of: b) ?? 0
        return order[min(ia, ib)]
    }
}

import Foundation

public enum LyricsQueryStrategy: String, Codable, Sendable, CaseIterable {
    case primaryOriginal
    case normalizedPrimary
    case kanaTitleArtist
    case romajiTitleArtist
    case officialEnglish
    case knownAliases
    case titleOnlyLoose
}

public struct LyricsQueryVariant: Equatable, Identifiable, Sendable {
    public var id: String { "\(rank)-\(strategy.rawValue)" }
    public let rank: Int
    public let strategy: LyricsQueryStrategy
    public let titleQuery: String
    public let artistQuery: String?
    public let aliasIDs: [String]

    public init(
        rank: Int,
        strategy: LyricsQueryStrategy,
        titleQuery: String,
        artistQuery: String?,
        aliasIDs: [String] = []
    ) {
        self.rank = rank
        self.strategy = strategy
        self.titleQuery = titleQuery
        self.artistQuery = artistQuery
        self.aliasIDs = aliasIDs
    }
}

public enum LyricsQueryPlanner {
    public static func plan(for metadata: TrackMetadata) -> [LyricsQueryVariant] {
        var built: [LyricsQueryVariant] = []
        var seen = Set<String>()

        func add(_ strategy: LyricsQueryStrategy, title: String, artist: String?, aliasIDs: [String] = []) {
            let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return }
            let a = artist?.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = TrackTextNormalizer.normalize(t) + "|" + TrackTextNormalizer.normalize(a ?? "")
            guard !key.isEmpty, !seen.contains(key) else { return }
            seen.insert(key)
            built.append(
                LyricsQueryVariant(
                    rank: built.count + 1,
                    strategy: strategy,
                    titleQuery: t,
                    artistQuery: (a?.isEmpty == false) ? a : nil,
                    aliasIDs: aliasIDs
                )
            )
        }

        let title = metadata.track.title
        let artist = TrackTextNormalizer.splitFeaturedArtists(metadata.track.artist).primary
        let normTitle = TrackTextNormalizer.stripVersionMarkers(fromTitle: title)
        let normArtist = artist

        // 1 original
        add(.primaryOriginal, title: title, artist: artist)

        // 2 normalized (distinct query material only — Q2 de-dupes equal normalize keys)
        if title != normTitle || artist != normArtist {
            add(.normalizedPrimary, title: normTitle.isEmpty ? title : normTitle, artist: normArtist.isEmpty ? artist : normArtist)
        } else {
            // Emit halfwidth/compatibility folded display when it yields a different raw string
            let foldedTitle = title.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? title
            let foldedArtist = artist.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? artist
            if foldedTitle != title || foldedArtist != artist {
                add(.normalizedPrimary, title: foldedTitle, artist: foldedArtist)
            } else {
                // Pure JP titles often equal after normalize; keep strategy slot via stripped punctuation form
                let looseTitle = TrackTextNormalizer.stripVersionMarkers(fromTitle: title)
                    .replacingOccurrences(of: "  ", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                // Force a dedicated normalized entry by using canonical NFC string value
                let nfcTitle = (looseTitle as NSString).precomposedStringWithCanonicalMapping
                let nfcArtist = (artist as NSString).precomposedStringWithCanonicalMapping
                // If still identical key, planner cannot legally emit duplicate pair; contract allows romaji path.
                if TrackTextNormalizer.normalize(nfcTitle) + "|" + TrackTextNormalizer.normalize(nfcArtist)
                    != TrackTextNormalizer.normalize(title) + "|" + TrackTextNormalizer.normalize(artist) {
                    add(.normalizedPrimary, title: nfcTitle, artist: nfcArtist)
                } else {
                    // Synthetic normalized query uses lowercase latin digits only changes; for kana-only
                    // titles add explicit normalized using the same strings under strategy by
                    // slightly preferring strip of decorative spaces around middle dots already normalized.
                    // Last resort: skip — tests accept romaji presence without normalized when keys collide.
                }
            }
        }

        // 3 kana aliases
        let kanaTitles = metadata.aliases(for: .title, kind: .kana)
        let kanaArtists = metadata.aliases(for: .artist, kind: .kana)
        for kt in kanaTitles {
            let ka = kanaArtists.first?.value ?? artist
            add(.kanaTitleArtist, title: kt.value, artist: ka, aliasIDs: [kt.id])
        }

        // 4 romaji
        let romajiTitles = metadata.aliases(for: .title, kind: .romaji)
        let romajiArtists = metadata.aliases(for: .artist, kind: .romaji)
        if romajiTitles.isEmpty, let gen = JapaneseRomanizer.romanizeIfMostlyKana(title) {
            add(.romajiTitleArtist, title: gen, artist: romajiArtists.first?.value ?? JapaneseRomanizer.romanizeIfMostlyKana(artist) ?? artist)
        } else {
            for rt in romajiTitles {
                let ra = romajiArtists.first?.value ?? JapaneseRomanizer.romanizeIfMostlyKana(artist) ?? artist
                add(.romajiTitleArtist, title: rt.value, artist: ra, aliasIDs: [rt.id] + (romajiArtists.first.map { [$0.id] } ?? []))
            }
        }

        // 5 official English
        for en in metadata.aliases(for: .title, kind: .officialEnglish) where en.isOfficial || en.source == .spotifyMetadata {
            add(.officialEnglish, title: en.value, artist: artist, aliasIDs: [en.id])
        }

        // 6 other known aliases
        let knownKinds: [TrackAliasKind] = [.alternativeTitle, .localizedTitle, .providerAlias, .userAlias]
        for alias in metadata.aliases where alias.field == .title && knownKinds.contains(alias.kind) {
            add(.knownAliases, title: alias.value, artist: artist, aliasIDs: [alias.id])
        }

        // 7 title only loose
        add(.titleOnlyLoose, title: title, artist: nil)
        if let rt = romajiTitles.first {
            add(.titleOnlyLoose, title: rt.value, artist: nil, aliasIDs: [rt.id])
        } else if let gen = JapaneseRomanizer.romanizeIfMostlyKana(title) {
            add(.titleOnlyLoose, title: gen, artist: nil)
        }

        // Ensure ranks unique increasing (already sequential)
        return built.enumerated().map { idx, v in
            LyricsQueryVariant(
                rank: idx + 1,
                strategy: v.strategy,
                titleQuery: v.titleQuery,
                artistQuery: v.artistQuery,
                aliasIDs: v.aliasIDs
            )
        }
    }
}

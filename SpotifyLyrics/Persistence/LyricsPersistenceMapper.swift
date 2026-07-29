import Foundation
import CryptoKit

public enum DatabaseSourceIdentifier {
    public static func identifier(for source: LyricsSource) -> String {
        switch source {
        case .local: return "localLRC"
        case .lrclib: return "lrclib"
        case .neteaseExperimental: return "netEaseExperimental"
        case .qqExperimental: return "qqExperimental"
        case .asrMachineGenerated: return "asrMachineGenerated"
        case .automaticAlignment: return "automaticAlignment"
        case .mock: return "mock"
        }
    }

    public static func source(for identifier: String) -> LyricsSource {
        switch identifier {
        case "localLRC", "localDatabase": return .local
        case "lrclib": return .lrclib
        case "netEaseExperimental": return .neteaseExperimental
        case "qqExperimental": return .qqExperimental
        case "asrMachineGenerated": return .asrMachineGenerated
        case "automaticAlignment": return .automaticAlignment
        default: return .local
        }
    }
}

public enum LyricsPersistenceMapper {
    public static func trackRecord(
        track: Track,
        identity: TrackIdentity,
        now: Date
    ) -> DatabaseTrackRecord {
        DatabaseTrackRecord(
            stableKey: identity.stableKey,
            spotifyID: identity.spotifyTrackID ?? track.spotifyId,
            spotifyURI: identity.spotifyURI ?? track.spotifyURL?.absoluteString,
            isrc: identity.isrc ?? track.isrc,
            title: track.title,
            artistDisplay: track.artist,
            album: track.album,
            duration: track.duration,
            artworkURL: track.artworkURL?.absoluteString,
            createdAt: now,
            updatedAt: now
        )
    }

    public static func aliasRecords(
        track: Track,
        identity: TrackIdentity,
        document: LyricsDocument,
        now: Date
    ) -> [DatabaseTrackAliasRecord] {
        let metadata = TrackMetadata.bootstrap(from: track)
        var aliases = metadata.aliases.map {
            DatabaseTrackAliasRecord(
                trackStableKey: identity.stableKey,
                field: $0.field.rawValue,
                kind: $0.kind.rawValue,
                value: $0.value,
                language: $0.language,
                script: $0.script.rawValue,
                source: $0.source.rawValue,
                confidence: $0.confidence,
                isOfficial: $0.isOfficial
            )
        }

        if let title = document.title, !title.isEmpty,
           TrackIdentity.normalizedComponent(title) != TrackIdentity.normalizedComponent(track.title) {
            aliases.append(
                DatabaseTrackAliasRecord(
                    trackStableKey: identity.stableKey,
                    field: TrackAliasField.title.rawValue,
                    kind: TrackAliasKind.providerAlias.rawValue,
                    value: title,
                    language: ScriptDetector.guessLanguage(title),
                    script: ScriptDetector.detect(title).rawValue,
                    source: TrackAliasSource.provider.rawValue,
                    confidence: document.confidence,
                    isOfficial: false
                )
            )
        }
        if let artist = document.artist, !artist.isEmpty,
           TrackIdentity.normalizedComponent(artist) != TrackIdentity.normalizedComponent(track.artist) {
            aliases.append(
                DatabaseTrackAliasRecord(
                    trackStableKey: identity.stableKey,
                    field: TrackAliasField.artist.rawValue,
                    kind: TrackAliasKind.providerAlias.rawValue,
                    value: artist,
                    language: ScriptDetector.guessLanguage(artist),
                    script: ScriptDetector.detect(artist).rawValue,
                    source: TrackAliasSource.provider.rawValue,
                    confidence: document.confidence,
                    isOfficial: false
                )
            )
        }
        _ = now // Kept in the mapper signature for future alias timestamps.
        return aliases
    }

    public static func aliasRecords(
        metadata: TrackMetadata,
        now: Date
    ) -> [DatabaseTrackAliasRecord] {
        _ = now
        return metadata.aliases.map {
            DatabaseTrackAliasRecord(
                trackStableKey: metadata.identity.stableKey,
                field: $0.field.rawValue,
                kind: $0.kind.rawValue,
                value: $0.value,
                language: $0.language,
                script: $0.script.rawValue,
                source: $0.source.rawValue,
                confidence: $0.confidence,
                isOfficial: $0.isOfficial
            )
        }
    }

    public static func versionRecord(
        document: LyricsDocument,
        identity: TrackIdentity,
        versionID: UUID,
        now: Date
    ) -> DatabaseLyricsVersionRecord {
        let source = DatabaseSourceIdentifier.identifier(for: document.source)
        let providerSourceID = document.providerSourceID?.isEmpty == false
            ? document.providerSourceID!
            : source
        return DatabaseLyricsVersionRecord(
            id: versionID,
            trackStableKey: identity.stableKey,
            source: source,
            providerSourceID: providerSourceID,
            language: language(for: document),
            isSynced: document.isSynchronized,
            rawText: document.lines.map(\.originalText).joined(separator: "\n"),
            contentHash: contentHash(document: document, source: source, providerSourceID: providerSourceID),
            createdAt: now,
            updatedAt: now,
            isMachineGenerated: document.source == .asrMachineGenerated || document.source == .automaticAlignment,
            isManuallyEdited: false,
            isLocked: false,
            confidence: document.confidence
        )
    }

    public static func lineRecords(
        document: LyricsDocument,
        versionID: UUID
    ) -> [DatabaseLyricLineRecord] {
        document.lines.enumerated().map { index, line in
            let start: TimeInterval? = document.isSynchronized ? line.timestamp : nil
            let end: TimeInterval?
            if document.isSynchronized, index + 1 < document.lines.count {
                let next = document.lines[index + 1].timestamp
                end = next > line.timestamp ? next : nil
            } else {
                end = nil
            }
            return DatabaseLyricLineRecord(
                lyricsVersionID: versionID,
                lineIndex: index,
                startTime: start,
                endTime: end,
                originalText: line.originalText,
                kanaText: line.kanaText,
                romajiText: line.romajiText,
                translationText: line.translationText
            )
        }
    }

    public static func document(
        identity: TrackIdentity,
        track: DatabaseTrackRecord,
        version: DatabaseLyricsVersionRecord,
        lines: [DatabaseLyricLineRecord]
    ) -> LyricsDocument {
        let lyricLines = lines.sorted { $0.lineIndex < $1.lineIndex }.map { line in
            LyricLine(
                timestamp: line.startTime ?? 0,
                originalText: line.originalText,
                translationText: line.translationText,
                romajiText: line.romajiText,
                kanaText: line.kanaText
            )
        }
        return LyricsDocument(
            identity: identity,
            title: track.title,
            artist: track.artistDisplay,
            album: track.album,
            duration: track.duration > 0 ? track.duration : nil,
            lines: lyricLines,
            isSynchronized: version.isSynced,
            source: DatabaseSourceIdentifier.source(for: version.source),
            confidence: version.confidence,
            providerSourceID: version.providerSourceID
        )
    }

    private static func language(for document: LyricsDocument) -> String {
        let text = document.lines.first?.originalText ?? document.title ?? ""
        return ScriptDetector.guessLanguage(text) ?? "und"
    }

    private struct HashLine: Encodable {
        let index: Int
        let start: TimeInterval?
        let original: String
        let kana: String?
        let romaji: String?
        let translation: String?
    }

    private struct HashPayload: Encodable {
        let source: String
        let providerSourceID: String
        let isSynced: Bool
        let lines: [HashLine]
    }

    private static func contentHash(
        document: LyricsDocument,
        source: String,
        providerSourceID: String
    ) -> String {
        let payload = HashPayload(
            source: source,
            providerSourceID: providerSourceID,
            isSynced: document.isSynchronized,
            lines: document.lines.enumerated().map { index, line in
                HashLine(
                    index: index,
                    start: document.isSynchronized ? line.timestamp : nil,
                    original: line.originalText,
                    kana: line.kanaText,
                    romaji: line.romajiText,
                    translation: line.translationText
                )
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(payload)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

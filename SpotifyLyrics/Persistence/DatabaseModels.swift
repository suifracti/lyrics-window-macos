import Foundation

/// Storage-shaped records. These types intentionally do not leak SQLite
/// handles or SQL details into the playback and provider layers.
public struct DatabaseTrackRecord: Equatable, Sendable {
    public let stableKey: String
    public let spotifyID: String?
    public let spotifyURI: String?
    public let isrc: String?
    public let title: String
    public let artistDisplay: String
    public let album: String
    public let duration: TimeInterval
    public let artworkURL: String?
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        stableKey: String,
        spotifyID: String?,
        spotifyURI: String?,
        isrc: String?,
        title: String,
        artistDisplay: String,
        album: String,
        duration: TimeInterval,
        artworkURL: String?,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.stableKey = stableKey
        self.spotifyID = spotifyID
        self.spotifyURI = spotifyURI
        self.isrc = isrc
        self.title = title
        self.artistDisplay = artistDisplay
        self.album = album
        self.duration = duration
        self.artworkURL = artworkURL
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct DatabaseTrackAliasRecord: Equatable, Sendable {
    public let trackStableKey: String
    public let field: String
    public let kind: String
    public let value: String
    public let language: String?
    public let script: String
    public let source: String
    public let confidence: Double
    public let isOfficial: Bool

    public init(
        trackStableKey: String,
        field: String,
        kind: String,
        value: String,
        language: String?,
        script: String,
        source: String,
        confidence: Double,
        isOfficial: Bool
    ) {
        self.trackStableKey = trackStableKey
        self.field = field
        self.kind = kind
        self.value = value
        self.language = language
        self.script = script
        self.source = source
        self.confidence = confidence
        self.isOfficial = isOfficial
    }
}

public struct DatabaseLyricsVersionRecord: Equatable, Sendable {
    public let id: UUID
    public let trackStableKey: String
    public let source: String
    public let providerSourceID: String
    public let language: String
    public let isSynced: Bool
    public let rawText: String
    public let contentHash: String
    public let createdAt: Date
    public let updatedAt: Date
    public let isMachineGenerated: Bool
    public let isManuallyEdited: Bool
    public let isLocked: Bool
    public let confidence: Double

    public init(
        id: UUID,
        trackStableKey: String,
        source: String,
        providerSourceID: String,
        language: String,
        isSynced: Bool,
        rawText: String,
        contentHash: String,
        createdAt: Date,
        updatedAt: Date,
        isMachineGenerated: Bool,
        isManuallyEdited: Bool,
        isLocked: Bool,
        confidence: Double
    ) {
        self.id = id
        self.trackStableKey = trackStableKey
        self.source = source
        self.providerSourceID = providerSourceID
        self.language = language
        self.isSynced = isSynced
        self.rawText = rawText
        self.contentHash = contentHash
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isMachineGenerated = isMachineGenerated
        self.isManuallyEdited = isManuallyEdited
        self.isLocked = isLocked
        self.confidence = confidence
    }
}

public struct DatabaseLyricLineRecord: Equatable, Sendable {
    public let lyricsVersionID: UUID
    public let lineIndex: Int
    public let startTime: TimeInterval?
    public let endTime: TimeInterval?
    public let originalText: String
    public let kanaText: String?
    public let romajiText: String?
    public let translationText: String?

    public init(
        lyricsVersionID: UUID,
        lineIndex: Int,
        startTime: TimeInterval?,
        endTime: TimeInterval?,
        originalText: String,
        kanaText: String?,
        romajiText: String?,
        translationText: String?
    ) {
        self.lyricsVersionID = lyricsVersionID
        self.lineIndex = lineIndex
        self.startTime = startTime
        self.endTime = endTime
        self.originalText = originalText
        self.kanaText = kanaText
        self.romajiText = romajiText
        self.translationText = translationText
    }
}

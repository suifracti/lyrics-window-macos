import Foundation

/// Metadata measured from the user-selected source file. The URL is kept by
/// the alignment task only; this value contains no audio bytes and is never
/// serialized into alignment provenance.
public struct AudioInputMetadata: Equatable, Sendable {
    public let duration: TimeInterval
    public let sampleRate: Double
    public let channels: Int
    public let fileExtension: String
    public let sha256: String
    public let fileSize: Int64
    public let embeddedTitle: String?
    public let embeddedArtist: String?

    public init(
        duration: TimeInterval,
        sampleRate: Double,
        channels: Int,
        fileExtension: String,
        sha256: String,
        fileSize: Int64,
        embeddedTitle: String? = nil,
        embeddedArtist: String? = nil
    ) {
        self.duration = duration
        self.sampleRate = sampleRate
        self.channels = channels
        self.fileExtension = fileExtension
        self.sha256 = sha256
        self.fileSize = fileSize
        self.embeddedTitle = embeddedTitle
        self.embeddedArtist = embeddedArtist
    }

    public var missingEmbeddedTitleOrArtist: Bool {
        embeddedTitle == nil || embeddedArtist == nil
    }

    public func hasHardMetadataMismatch(title: String, artist: String) -> Bool {
        if let embeddedTitle, !normalized(embeddedTitle).isEmpty,
           !normalized(title).isEmpty,
           normalized(embeddedTitle) != normalized(title) {
            return true
        }
        if let embeddedArtist, !normalized(embeddedArtist).isEmpty,
           !normalized(artist).isEmpty,
           normalized(embeddedArtist) != normalized(artist) {
            return true
        }
        return false
    }

    private func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.punctuationCharacters)
            .joined()
            .split(whereSeparator: { $0.isWhitespace })
            .joined()
    }
}

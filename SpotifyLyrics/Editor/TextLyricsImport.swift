import Foundation

/// The encoding detected for a plain-text lyric import.  `plainText` is used
/// for pasted text, while the BOM cases are kept separate so the preview can
/// explain exactly what was read from disk.
public enum TextLyricsEncoding: String, Equatable, Sendable {
    case plainText
    case utf8
    case utf8BOM
    case utf16LittleEndian
    case utf16BigEndian
}

public enum TextLyricsWarningKind: String, Equatable, Sendable {
    case sectionMarker
    case timestampLabel
    case advertisement
    case credits
}

public struct TextLyricsImportWarning: Equatable, Sendable {
    public let kind: TextLyricsWarningKind
    public let lineIndex: Int
    public let text: String

    public init(kind: TextLyricsWarningKind, lineIndex: Int, text: String) {
        self.kind = kind
        self.lineIndex = lineIndex
        self.text = text
    }
}

public enum TextLyricsImportError: Error, Equatable, Sendable, LocalizedError {
    case unsupportedEncoding
    case empty

    public var errorDescription: String? {
        switch self {
        case .unsupportedEncoding:
            return "无法识别 TXT 文件编码"
        case .empty:
            return "歌词文本为空，未创建歌词版本"
        }
    }
}

public struct TextLyricsImportResult: Equatable, Sendable {
    public let encoding: TextLyricsEncoding
    public let lines: [String]
    public let warnings: [TextLyricsImportWarning]

    public init(
        encoding: TextLyricsEncoding,
        lines: [String],
        warnings: [TextLyricsImportWarning]
    ) {
        self.encoding = encoding
        self.lines = lines
        self.warnings = warnings
    }

    public var normalizedText: String {
        lines.joined(separator: "\n")
    }

    public func document(
        identity: TrackIdentity,
        track: Track,
        source: LyricsSource = .manualImport
    ) -> LyricsDocument {
        LyricsDocument(
            identity: identity,
            title: track.title,
            artist: track.artist,
            album: track.album,
            duration: track.duration,
            lines: lines.map { line in
                LyricLine(timestamp: 0, originalText: line)
            },
            isSynchronized: false,
            source: source,
            confidence: 1,
            providerSourceID: nil,
            spotifyTrackID: identity.spotifyTrackID,
            isrc: identity.isrc
        )
    }
}

/// Deterministic plain-text import shared by file and clipboard flows.
///
/// This parser deliberately does not attempt to remove web-site material or
/// rewrite lyric text.  It only normalizes line endings, trims line edges and
/// collapses excessive blank rows; suspicious rows are surfaced as warnings
/// for the editor preview to let the user decide.
public enum TextLyricsImportParser {
    public static func parse(_ data: Data) throws -> TextLyricsImportResult {
        let decoded: (String, TextLyricsEncoding)

        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            guard let text = String(data: data.dropFirst(3), encoding: .utf8) else {
                throw TextLyricsImportError.unsupportedEncoding
            }
            decoded = (text, .utf8BOM)
        } else if data.starts(with: [0xFF, 0xFE]) {
            guard let text = String(data: data.dropFirst(2), encoding: .utf16LittleEndian) else {
                throw TextLyricsImportError.unsupportedEncoding
            }
            decoded = (text, .utf16LittleEndian)
        } else if data.starts(with: [0xFE, 0xFF]) {
            guard let text = String(data: data.dropFirst(2), encoding: .utf16BigEndian) else {
                throw TextLyricsImportError.unsupportedEncoding
            }
            decoded = (text, .utf16BigEndian)
        } else if let text = String(data: data, encoding: .utf8) {
            decoded = (text, .utf8)
        } else if let text = String(data: data, encoding: .utf16LittleEndian) {
            decoded = (text, .utf16LittleEndian)
        } else if let text = String(data: data, encoding: .utf16BigEndian) {
            decoded = (text, .utf16BigEndian)
        } else {
            throw TextLyricsImportError.unsupportedEncoding
        }

        return try makeResult(text: decoded.0, encoding: decoded.1)
    }

    public static func parse(_ text: String) throws -> TextLyricsImportResult {
        try makeResult(text: text, encoding: .plainText)
    }

    private static func makeResult(
        text: String,
        encoding: TextLyricsEncoding
    ) throws -> TextLyricsImportResult {
        // Some clipboard managers preserve a BOM even though the data no
        // longer carries an encoding marker. Treat it like the file parser
        // does instead of exposing an invisible character in the first row.
        let textWithoutBOM = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
        let normalized = textWithoutBOM
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var lines = normalized
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        while lines.first?.isEmpty == true { lines.removeFirst() }
        while lines.last?.isEmpty == true { lines.removeLast() }

        var cleaned: [String] = []
        cleaned.reserveCapacity(lines.count)
        var previousWasBlank = false
        for line in lines {
            let isBlank = line.isEmpty
            if isBlank && previousWasBlank { continue }
            cleaned.append(line)
            previousWasBlank = isBlank
        }

        guard cleaned.contains(where: { !$0.isEmpty }) else {
            throw TextLyricsImportError.empty
        }

        let warnings = cleaned.enumerated().compactMap { index, line in
            warning(for: line, lineIndex: index)
        }
        return TextLyricsImportResult(encoding: encoding, lines: cleaned, warnings: warnings)
    }

    private static func warning(
        for line: String,
        lineIndex: Int
    ) -> TextLyricsImportWarning? {
        let lowercased = line.lowercased()

        let sectionPrefixes = [
            "[verse", "[chorus", "[bridge", "[pre-chorus", "[pre chorus",
            "[intro", "[outro", "[hook", "[refrain"
        ]
        if sectionPrefixes.contains(where: { lowercased.hasPrefix($0) }) && lowercased.hasSuffix("]") {
            return TextLyricsImportWarning(kind: .sectionMarker, lineIndex: lineIndex, text: line)
        }

        if line.range(of: #"^\s*\[\d{1,3}:\d{2}(?:[\.:]\d{1,3})?\]"#, options: .regularExpression) != nil {
            return TextLyricsImportWarning(kind: .timestampLabel, lineIndex: lineIndex, text: line)
        }

        let advertisementWords = [
            "歌词网站广告", "歌词下载", "music.163.com", "酷狗", "网易云",
            "qq音乐", "http://", "https://", "www."
        ]
        if advertisementWords.contains(where: { lowercased.contains($0.lowercased()) }) {
            return TextLyricsImportWarning(kind: .advertisement, lineIndex: lineIndex, text: line)
        }

        if line.range(of: #"^\s*(作词|作曲|编曲|制作人|演唱|词|曲|lyrics\s+by|written\s+by|produced\s+by)\s*[:：]"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return TextLyricsImportWarning(kind: .credits, lineIndex: lineIndex, text: line)
        }

        return nil
    }
}

import Foundation

public enum LRCParser {
    private static let timestampExpression = try! NSRegularExpression(
        pattern: #"\[(\d{1,3}):(\d{2})(?:[\.:](\d{1,3}))?\]"#
    )

    public static func parse(
        _ content: String,
        identity: TrackIdentity,
        source: LyricsSource
    ) -> LyricsDocument? {
        var title: String?
        var artist: String?
        var album: String?
        var duration: TimeInterval?
        var parsedLines: [LyricLine] = []

        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if let tag = metadataTag(in: line) {
                switch tag.key {
                case "ti": title = tag.value
                case "ar": artist = tag.value
                case "al": album = tag.value
                case "length": duration = parseLength(tag.value)
                default: break
                }
            }

            let fullRange = NSRange(line.startIndex..<line.endIndex, in: line)
            let matches = timestampExpression.matches(in: line, range: fullRange)
            guard !matches.isEmpty else { continue }

            let text = timestampExpression.stringByReplacingMatches(
                in: line,
                range: fullRange,
                withTemplate: ""
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            for match in matches {
                guard let timestamp = timestamp(from: match, in: line) else { continue }
                parsedLines.append(
                    LyricLine(timestamp: timestamp, originalText: text)
                )
            }
        }

        guard !parsedLines.isEmpty else { return nil }
        parsedLines.sort { lhs, rhs in
            if lhs.timestamp == rhs.timestamp { return lhs.id.uuidString < rhs.id.uuidString }
            return lhs.timestamp < rhs.timestamp
        }

        return LyricsDocument(
            identity: identity,
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            lines: parsedLines,
            source: source,
            confidence: 1
        )
    }

    private static func metadataTag(in line: String) -> (key: String, value: String)? {
        guard line.first == "[", let closing = line.firstIndex(of: ":"), let end = line.firstIndex(of: "]"), closing < end else {
            return nil
        }
        let keyStart = line.index(after: line.startIndex)
        let key = String(line[keyStart..<closing]).lowercased()
        let valueStart = line.index(after: closing)
        let value = String(line[valueStart..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !value.isEmpty else { return nil }
        return (key, value)
    }

    private static func timestamp(from match: NSTextCheckingResult, in line: String) -> TimeInterval? {
        guard match.numberOfRanges >= 4,
              let minuteRange = Range(match.range(at: 1), in: line),
              let secondRange = Range(match.range(at: 2), in: line),
              let minute = Double(line[minuteRange]),
              let seconds = Double(line[secondRange]) else {
            return nil
        }

        var fraction = 0.0
        if let fractionRange = Range(match.range(at: 3), in: line) {
            let fractionText = String(line[fractionRange])
            let denominator = pow(10.0, Double(fractionText.count))
            fraction = (Double(fractionText) ?? 0) / denominator
        }
        return minute * 60 + seconds + fraction
    }

    private static func parseLength(_ value: String) -> TimeInterval? {
        let pieces = value.split(separator: ":")
        guard pieces.count == 2,
              let minutes = Double(pieces[0]),
              let seconds = Double(pieces[1]) else {
            return nil
        }
        return minutes * 60 + seconds
    }
}

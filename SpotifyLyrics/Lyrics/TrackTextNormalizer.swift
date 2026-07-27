import Foundation

public enum TrackTextNormalizer {
    public struct FeaturedSplit: Equatable, Sendable {
        public let primary: String
        public let featured: [String]
    }

    public static func normalize(_ raw: String) -> String {
        var s = raw
        // Unicode compatibility + canonical composition
        s = s.decomposedStringWithCompatibilityMapping
        s = s.precomposedStringWithCanonicalMapping

        // Fullwidth ASCII / spaces via applyingTransform when available
        if let folded = s.applyingTransform(.fullwidthToHalfwidth, reverse: false) {
            s = folded
        }

        s = s.lowercased()

        let replacements: [(String, String)] = [
            ("・", " "),
            ("·", " "),
            ("•", " "),
            ("〜", "~"),
            ("～", "~"),
            ("─", "-"),
            ("—", "-"),
            ("–", "-"),
            ("‐", "-"),
            ("\u{3000}", " "),
            ("\t", " "),
            ("\n", " "),
            ("\r", " "),
            ("“", "\""),
            ("”", "\""),
            ("‘", "'"),
            ("’", "'"),
            ("「", " "),
            ("」", " "),
            ("『", " "),
            ("』", " "),
            ("（", "("),
            ("）", ")"),
            ("【", " "),
            ("】", " "),
            ("［", "["),
            ("］", "]")
        ]
        for (a, b) in replacements {
            s = s.replacingOccurrences(of: a, with: b)
        }

        // Collapse punctuation used as separators into space (keep alphanumeric JP)
        let scalars = s.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) { return Character(scalar) }
            if (0x3040...0x30FF).contains(scalar.value) || (0x4E00...0x9FFF).contains(scalar.value) {
                return Character(scalar)
            }
            if scalar == "~" || scalar == "-" || scalar == "'" { return Character(scalar) }
            return " "
        }
        s = String(scalars)

        while s.contains("  ") {
            s = s.replacingOccurrences(of: "  ", with: " ")
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func splitFeaturedArtists(_ artist: String) -> FeaturedSplit {
        let patterns = [
            #"\s+feat\.?\s+"#,
            #"\s+ft\.?\s+"#,
            #"\s+featuring\s+"#,
            #"\s+with\s+"#,
            #"\s+x\s+"#
        ]
        var primary = artist
        var featured: [String] = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(primary.startIndex..<primary.endIndex, in: primary)
            if let match = regex.firstMatch(in: primary, options: [], range: range),
               let r = Range(match.range, in: primary) {
                let head = String(primary[..<r.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let tail = String(primary[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !head.isEmpty {
                    primary = head
                    if !tail.isEmpty {
                        featured.append(contentsOf: tail.split(separator: ",").map {
                            $0.trimmingCharacters(in: .whitespacesAndNewlines)
                        }.filter { !$0.isEmpty })
                    }
                    break
                }
            }
        }
        return FeaturedSplit(primary: primary, featured: featured)
    }

    public static func extractVersionTags(fromTitle title: String) -> [VersionTag] {
        let n = normalize(title)
        var tags: [VersionTag] = []
        let rules: [(String, VersionTag)] = [
            ("live", .live),
            ("remix", .remix),
            ("acoustic", .acoustic),
            ("instrumental", .instrumental),
            ("off vocal", .instrumental),
            ("karaoke", .karaoke),
            ("radio edit", .radioEdit),
            ("demo", .demo),
            ("cover", .cover),
            ("re-record", .reRecord),
            ("rerecord", .reRecord)
        ]
        for (key, tag) in rules where n.contains(key) {
            if !tags.contains(tag) { tags.append(tag) }
        }
        // Japanese markers
        if title.contains("ライブ") || title.contains("生") && n.contains("live") {
            if !tags.contains(.live) { tags.append(.live) }
        }
        if title.contains("リミックス"), !tags.contains(.remix) { tags.append(.remix) }
        if title.contains("インスト"), !tags.contains(.instrumental) { tags.append(.instrumental) }
        return tags
    }

    public static func stripVersionMarkers(fromTitle title: String) -> String {
        var s = title
        let patterns = [
            #"\s*[\(\[\{（【].*?(live|remix|acoustic|instrumental|karaoke|radio\s*edit|demo|cover).*?[\)\]\}）】]\s*"#,
            #"\s*-\s*(live|remix|acoustic|instrumental).*$"#
        ]
        for p in patterns {
            if let regex = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]) {
                let range = NSRange(s.startIndex..<s.endIndex, in: s)
                s = regex.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: " ")
            }
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

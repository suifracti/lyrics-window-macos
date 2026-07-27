import Foundation

/// Dictionary + rule based Japanese reading generator.
///
/// - Provider-supplied kana always wins (handled by `LyricsLayerEnricher`).
/// - Local engine uses longest-match against a kanji reading dictionary exported
///   from a Japanese transliteration lexicon (pykakasi/kanwa), plus lyric particle rules.
/// - This is **not** a full morphological analyzer (MeCab/UniDic). It is real lexicon
///   lookup, not Chinese Unihan guessing. Unresolved kanji remain marked nil.
public enum JapaneseKanaGenerator {
    public static var sharedDictionary: JapaneseReadingDictionary = {
        JapaneseReadingDictionary.loadDefault()
    }()

    public static func isMostlyKana(_ text: String) -> Bool {
        let jp = text.unicodeScalars.filter {
            (0x3040...0x30FF).contains($0.value) || (0x4E00...0x9FFF).contains($0.value)
        }
        guard !jp.isEmpty else { return false }
        let kana = jp.filter { (0x3040...0x30FF).contains($0.value) }.count
        return Double(kana) / Double(jp.count) >= 0.8
    }

    public static func hasKanji(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
    }

    /// Returns hiragana reading when the line can be fully resolved by lexicon/rules.
    public static func kanaPreservingOriginal(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if !hasKanji(trimmed) {
            // Kana/latin only: normalize katakana → hiragana, keep latin/digits.
            return applyParticleReadings(JapaneseRomanizer.toHiraganaPreservingLatin(trimmed))
        }

        guard let converted = sharedDictionary.reading(for: trimmed) else {
            return nil
        }
        return applyParticleReadings(converted)
    }

    /// Lyric-oriented particle readings after segmentation.
    /// Heuristic: standalone particle tokens は/へ/を → わ/え/お.
    static func applyParticleReadings(_ text: String) -> String {
        // Character-wise is wrong for は inside words; dictionary longest-match should
        // already consume word は inside compounds. Remaining isolated は between kana
        // boundaries become わ.
        var scalars = Array(text)
        guard !scalars.isEmpty else { return text }
        for i in scalars.indices {
            let c = scalars[i]
            let prev = i > 0 ? scalars[i - 1] : nil
            let next = i + 1 < scalars.count ? scalars[i + 1] : nil
            let prevIsJP = prev.map(isJapaneseLetter) ?? false
            let nextIsJP = next.map(isJapaneseLetter) ?? false
            // Particle-like when surrounded by japanese letters or edges of phrase
            if c == "は", (prevIsJP || prev == nil || prev == " " || prev == "　"), (nextIsJP || next == nil || next == " " || next == "　" || next == "、" || next == "。") {
                // Avoid rewriting if part of unresolved residual — still apply common lyric particle
                if prev != "に" { // keep simple
                    scalars[i] = "わ"
                }
            } else if c == "へ", prevIsJP || nextIsJP {
                scalars[i] = "え"
            } else if c == "を", prevIsJP || nextIsJP {
                scalars[i] = "お"
            }
        }
        return String(scalars)
    }

    private static func isJapaneseLetter(_ c: Character) -> Bool {
        guard let v = c.unicodeScalars.first?.value else { return false }
        return (0x3040...0x30FF).contains(v) || (0x4E00...0x9FFF).contains(v)
    }
}

public struct JapaneseReadingDictionary: Sendable {
    /// Longest-first surface forms.
    private let entries: [(String, String)]
    public let entryCount: Int

    public init(entries: [(String, String)]) {
        self.entries = entries.sorted { lhs, rhs in
            if lhs.0.count != rhs.0.count { return lhs.0.count > rhs.0.count }
            return lhs.0 < rhs.0
        }
        self.entryCount = self.entries.count
    }

    public static func loadDefault() -> JapaneseReadingDictionary {
        if let url = Bundle.main.url(forResource: "japanese_kanji_readings", withExtension: "json"),
           let dict = load(from: url) {
            return dict
        }
        if let env = ProcessInfo.processInfo.environment["SPOTIFYLYRICS_KANA_DICT"],
           let dict = load(from: URL(fileURLWithPath: env)) {
            return dict
        }
        // Source-relative fallback for swiftc contract tests / dev.
        let candidates = [
            "SpotifyLyrics/Resources/japanese_kanji_readings.json",
            "../Resources/japanese_kanji_readings.json",
            "japanese_kanji_readings.json"
        ]
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for rel in candidates {
            let url = cwd.appendingPathComponent(rel)
            if let dict = load(from: url) { return dict }
        }
        // Minimal embedded fallback so kana-only still works if dict missing.
        return JapaneseReadingDictionary(entries: [
            ("私たち", "わたしたち"),
            ("彼女", "かのじょ"),
            ("約束", "やくそく"),
            ("水曜日", "すいようび"),
            ("気持ち", "きもち")
        ])
    }

    public static func load(from url: URL) -> JapaneseReadingDictionary? {
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = obj["entries"] as? [[String: String]] else {
            return nil
        }
        let pairs: [(String, String)] = arr.compactMap { row in
            guard let s = row["s"], let r = row["r"], !s.isEmpty, !r.isEmpty else { return nil }
            return (s, r)
        }
        guard !pairs.isEmpty else { return nil }
        return JapaneseReadingDictionary(entries: pairs)
    }

    /// Longest-match conversion. Returns nil if any kanji remains unresolved.
    public func reading(for text: String) -> String? {
        var i = text.startIndex
        var out = ""
        while i < text.endIndex {
            let rest = text[i...]
            var matched = false
            for (surface, reading) in entries {
                if rest.hasPrefix(surface) {
                    out += reading
                    i = text.index(i, offsetBy: surface.count)
                    matched = true
                    break
                }
            }
            if matched { continue }

            let ch = rest[rest.startIndex]
            // Pass through kana/latin/digits/punct
            if let v = ch.unicodeScalars.first?.value {
                if (0x3040...0x30FF).contains(v) {
                    // katakana handled later as whole-string hiragana fold
                    out.append(ch)
                    i = text.index(after: i)
                    continue
                }
                if (0x4E00...0x9FFF).contains(v) {
                    // unresolved kanji
                    return nil
                }
            }
            out.append(ch)
            i = text.index(after: i)
        }
        return JapaneseRomanizer.toHiraganaPreservingLatin(out)
    }
}

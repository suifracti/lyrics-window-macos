import Foundation

/// Local deterministic kana helpers.
/// - Already-kana text is preserved (or katakana→hiragana).
/// - Kanji readings are NOT invented via Chinese Unihan; returns nil for unresolved kanji-heavy lines.
public enum JapaneseKanaGenerator {
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

    /// Returns hiragana form when safe; nil when line needs dictionary/provider readings.
    public static func kanaPreservingOriginal(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if hasKanji(trimmed) && !isMostlyKana(trimmed) {
            return nil
        }
        // Convert katakana runs to hiragana; keep latin/punctuation
        return JapaneseRomanizer.toHiraganaPreservingLatin(trimmed)
    }
}

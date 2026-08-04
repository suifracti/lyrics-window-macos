#if DEBUG
import Foundation

public struct LocaleRecommendation: Equatable, Sendable {
    public let localeIdentifier: String
    public let reason: String
    public let usedFallback: Bool
}

/// Minimal ja-JP / zh-CN / en-US recommendation for S3A Speech.
public enum AlignmentLocaleRecommender: Sendable {
    public static func recommend(
        languageHint: String?,
        lyricText: String,
        override: String? = nil
    ) -> LocaleRecommendation {
        if let override, !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return LocaleRecommendation(
                localeIdentifier: override,
                reason: "debug_override",
                usedFallback: false
            )
        }
        if let languageHint {
            let n = languageHint.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if n.hasPrefix("ja") {
                return LocaleRecommendation(localeIdentifier: "ja-JP", reason: "document.language=ja", usedFallback: false)
            }
            if n.hasPrefix("zh") {
                return LocaleRecommendation(localeIdentifier: "zh-CN", reason: "document.language=zh", usedFallback: false)
            }
            if n.hasPrefix("en") {
                return LocaleRecommendation(localeIdentifier: "en-US", reason: "document.language=en", usedFallback: false)
            }
        }
        if LyricsLanguageGate.inferredLanguage(text: lyricText) == "ja" {
            return LocaleRecommendation(localeIdentifier: "ja-JP", reason: "kana_surface", usedFallback: false)
        }
        if containsLatinLetter(lyricText) && !containsCJK(lyricText) {
            return LocaleRecommendation(localeIdentifier: "en-US", reason: "latin_only_surface", usedFallback: false)
        }
        if containsCJK(lyricText) && !containsKana(lyricText) {
            // Han-only is ambiguous; prefer zh-CN over silent ja for S3A.
            return LocaleRecommendation(localeIdentifier: "zh-CN", reason: "han_only_ambiguous_as_zh", usedFallback: false)
        }
        return LocaleRecommendation(
            localeIdentifier: "ja-JP",
            reason: "fallback_default_ja_JP",
            usedFallback: true
        )
    }

    private static func containsLatinLetter(_ text: String) -> Bool {
        text.unicodeScalars.contains { CharacterSet.letters.contains($0) && $0.isASCII }
    }

    private static func containsCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x3400...0x4DBF).contains(scalar.value)
                || (0x4E00...0x9FFF).contains(scalar.value)
                || (0xF900...0xFAFF).contains(scalar.value)
        }
    }

    private static func containsKana(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x3040...0x309F).contains(scalar.value)
                || (0x30A0...0x30FF).contains(scalar.value)
        }
    }
}
#endif

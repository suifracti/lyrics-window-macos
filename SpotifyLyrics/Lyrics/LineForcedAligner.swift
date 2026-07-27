import Foundation

/// Deterministic line-level force aligner: match lyric pronunciations to timed ASR tokens.
/// Does not invent times from lyric semantics — only from timed recognition evidence + interpolation.
public enum LineForcedAligner {
    public struct TimedToken: Equatable, Sendable {
        public let surface: String
        public let norm: String
        public let start: TimeInterval
        public let end: TimeInterval

        public init(surface: String, norm: String, start: TimeInterval, end: TimeInterval) {
            self.surface = surface
            self.norm = norm
            self.start = start
            self.end = max(end, start)
        }
    }

    public static func align(
        lines: [LyricLine],
        tokens: [TimedToken],
        audioDuration: TimeInterval
    ) -> [AlignedLyricLine] {
        guard !lines.isEmpty else { return [] }

        let prepared: [(line: LyricLine, norm: String)] = lines.map { line in
            let kana = line.kanaText
                ?? JapaneseKanaGenerator.kanaPreservingOriginal(line.originalText)
                ?? line.originalText
            return (line, normalize(kana))
        }

        if tokens.isEmpty {
            return spreadLowConfidence(prepared.map(\.line), duration: audioDuration, status: .unmatched)
        }

        var tokenCursor = 0
        var results: [AlignedLyricLine] = []

        for item in prepared {
            let line = item.line
            let target = item.norm
            if target.isEmpty {
                results.append(
                    AlignedLyricLine(
                        id: line.id,
                        originalText: line.originalText,
                        kanaText: line.kanaText,
                        romajiText: line.romajiText,
                        translationText: line.translationText,
                        startTime: results.last?.endTime ?? results.last?.startTime ?? 0,
                        endTime: nil,
                        confidence: 0.05,
                        status: .unmatched
                    )
                )
                continue
            }

            // Search forward from tokenCursor for best fuzzy window.
            let window = bestWindow(
                target: target,
                tokens: tokens,
                from: tokenCursor
            )

            if let window {
                // A token belongs to at most one lyric line. Advancing past
                // the matched window prevents a repeated suffix token from
                // being reused as the next line's anchor.
                tokenCursor = max(tokenCursor, window.endTokenIndex + 1)
                let conf = window.score
                let status: AlignmentLineStatus
                if conf >= 0.62 { status = .aligned }
                else if conf >= 0.38 { status = .lowConfidence }
                else { status = .unmatched }

                let start = tokens[window.startTokenIndex].start
                let end = tokens[min(window.endTokenIndex, tokens.count - 1)].end
                results.append(
                    AlignedLyricLine(
                        id: line.id,
                        originalText: line.originalText,
                        kanaText: line.kanaText,
                        romajiText: line.romajiText,
                        translationText: line.translationText,
                        startTime: start,
                        endTime: end,
                        confidence: conf,
                        status: status == .unmatched && conf < 0.38 ? .lowConfidence : status
                    )
                )
            } else {
                results.append(
                    AlignedLyricLine(
                        id: line.id,
                        originalText: line.originalText,
                        kanaText: line.kanaText,
                        romajiText: line.romajiText,
                        translationText: line.translationText,
                        startTime: -1, // mark for interpolation
                        endTime: nil,
                        confidence: 0.1,
                        status: .unmatched
                    )
                )
            }
        }

        return enforceMonotonicAndInterpolate(results, duration: audioDuration)
    }

    // MARK: - Window search

    private struct Window {
        let startTokenIndex: Int
        let endTokenIndex: Int // inclusive
        let score: Double
    }

    private static func bestWindow(target: String, tokens: [TimedToken], from: Int) -> Window? {
        guard from < tokens.count else { return nil }
        let targetLen = max(target.count, 1)
        var best: Window?

        // Limit search horizon to keep V1 interactive.
        let startMax = min(tokens.count - 1, from + 80)
        for s in from...startMax {
            var acc = ""
            let endMax = min(tokens.count - 1, s + max(6, targetLen + 18))
            for e in s...endMax {
                acc += tokens[e].norm
                if acc.count < max(1, targetLen / 3) { continue }
                if acc.count > targetLen * 3 + 12 { break }
                let score = similarity(target, acc)
                // Prefer closer length
                let lenPenalty = abs(Double(acc.count - targetLen)) / Double(max(targetLen, 1))
                let adjusted = max(0, score - 0.08 * lenPenalty)
                if best == nil || adjusted > best!.score + 0.0001 {
                    best = Window(startTokenIndex: s, endTokenIndex: e, score: adjusted)
                }
                if adjusted > 0.92, acc.count >= targetLen { return best }
            }
        }
        // Only accept if score isn't garbage
        if let best, best.score >= 0.28 { return best }
        return best?.score ?? 0 >= 0.22 ? best : nil
    }

    /// Character-level Dice/Jaccard-ish similarity for kana/latin strings.
    private static func similarity(_ a: String, _ b: String) -> Double {
        if a.isEmpty && b.isEmpty { return 1 }
        if a.isEmpty || b.isEmpty { return 0 }
        if a == b { return 1 }
        let aChars = Array(a)
        let bChars = Array(b)
        // LCS length ratio
        let lcs = lcsLength(aChars, bChars)
        let denom = Double(max(aChars.count, bChars.count))
        let lcsScore = Double(lcs) / denom
        // bigram dice
        let dice = diceCoefficient(a, b)
        return 0.65 * lcsScore + 0.35 * dice
    }

    private static func lcsLength(_ a: [Character], _ b: [Character]) -> Int {
        let n = a.count, m = b.count
        if n == 0 || m == 0 { return 0 }
        // memory optimized
        var prev = Array(repeating: 0, count: m + 1)
        var cur = Array(repeating: 0, count: m + 1)
        for i in 1...n {
            for j in 1...m {
                if a[i - 1] == b[j - 1] {
                    cur[j] = prev[j - 1] + 1
                } else {
                    cur[j] = max(prev[j], cur[j - 1])
                }
            }
            swap(&prev, &cur)
            cur = Array(repeating: 0, count: m + 1)
        }
        return prev[m]
    }

    private static func diceCoefficient(_ a: String, _ b: String) -> Double {
        func bigrams(_ s: String) -> [String] {
            let chars = Array(s)
            guard chars.count >= 2 else { return chars.map(String.init) }
            return (0..<(chars.count - 1)).map { String(chars[$0]) + String(chars[$0 + 1]) }
        }
        let A = bigrams(a)
        let B = bigrams(b)
        if A.isEmpty && B.isEmpty { return 1 }
        if A.isEmpty || B.isEmpty { return 0 }
        var counts: [String: Int] = [:]
        for g in A { counts[g, default: 0] += 1 }
        var inter = 0
        for g in B {
            if let c = counts[g], c > 0 {
                inter += 1
                counts[g] = c - 1
            }
        }
        return (2.0 * Double(inter)) / Double(A.count + B.count)
    }

    public static func normalize(_ text: String) -> String {
        var s = JapaneseRomanizer.toHiraganaPreservingLatin(text)
        s = s.lowercased()
        // strip punctuation/spaces/symbols; keep kana and latin alnum
        let allowed = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: "ぁあぃいぅうぇえぉおかがきぎくぐけげこごさざしじすずせぜそぞただちぢっつづてでとどなにぬねのはばぱひびぴふぶぷへべぺほぼぽまみむめもゃやゅゆょよらりるれろゎわゐゑをんー"))
        s = String(s.unicodeScalars.filter { allowed.contains($0) || (0x3040...0x30FF).contains($0.value) })
        return s
    }

    private static func spreadLowConfidence(_ lines: [LyricLine], duration: TimeInterval, status: AlignmentLineStatus) -> [AlignedLyricLine] {
        let n = max(lines.count, 1)
        let step = max(duration, 1) / Double(n)
        return lines.enumerated().map { idx, line in
            let start = Double(idx) * step
            return AlignedLyricLine(
                id: line.id,
                originalText: line.originalText,
                kanaText: line.kanaText,
                romajiText: line.romajiText,
                translationText: line.translationText,
                startTime: start,
                endTime: start + step,
                confidence: 0.12,
                status: status
            )
        }
    }

    private static func enforceMonotonicAndInterpolate(
        _ input: [AlignedLyricLine],
        duration: TimeInterval
    ) -> [AlignedLyricLine] {
        var lines = input
        // Fill unmatched (-1) by linear interpolation between anchors
        var anchors: [(Int, TimeInterval)] = []
        for (i, line) in lines.enumerated() where line.startTime >= 0 {
            anchors.append((i, line.startTime))
        }
        if anchors.isEmpty {
            return spreadLowConfidence(
                lines.map {
                    LyricLine(
                        id: $0.id,
                        timestamp: 0,
                        originalText: $0.originalText,
                        translationText: $0.translationText,
                        romajiText: $0.romajiText,
                        kanaText: $0.kanaText
                    )
                },
                duration: duration,
                status: .interpolated
            )
        }

        // Interpolate each contiguous unmatched run as a group. In
        // particular, a tail run must be spread across the remaining audio;
        // assigning every line `prev + 1.2s` collapses the preview and makes
        // playback appear stuck on one lyric row.
        var runStart = 0
        while runStart < lines.count {
            guard lines[runStart].startTime < 0 else {
                runStart += 1
                continue
            }

            var runEnd = runStart
            while runEnd + 1 < lines.count, lines[runEnd + 1].startTime < 0 {
                runEnd += 1
            }

            let previous = anchors.last(where: { $0.0 < runStart })
            let next = anchors.first(where: { $0.0 > runEnd })
            let count = runEnd - runStart + 1
            let safeDuration = max(duration, 0)

            for offset in 0..<count {
                let fraction = Double(offset + 1) / Double(count + 1)
                let time: TimeInterval
                if let previous, let next {
                    time = previous.1 + (next.1 - previous.1) * fraction
                } else if let previous {
                    time = previous.1 + (safeDuration - previous.1) * fraction
                } else if let next {
                    // There is no evidence for a vocal onset before the
                    // first matched token. Never interpolate a leading lyric
                    // into the intro: that makes the UI move before the
                    // singer starts. These rows remain low-confidence and
                    // share the first evidence anchor until a user corrects
                    // them in the preview.
                    time = next.1
                } else {
                    time = safeDuration * fraction
                }

                let index = runStart + offset
                lines[index].startTime = time
                lines[index].status = .interpolated
                lines[index].confidence = min(lines[index].confidence, 0.28)
            }

            runStart = runEnd + 1
        }

        // Enforce non-decreasing starts
        for i in 1..<lines.count {
            if lines[i].startTime < lines[i - 1].startTime {
                lines[i].startTime = lines[i - 1].startTime
                if lines[i].status == .aligned {
                    lines[i].status = .lowConfidence
                }
                lines[i].confidence = min(lines[i].confidence, 0.45)
            }
        }

        // Fill end times
        for i in lines.indices {
            let end: TimeInterval
            if i + 1 < lines.count {
                end = max(lines[i].startTime, lines[i + 1].startTime)
            } else {
                end = max(lines[i].startTime, duration)
            }
            if let existing = lines[i].endTime {
                lines[i].endTime = min(max(existing, lines[i].startTime), end + 0.01)
            } else {
                lines[i].endTime = end
            }
            // clamp into audio
            lines[i].startTime = min(max(0, lines[i].startTime), max(duration, 0))
            if let e = lines[i].endTime {
                lines[i].endTime = min(max(lines[i].startTime, e), max(duration, lines[i].startTime))
            }
        }
        return lines
    }
}

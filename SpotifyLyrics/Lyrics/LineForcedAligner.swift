import Foundation

/// Deterministic line-level force aligner.
///
/// The matcher uses a global monotonic dynamic-programming path over lyric
/// lines and timed transcript segments. It may skip transcript segments (for
/// insertions, breaths and instrumental speech), and it may interpolate only
/// a missing line whose anchors are real matches on both sides. It never
/// spreads a song duration across lines.
public enum LineForcedAligner {
    /// Compatibility shape used by older tests/services while callers migrate
    /// to `TimedTranscript`. This wrapper intentionally preserves unresolved
    /// lines with a negative start rather than manufacturing a time.
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

    private struct Match: Sendable {
        let start: Int
        let end: Int
        let score: Double
        let transcriptConfidence: Double
    }

    private struct Path: Sendable {
        var score: Double
        var matches: [Match?]
        var matchedCount: Int
        var lastEnd: Int
    }

    public static func align(
        lines: [LyricLine],
        transcript: TimedTranscript,
        audioDuration: TimeInterval,
        parameters: AlignmentParameters = AlignmentParameters()
    ) -> LineAlignmentResult {
        guard !lines.isEmpty else {
            return LineAlignmentResult(lines: [])
        }

        let duration = max(0, audioDuration)
        let normalizedSegments = transcript.segments.map { normalize($0.text) }
        let preparedTargets = lines.map { line -> String in
            if let kana = line.kanaText, !kana.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return normalize(kana)
            }
            if let romaji = line.romajiText, !romaji.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return normalize(romaji)
            }
            return normalize(line.originalText)
        }

        guard !transcript.segments.isEmpty, transcript.isValid else {
            let unresolved = lines.indices.filter { !isBlank(lines[$0].originalText) }
            let outputs = makeUnresolvedLines(lines: lines)
            return LineAlignmentResult(
                lines: outputs,
                skippedTranscriptSegmentIndices: transcript.segments.indices.map { $0 },
                unresolvedLineIndices: unresolved
            )
        }

        let candidates = preparedTargets.map { target in
            makeCandidates(
                target: target,
                segments: transcript.segments,
                normalizedSegments: normalizedSegments,
                parameters: parameters
            )
        }

        var states: [Int: Path] = [
            -1: Path(score: 0, matches: [], matchedCount: 0, lastEnd: -1)
        ]

        for lineIndex in lines.indices {
            var nextStates: [Int: Path] = [:]
            let target = preparedTargets[lineIndex]
            let blank = target.isEmpty || isBlank(lines[lineIndex].originalText)

            for (_, path) in states {
                var unmatched = path
                unmatched.matches.append(nil)
                unmatched.score += blank ? 0 : -0.55
                if shouldReplace(nextStates[unmatched.lastEnd], with: unmatched) {
                    nextStates[unmatched.lastEnd] = unmatched
                }

                guard !blank else { continue }
                for candidate in candidates[lineIndex] {
                    guard candidate.start > path.lastEnd else { continue }
                    let skipped = max(0, candidate.start - path.lastEnd - 1)
                    var matched = path
                    matched.matches.append(candidate)
                    matched.score += candidate.score - (0.012 * Double(skipped))
                    matched.matchedCount += 1
                    matched.lastEnd = candidate.end
                    if shouldReplace(nextStates[matched.lastEnd], with: matched) {
                        nextStates[matched.lastEnd] = matched
                    }
                }
            }

            // Never let a pathological transcript make the state set empty.
            // The unmatched path is retained even when no direct candidate was
            // good enough to cross the direct-score gate.
            if nextStates.isEmpty {
                nextStates[-1] = Path(
                    score: -0.55 * Double(lineIndex + 1),
                    matches: Array(repeating: nil, count: lineIndex + 1),
                    matchedCount: 0,
                    lastEnd: -1
                )
            }
            states = nextStates
        }

        let best = states.values.max { lhs, rhs in comparePaths(rhs, lhs) }
            ?? Path(score: 0, matches: Array(repeating: nil, count: lines.count), matchedCount: 0, lastEnd: -1)
        let selectedMatches = best.matches + Array(repeating: nil, count: max(0, lines.count - best.matches.count))
        let direct = makeDirectLines(
            lines: lines,
            matches: selectedMatches,
            transcript: transcript,
            duration: duration
        )
        let materialized = interpolateBoundedMissingLines(
            lines: direct,
            matches: selectedMatches,
            transcript: transcript,
            duration: duration
        )
        let unresolved: [Int] = materialized.enumerated().compactMap { entry in
            let index = entry.offset
            let line = entry.element
            guard line.startTime < 0, !isBlank(line.originalText) else { return nil }
            return index
        }
        let used = Set(selectedMatches.compactMap { $0 }.flatMap { $0.start...$0.end })
        let skipped = transcript.segments.indices.filter { !used.contains($0) }
        return LineAlignmentResult(
            lines: materialized,
            skippedTranscriptSegmentIndices: skipped,
            unresolvedLineIndices: unresolved
        )
    }

    /// Compatibility wrapper for the pre-transcript API.
    @available(*, deprecated, message: "Use align(lines:transcript:audioDuration:parameters:)")
    public static func align(
        lines: [LyricLine],
        tokens: [TimedToken],
        audioDuration: TimeInterval
    ) -> [AlignedLyricLine] {
        let transcript = TimedTranscript(
            backendID: "legacy-token-wrapper",
            segments: tokens.enumerated().map {
                TimedTranscriptSegment(
                    index: $0.offset,
                    text: $0.element.norm.isEmpty ? $0.element.surface : $0.element.norm,
                    startTime: $0.element.start,
                    endTime: $0.element.end,
                    confidence: 1
                )
            },
            audioDuration: max(audioDuration, tokens.map(\.end).max() ?? 0.1)
        )
        return align(
            lines: lines,
            transcript: transcript,
            audioDuration: audioDuration,
            parameters: AlignmentParameters(recognizerID: "legacy-token-wrapper")
        ).lines
    }

    private static func shouldReplace(_ existing: Path?, with candidate: Path) -> Bool {
        guard let existing else { return true }
        return comparePaths(candidate, existing)
    }

    private static func comparePaths(_ lhs: Path, _ rhs: Path) -> Bool {
        if abs(lhs.score - rhs.score) > 0.0001 { return lhs.score > rhs.score }
        if lhs.matchedCount != rhs.matchedCount { return lhs.matchedCount > rhs.matchedCount }
        return lhs.lastEnd < rhs.lastEnd
    }

    private static func makeCandidates(
        target: String,
        segments: [TimedTranscriptSegment],
        normalizedSegments: [String],
        parameters: AlignmentParameters
    ) -> [Match] {
        guard !target.isEmpty else { return [] }
        var result: [Match] = []
        for start in segments.indices {
            var combined = ""
            let endLimit = min(segments.count - 1, start + parameters.maxWindowSegments - 1)
            for end in start...endLimit {
                combined += normalizedSegments[end]
                guard !combined.isEmpty else { continue }
                let similarity = similarity(target, combined)
                let confidence = segments[start...end].map(\.confidence).reduce(0, +)
                    / Double(end - start + 1)
                let lengthPenalty = abs(Double(combined.count - target.count))
                    / Double(max(1, target.count))
                let score = max(0, 0.78 * similarity + 0.22 * confidence - 0.06 * lengthPenalty)
                if score >= parameters.minimumDirectScore {
                    result.append(Match(
                        start: start,
                        end: end,
                        score: score,
                        transcriptConfidence: confidence
                    ))
                }
                if combined.count > target.count * 2 + 16 { break }
            }
        }
        // Retain only the strongest local window for a given start/end pair.
        // The DP still sees every occurrence, which is what distinguishes
        // repeated choruses from a greedy first-hit matcher.
        return result.sorted {
            if $0.start != $1.start { return $0.start < $1.start }
            if $0.end != $1.end { return $0.end < $1.end }
            return $0.score > $1.score
        }
    }

    private static func makeDirectLines(
        lines: [LyricLine],
        matches: [Match?],
        transcript: TimedTranscript,
        duration: TimeInterval
    ) -> [AlignedLyricLine] {
        lines.enumerated().map { index, line in
            guard index < matches.count, let match = matches[index] else {
                return unresolvedLine(line)
            }
            let start = min(max(0, transcript.segments[match.start].startTime), duration)
            let end = min(max(start, transcript.segments[match.end].endTime), duration)
            let status: AlignmentLineStatus = match.score >= 0.72 ? .aligned : .lowConfidence
            return AlignedLyricLine(
                id: line.id,
                originalText: line.originalText,
                kanaText: line.kanaText,
                romajiText: line.romajiText,
                translationText: line.translationText,
                rubyTokens: line.rubyTokens,
                startTime: start,
                endTime: end,
                confidence: match.score,
                status: status,
                evidence: AlignmentLineEvidence(
                    kind: .directSpeech,
                    segmentStartIndex: transcript.segments[match.start].index,
                    segmentEndIndex: transcript.segments[match.end].index,
                    transcriptConfidence: match.transcriptConfidence,
                    matchScore: match.score,
                    note: "直接命中带时间识别片段"
                )
            )
        }
    }

    private static func interpolateBoundedMissingLines(
        lines: [AlignedLyricLine],
        matches: [Match?],
        transcript: TimedTranscript,
        duration: TimeInterval
    ) -> [AlignedLyricLine] {
        var output = lines
        var cursor = 0
        while cursor < output.count {
            guard output[cursor].startTime < 0 else {
                cursor += 1
                continue
            }
            var end = cursor
            while end + 1 < output.count, output[end + 1].startTime < 0 { end += 1 }
            let previous = (0..<cursor).reversed().first { output[$0].startTime >= 0 }
            let next = (end + 1..<output.count).first { output[$0].startTime >= 0 }
            guard let previous, let next else {
                cursor = end + 1
                continue
            }
            let previousStart = output[previous].startTime
            let nextStart = output[next].startTime
            let count = end - cursor + 1
            for offset in 0..<count {
                let index = cursor + offset
                let fraction = Double(offset + 1) / Double(count + 1)
                let start = previousStart + (nextStart - previousStart) * fraction
                let previousEvidence = output[previous].evidence
                let nextEvidence = output[next].evidence
                let anchorStart = previousEvidence.segmentEndIndex ?? previousEvidence.segmentStartIndex
                let anchorEnd = nextEvidence.segmentStartIndex ?? nextEvidence.segmentEndIndex
                output[index].startTime = min(max(0, start), duration)
                output[index].endTime = output[index].startTime
                output[index].status = .interpolated
                output[index].confidence = min(output[index].confidence, 0.28)
                output[index].evidence = AlignmentLineEvidence(
                    kind: .boundedInterpolation,
                    segmentStartIndex: anchorStart,
                    segmentEndIndex: anchorEnd,
                    transcriptConfidence: nil,
                    matchScore: 0,
                    note: "仅在前后真实识别行之间有界插值；需人工复核"
                )
            }
            cursor = end + 1
        }
        _ = matches
        _ = transcript
        return enforceMonotonicEnds(output, duration: duration)
    }

    private static func enforceMonotonicEnds(
        _ input: [AlignedLyricLine],
        duration: TimeInterval
    ) -> [AlignedLyricLine] {
        var lines = input
        var lastStart: TimeInterval = 0
        for index in lines.indices {
            guard lines[index].startTime >= 0 else { continue }
            if lines[index].startTime < lastStart {
                lines[index].startTime = lastStart
                lines[index].status = .lowConfidence
                lines[index].confidence = min(lines[index].confidence, 0.35)
            }
            lines[index].startTime = min(max(0, lines[index].startTime), duration)
            lastStart = lines[index].startTime
        }

        for index in lines.indices {
            guard lines[index].startTime >= 0 else { continue }
            let nextIndex = (index + 1..<lines.count)
                .first(where: { lines[$0].startTime >= 0 })
            let nextStart = nextIndex.map { lines[$0].startTime } ?? duration
            let end = min(max(lines[index].startTime, lines[index].endTime ?? nextStart), duration)
            lines[index].endTime = max(lines[index].startTime, end)
        }
        return lines
    }

    private static func unresolvedLine(_ line: LyricLine) -> AlignedLyricLine {
        AlignedLyricLine(
            id: line.id,
            originalText: line.originalText,
            kanaText: line.kanaText,
            romajiText: line.romajiText,
            translationText: line.translationText,
            rubyTokens: line.rubyTokens,
            startTime: -1,
            endTime: nil,
            confidence: 0,
            status: .unmatched,
            evidence: AlignmentLineEvidence(
                kind: .noEvidence,
                matchScore: 0,
                note: "没有直接文字证据；未生成时间"
            )
        )
    }

    private static func makeUnresolvedLines(lines: [LyricLine]) -> [AlignedLyricLine] {
        lines.map(unresolvedLine)
    }

    public static func normalize(_ text: String) -> String {
        var s = JapaneseRomanizer.toHiraganaPreservingLatin(text)
        s = s.lowercased()
        let allowed = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: "ぁあぃいぅうぇえぉおかがきぎくぐけげこごさざしじすずせぜそぞただちぢっつづてでとどなにぬねのはばぱひびぴふぶぷへべぺほぼぽまみむめもゃやゅゆょよらりるれろゎわゐゑをんー"))
        s = String(s.unicodeScalars.filter {
            allowed.contains($0) || (0x3040...0x30FF).contains($0.value)
        })
        return s
    }

    private static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func similarity(_ a: String, _ b: String) -> Double {
        if a.isEmpty && b.isEmpty { return 1 }
        if a.isEmpty || b.isEmpty { return 0 }
        if a == b { return 1 }
        let aChars = Array(a)
        let bChars = Array(b)
        let lcs = lcsLength(aChars, bChars)
        let lcsScore = Double(lcs) / Double(max(aChars.count, bChars.count))
        return 0.7 * lcsScore + 0.3 * diceCoefficient(a, b)
    }

    private static func lcsLength(_ a: [Character], _ b: [Character]) -> Int {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        var previous = Array(repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            var current = Array(repeating: 0, count: b.count + 1)
            for j in 1...b.count {
                current[j] = a[i - 1] == b[j - 1]
                    ? previous[j - 1] + 1
                    : max(previous[j], current[j - 1])
            }
            previous = current
        }
        return previous[b.count]
    }

    private static func diceCoefficient(_ a: String, _ b: String) -> Double {
        func bigrams(_ value: String) -> [String] {
            let chars = Array(value)
            guard chars.count > 1 else { return chars.map(String.init) }
            return (0..<(chars.count - 1)).map { String(chars[$0]) + String(chars[$0 + 1]) }
        }
        let lhs = bigrams(a)
        let rhs = bigrams(b)
        guard !lhs.isEmpty, !rhs.isEmpty else { return lhs.isEmpty && rhs.isEmpty ? 1 : 0 }
        var counts: [String: Int] = [:]
        lhs.forEach { counts[$0, default: 0] += 1 }
        var intersection = 0
        for item in rhs where (counts[item] ?? 0) > 0 {
            intersection += 1
            counts[item, default: 0] -= 1
        }
        return 2 * Double(intersection) / Double(lhs.count + rhs.count)
    }
}

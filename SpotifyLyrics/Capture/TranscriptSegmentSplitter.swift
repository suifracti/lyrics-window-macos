#if DEBUG
import Foundation

/// Split long ASR segments into lyric-line-scale subsegments without fabricating
/// speech content. Times stay inside the observed parent segment bounds.
public enum TranscriptSegmentSplitter {
    public enum TimeProvenance: String, Sendable, Codable, Equatable {
        /// Engine-original segment boundary (unsplit).
        case observed
        /// Legacy alias for constrained intra-segment allocation.
        case interpolatedWithinObservedSegment
        /// Token/lyric alignment inside an observed parent (acceptable for candidates).
        case constrainedInterpolated
        /// Punctuation/blank-only split without strong lyric evidence (do not auto-accept).
        case weakInterpolated
        case unresolved
    }

    public struct Subsegment: Equatable, Sendable {
        public let sourceIndex: Int
        public let originalText: String
        public let matchText: String
        public let startTime: TimeInterval
        public let endTime: TimeInterval
        public let asrConfidence: Double?
        public let timeProvenance: TimeProvenance
        public let splitReason: String
        public let matchedLyricLineIndex: Int?
    }

    public struct Result: Equatable, Sendable {
        public let language: String
        public let subsegments: [Subsegment]
        public let diagnostics: [String]
    }

    /// Hybrid split: punctuation first, then monotonic lyric-line local match
    /// with character-proportional times inside the observed window.
    public static func split(
        normalized: TranscriptNormalizer.Result,
        plainLines: [LyricLine],
        language: String
    ) -> Result {
        let lyricMatch = plainLines.map {
            TranscriptNormalizer.matchView($0.originalText, language: language)
        }
        var out: [Subsegment] = []
        var diag: [String] = []

        for seg in normalized.segments {
            let match = seg.matchText
            if match.count <= 18 || plainLines.isEmpty {
                out.append(
                    Subsegment(
                        sourceIndex: seg.sourceIndex,
                        originalText: seg.originalText,
                        matchText: match,
                        startTime: seg.startTime,
                        endTime: seg.endTime,
                        asrConfidence: seg.asrConfidence,
                        timeProvenance: .observed,
                        splitReason: "keep_short_or_empty_lyrics",
                        matchedLyricLineIndex: nil
                    )
                )
                continue
            }

            let lyricPack = matchLyricSequence(
                segmentMatch: match,
                lyricMatch: lyricMatch,
                plainLines: plainLines
            )
            let punctChunks = phraseChunks(seg.originalText, language: language)

            if lyricPack.count >= 2 {
                let parts = lyricPack.map { ($0.original, $0.match, Optional($0.lineIndex)) }
                let pieces = allocateTimes(
                    parts: parts,
                    start: seg.startTime,
                    end: seg.endTime,
                    asrConfidence: seg.asrConfidence,
                    sourceIndex: seg.sourceIndex,
                    reason: "lyric_token_alignment",
                    provenance: .constrainedInterpolated
                )
                out.append(contentsOf: pieces)
                diag.append("split source=\(seg.sourceIndex) reason=lyric_token_alignment parts=\(pieces.count)")
            } else if punctChunks.count >= 2 {
                let parts = punctChunks.map { chunk -> (String, String, Int?) in
                    (chunk, TranscriptNormalizer.matchView(chunk, language: language), nil)
                }
                let pieces = allocateTimes(
                    parts: parts,
                    start: seg.startTime,
                    end: seg.endTime,
                    asrConfidence: seg.asrConfidence,
                    sourceIndex: seg.sourceIndex,
                    reason: "punctuation_whitespace",
                    provenance: .weakInterpolated
                )
                out.append(contentsOf: pieces)
                diag.append("split source=\(seg.sourceIndex) reason=punctuation_whitespace parts=\(pieces.count) weak=1")
            } else {
                let cover = greedyCover(segmentMatch: match, lyricMatch: lyricMatch)
                if cover.count >= 2 {
                    let parts = cover.map { item -> (String, String, Int?) in
                        (plainLines[item.line].originalText, lyricMatch[item.line], item.line)
                    }
                    let pieces = allocateTimes(
                        parts: parts,
                        start: seg.startTime,
                        end: seg.endTime,
                        asrConfidence: seg.asrConfidence,
                        sourceIndex: seg.sourceIndex,
                        reason: "hybrid_greedy_cover",
                        provenance: .constrainedInterpolated
                    )
                    out.append(contentsOf: pieces)
                    diag.append("split source=\(seg.sourceIndex) reason=hybrid_greedy_cover parts=\(pieces.count)")
                } else {
                    out.append(
                        Subsegment(
                            sourceIndex: seg.sourceIndex,
                            originalText: seg.originalText,
                            matchText: match,
                            startTime: seg.startTime,
                            endTime: seg.endTime,
                            asrConfidence: seg.asrConfidence,
                            timeProvenance: .observed,
                            splitReason: "no_split_single_cover",
                            matchedLyricLineIndex: cover.first?.line
                        )
                    )
                }
            }
        }
        return Result(language: language, subsegments: out, diagnostics: diag)
    }

    /// Missing ASR confidence is encoded as -1 (not a fabricated 1.0).
    public static func asTimedTranscript(
        split: Result,
        engineID: String,
        audioDuration: TimeInterval
    ) -> TimedTranscript {
        let segments = split.subsegments.enumerated().map { index, sub in
            TimedTranscriptSegment(
                index: index,
                text: sub.originalText,
                startTime: sub.startTime,
                endTime: max(sub.startTime, sub.endTime),
                confidence: sub.asrConfidence ?? -1
            )
        }
        let duration = max(audioDuration, segments.map(\.endTime).max() ?? audioDuration)
        return TimedTranscript(backendID: engineID, segments: segments, audioDuration: duration)
    }

    // MARK: - internals

    private struct LyricHit {
        let original: String
        let match: String
        let lineIndex: Int
    }

    private static func phraseChunks(_ text: String, language: String) -> [String] {
        let separators: CharacterSet
        switch language {
        case "en":
            separators = CharacterSet(charactersIn: ".!?;")
        case "zh":
            separators = CharacterSet(charactersIn: "。！？；，")
        default:
            separators = CharacterSet(charactersIn: "。！？、…　 \t")
        }
        var parts: [String] = []
        var current = ""
        for ch in text {
            if String(ch).rangeOfCharacter(from: separators) != nil {
                let t = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { parts.append(t) }
                current = ""
            } else {
                current.append(ch)
            }
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { parts.append(tail) }
        if parts.count >= 2 { return parts }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? [] : [t]
    }

    private static func matchLyricSequence(
        segmentMatch: String,
        lyricMatch: [String],
        plainLines: [LyricLine]
    ) -> [LyricHit] {
        guard !segmentMatch.isEmpty else { return [] }
        var searchFrom = segmentMatch.startIndex
        var hits: [LyricHit] = []
        var lastLine = -1
        let maxLines = min(lyricMatch.count, 120)

        var startLine = 0
        if let seed = bestContainedLine(segmentMatch: segmentMatch, lyricMatch: lyricMatch, limit: maxLines) {
            startLine = max(0, seed - 1)
        }

        for line in startLine..<maxLines {
            let lm = lyricMatch[line]
            guard lm.count >= 2, line > lastLine else { continue }
            if let range = segmentMatch.range(of: lm, range: searchFrom..<segmentMatch.endIndex) {
                hits.append(LyricHit(original: plainLines[line].originalText, match: lm, lineIndex: line))
                searchFrom = range.upperBound
                lastLine = line
            } else if lm.count >= 4 {
                let remain = String(segmentMatch[searchFrom...])
                let prefLen = min(6, lm.count)
                let pref = String(lm.prefix(prefLen))
                if let r = remain.range(of: pref), roughContainment(lm, in: remain) >= 0.72 {
                    hits.append(LyricHit(original: plainLines[line].originalText, match: lm, lineIndex: line))
                    // Advance searchFrom by prefix match in full string
                    if let full = segmentMatch.range(of: pref, range: searchFrom..<segmentMatch.endIndex) {
                        searchFrom = full.upperBound
                    }
                    lastLine = line
                    _ = r
                }
            }
            if hits.count >= 14 { break }
            let consumed = segmentMatch.distance(from: segmentMatch.startIndex, to: searchFrom)
            if consumed >= (segmentMatch.count * 9) / 10 { break }
        }
        return hits
    }

    private static func bestContainedLine(segmentMatch: String, lyricMatch: [String], limit: Int) -> Int? {
        var best: (Int, Int)?
        for i in 0..<min(limit, lyricMatch.count) {
            let lm = lyricMatch[i]
            guard lm.count >= 4, segmentMatch.contains(lm) else { continue }
            if best == nil || lm.count > best!.1 { best = (i, lm.count) }
        }
        return best?.0
    }

    private static func greedyCover(
        segmentMatch: String,
        lyricMatch: [String]
    ) -> [(line: Int, score: Double)] {
        var remaining = segmentMatch
        var used = Set<Int>()
        var hits: [(Int, Double)] = []
        while !remaining.isEmpty {
            var best: (idx: Int, len: Int, end: String.Index)?
            for (i, lm) in lyricMatch.enumerated() where !used.contains(i) {
                guard lm.count >= 3, let r = remaining.range(of: lm) else { continue }
                if best == nil || lm.count > best!.len {
                    best = (i, lm.count, r.upperBound)
                }
            }
            guard let b = best else { break }
            used.insert(b.idx)
            hits.append((b.idx, Double(b.len) / Double(max(1, segmentMatch.count))))
            remaining = String(remaining[b.end...])
            if hits.count >= 10 { break }
        }
        return hits.sorted { $0.0 < $1.0 }.map { (line: $0.0, score: $0.1) }
    }

    private static func allocateTimes(
        parts: [(original: String, match: String, line: Int?)],
        start: TimeInterval,
        end: TimeInterval,
        asrConfidence: Double?,
        sourceIndex: Int,
        reason: String,
        provenance: TimeProvenance
    ) -> [Subsegment] {
        // Prefer match-token weights; never invent times outside [start,end].
        let weights = parts.map { max(1, $0.match.isEmpty ? $0.original.count : $0.match.count) }
        let total = max(1, weights.reduce(0, +))
        var cursor = start
        let span = max(0.02, end - start)
        var result: [Subsegment] = []
        for (i, part) in parts.enumerated() {
            let frac = Double(weights[i]) / Double(total)
            let next = (i == parts.count - 1) ? end : (cursor + span * frac)
            let prov: TimeProvenance = parts.count == 1 ? .observed : provenance
            // Guard: no multi-line collapse onto nearly identical times.
            let endT = max(cursor + 0.05, next)
            result.append(
                Subsegment(
                    sourceIndex: sourceIndex,
                    originalText: part.original,
                    matchText: part.match,
                    startTime: cursor,
                    endTime: min(end, endT),
                    asrConfidence: asrConfidence,
                    timeProvenance: prov,
                    splitReason: reason,
                    matchedLyricLineIndex: part.line
                )
            )
            cursor = min(end, endT)
        }
        return result
    }

    private static func roughContainment(_ needle: String, in hay: String) -> Double {
        guard !needle.isEmpty, !hay.isEmpty else { return 0 }
        let n = Array(needle)
        let h = Array(hay)
        var hit = 0
        var j = 0
        for ch in n {
            while j < h.count, h[j] != ch { j += 1 }
            if j < h.count, h[j] == ch {
                hit += 1
                j += 1
            }
        }
        return Double(hit) / Double(n.count)
    }
}
#endif

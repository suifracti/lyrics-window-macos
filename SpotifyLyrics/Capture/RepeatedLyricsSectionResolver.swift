import Foundation

/// Engine-agnostic repeated-lyric occurrence modeling and capture-window constraints.
/// Prefer unresolved over guessing first/second chorus when evidence is weak.
public enum RepeatedLyricsSectionResolver {
    public enum Decision: String, Sendable, Codable, Equatable {
        case accepted
        case unresolved
        case rejected
    }

    public struct RepeatedGroup: Equatable, Sendable, Codable {
        public let groupID: String
        public let matchKey: String
        public let lineIndices: [Int]
    }

    public struct OccurrenceResult: Equatable, Sendable, Codable {
        public let lyricLineIndex: Int
        public let groupID: String?
        public let occurrenceIndex: Int
        public let absoluteStart: TimeInterval?
        public let decision: Decision
        public let reason: String
        public let neighboringSupport: Int
    }

    public struct Resolution: Equatable, Sendable {
        public let groups: [RepeatedGroup]
        public let results: [OccurrenceResult]
        public let diagnostics: [String]
    }

    public struct CaptureWindow: Equatable, Sendable {
        public let absoluteStart: TimeInterval
        public let absoluteEnd: TimeInterval
        public let trackDuration: TimeInterval

        public init(absoluteStart: TimeInterval, absoluteEnd: TimeInterval, trackDuration: TimeInterval) {
            self.absoluteStart = max(0, absoluteStart)
            self.absoluteEnd = max(self.absoluteStart + 0.05, absoluteEnd)
            self.trackDuration = max(self.absoluteEnd, trackDuration)
        }

        public func contains(_ t: TimeInterval, slack: TimeInterval = 0.75) -> Bool {
            t >= absoluteStart - slack && t <= absoluteEnd + slack
        }
    }

    /// Group lines that share the same match-view key (repeated chorus / identical lines).
    public static func buildGroups(
        plainLines: [LyricLine],
        language: String = "ja"
    ) -> [RepeatedGroup] {
        var buckets: [String: [Int]] = [:]
        for (i, line) in plainLines.enumerated() {
            let key = TranscriptNormalizer.matchView(line.originalText, language: language)
            guard key.count >= 4 else { continue }
            buckets[key, default: []].append(i)
        }
        return buckets
            .filter { $0.value.count >= 2 }
            .map { key, indices in
                RepeatedGroup(
                    groupID: "rep-\(abs(key.hashValue))",
                    matchKey: key,
                    lineIndices: indices.sorted()
                )
            }
            .sorted { $0.groupID < $1.groupID }
    }

    /// Resolve timed candidates under capture-window + repeated-section constraints.
    /// - Parameters:
    ///   - timedLines: absolute start times already mapped (Spotify domain).
    ///   - capture: absolute capture window (must not match outside).
    ///   - anchors: accepted anchors used as neighboring support.
    public static func resolve(
        plainLines: [LyricLine],
        timedLines: [Int: TimeInterval],
        capture: CaptureWindow,
        anchors: [AlignmentAnchor],
        language: String = "ja"
    ) -> Resolution {
        let groups = buildGroups(plainLines: plainLines, language: language)
        let groupByLine: [Int: RepeatedGroup] = {
            var map: [Int: RepeatedGroup] = [:]
            for g in groups {
                for i in g.lineIndices { map[i] = g }
            }
            return map
        }()
        let occurrenceIndex: [Int: Int] = {
            var map: [Int: Int] = [:]
            for g in groups {
                for (occ, line) in g.lineIndices.enumerated() {
                    map[line] = occ
                }
            }
            return map
        }()

        var results: [OccurrenceResult] = []
        var diag: [String] = []
        diag.append("repeated_groups=\(groups.count) capture=\(fmt(capture.absoluteStart))-\(fmt(capture.absoluteEnd))")

        let anchorByLine = Dictionary(uniqueKeysWithValues: anchors.map { ($0.lyricLineIndex, $0) })

        for index in plainLines.indices {
            let group = groupByLine[index]
            let occ = occurrenceIndex[index] ?? 0
            guard let start = timedLines[index] else {
                results.append(
                    OccurrenceResult(
                        lyricLineIndex: index,
                        groupID: group?.groupID,
                        occurrenceIndex: occ,
                        absoluteStart: nil,
                        decision: .unresolved,
                        reason: "no_timed_candidate",
                        neighboringSupport: neighborSupport(index: index, anchors: anchorByLine)
                    )
                )
                continue
            }

            // 1) Capture-window hard constraint
            if !capture.contains(start) {
                results.append(
                    OccurrenceResult(
                        lyricLineIndex: index,
                        groupID: group?.groupID,
                        occurrenceIndex: occ,
                        absoluteStart: start,
                        decision: .rejected,
                        reason: "outside_capture_window",
                        neighboringSupport: neighborSupport(index: index, anchors: anchorByLine)
                    )
                )
                continue
            }

            // 2) Track bounds
            if start < -0.25 || start > capture.trackDuration + 0.5 {
                results.append(
                    OccurrenceResult(
                        lyricLineIndex: index,
                        groupID: group?.groupID,
                        occurrenceIndex: occ,
                        absoluteStart: start,
                        decision: .rejected,
                        reason: "outside_track_duration",
                        neighboringSupport: neighborSupport(index: index, anchors: anchorByLine)
                    )
                )
                continue
            }

            // 3) Repeated group: occurrence order vs time order among accepted peers
            if let group {
                let peers = group.lineIndices.compactMap { li -> (Int, TimeInterval)? in
                    guard let t = timedLines[li], capture.contains(t) else { return nil }
                    return (li, t)
                }
                // If another earlier occurrence has a later absolute time → conflict
                var orderConflict = false
                for (otherLine, otherT) in peers where otherLine != index {
                    let otherOcc = occurrenceIndex[otherLine] ?? 0
                    if otherOcc < occ, otherT > start + 0.35 {
                        orderConflict = true
                        break
                    }
                    if otherOcc > occ, otherT + 0.35 < start {
                        orderConflict = true
                        break
                    }
                }
                if orderConflict {
                    results.append(
                        OccurrenceResult(
                            lyricLineIndex: index,
                            groupID: group.groupID,
                            occurrenceIndex: occ,
                            absoluteStart: start,
                            decision: .rejected,
                            reason: "wrong_occurrence_order_conflict",
                            neighboringSupport: neighborSupport(index: index, anchors: anchorByLine)
                        )
                    )
                    continue
                }

                // 4) Ambiguous: identical text, no neighboring anchors, weak isolation
                let support = neighborSupport(index: index, anchors: anchorByLine)
                let isolated = peers.count == 1
                if support == 0, !isolated, peers.count >= 2 {
                    // Prefer keeping the occurrence whose time is closest to capture midpoint
                    // only when uniqueness is clear; else unresolved.
                    let mid = (capture.absoluteStart + capture.absoluteEnd) / 2
                    let best = peers.min { abs($0.1 - mid) < abs($1.1 - mid) }
                    if best?.0 != index {
                        results.append(
                            OccurrenceResult(
                                lyricLineIndex: index,
                                groupID: group.groupID,
                                occurrenceIndex: occ,
                                absoluteStart: start,
                                decision: .unresolved,
                                reason: "ambiguous_repeated_section_no_neighbor_support",
                                neighboringSupport: 0
                            )
                        )
                        continue
                    }
                }
            }

            results.append(
                OccurrenceResult(
                    lyricLineIndex: index,
                    groupID: group?.groupID,
                    occurrenceIndex: occ,
                    absoluteStart: start,
                    decision: .accepted,
                    reason: group == nil ? "unique_line_in_capture" : "repeated_section_disambiguated",
                    neighboringSupport: neighborSupport(index: index, anchors: anchorByLine)
                )
            )
        }

        let rejected = results.filter { $0.decision == .rejected }.count
        let unresolved = results.filter { $0.decision == .unresolved }.count
        diag.append("resolve rejected=\(rejected) unresolved=\(unresolved) accepted=\(results.count - rejected - unresolved)")
        return Resolution(groups: groups, results: results, diagnostics: diag)
    }

    /// Filter absolute candidate times using resolution decisions (reject only).
    public static func applyRejections(
        times: [Int: TimeInterval],
        resolution: Resolution
    ) -> [Int: TimeInterval] {
        let rejected = Set(
            resolution.results
                .filter { $0.decision == .rejected }
                .map(\.lyricLineIndex)
        )
        let ambiguous = Set(
            resolution.results
                .filter { $0.decision == .unresolved && $0.reason.contains("ambiguous") }
                .map(\.lyricLineIndex)
        )
        var out = times
        for i in rejected.union(ambiguous) {
            out.removeValue(forKey: i)
        }
        return out
    }

    private static func neighborSupport(index: Int, anchors: [Int: AlignmentAnchor]) -> Int {
        var n = 0
        for d in [-2, -1, 1, 2] {
            if anchors[index + d] != nil { n += 1 }
        }
        return n
    }

    private static func fmt(_ t: TimeInterval) -> String {
        String(format: "%.2f", t)
    }
}

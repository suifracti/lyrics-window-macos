#if DEBUG
import Foundation

/// S3A: run Speech + LineForcedAligner per continuous CapturedAudioSegment,
/// map relative Speech times to absolute Spotify positions, and emit a
/// Debug-only PartialAlignmentCandidate (never written to formal SQLite).
public enum SegmentPartialAlignmentPipeline {
    public static let reportDirectoryName = "s3a-reports"

    /// Align plain lyric lines against one or more continuous segments that
    /// already have temporary 16 kHz mono WAV paths.
    public static func align(
        session: CapturedAudioSession,
        segments: [CapturedAudioSegment],
        plainLines: [LyricLine],
        languageHint: String?,
        localeOverride: String?,
        groundTruthSyncedLines: [LyricLine]?,
        identity: TrackIdentity,
        generation: UInt64,
        isGenerationCurrent: @escaping @Sendable () -> Bool
    ) async throws -> PartialAlignmentReport {
        guard isGenerationCurrent() else {
            throw AlignmentError.cancelled
        }
        let text = plainLines.map(\.originalText).joined(separator: "\n")
        let localeRec = AlignmentLocaleRecommender.recommend(
            languageHint: languageHint,
            lyricText: text,
            override: localeOverride
        )
        SCKSpikeLog.log(
            "S3A locale=\(localeRec.localeIdentifier) reason=\(localeRec.reason) fallback=\(localeRec.usedFallback)"
        )

        let usable = segments.filter { seg in
            guard let path = seg.temporaryPCMReference, path.hasSuffix(".wav") else { return false }
            return FileManager.default.isReadableFile(atPath: path) && seg.sampleCount > 0
        }
        guard !usable.isEmpty else {
            throw AlignmentError.invalidAudio("没有可用于识别的 segment WAV")
        }

        var ranges: [CapturedTimeRange] = []
        var totalTranscriptSegments = 0
        var totalCapturedDuration: TimeInterval = 0
        // Best absolute time per lyric line across segments (prefer higher confidence).
        var bestByLine: [Int: PartialAlignedLine] = [:]

        let provider = SpeechTimedTranscriptProvider(localeIdentifier: localeRec.localeIdentifier)

        for segment in usable {
            guard isGenerationCurrent() else { throw AlignmentError.cancelled }
            guard let wavPath = segment.temporaryPCMReference else { continue }
            let wavURL = URL(fileURLWithPath: wavPath)
            let posStart = segment.spotifyPositionStart
            let posEnd = segment.spotifyPositionEnd ?? (posStart + max(segment.duration, 0.1))
            ranges.append(CapturedTimeRange(segmentID: segment.segmentID, start: posStart, end: posEnd))
            totalCapturedDuration += max(0, posEnd - posStart)

            SCKSpikeLog.log(
                "S3A speech begin segmentID=\(segment.segmentID.uuidString.prefix(8)) wav=\(wavURL.lastPathComponent) pos=\(fmt(posStart))->\(fmt(posEnd))"
            )
            let transcript: TimedTranscript
            do {
                transcript = try await provider.transcribe(
                    pcmURL: wavURL,
                    localeIdentifier: localeRec.localeIdentifier,
                    progress: nil
                )
            } catch {
                SCKSpikeLog.log("S3A speech failed segmentID=\(segment.segmentID.uuidString.prefix(8)) error=\(error.localizedDescription)")
                continue
            }
            guard isGenerationCurrent() else { throw AlignmentError.cancelled }
            totalTranscriptSegments += transcript.segments.count
            SCKSpikeLog.log(
                "S3A speech ok segmentID=\(segment.segmentID.uuidString.prefix(8)) transcriptSegments=\(transcript.segments.count) audioDuration=\(fmt(transcript.audioDuration))"
            )

            let result = LineForcedAligner.align(
                lines: plainLines,
                transcript: transcript,
                audioDuration: max(transcript.audioDuration, segment.duration),
                parameters: AlignmentParameters(
                    recognizerID: transcript.backendID,
                    localeIdentifier: localeRec.localeIdentifier,
                    sampleRate: 16_000,
                    channels: 1
                )
            )
            // Partial: do NOT require result.isComplete.
            for (index, aligned) in result.lines.enumerated() {
                let textLine = plainLines[index].originalText
                if aligned.startTime < 0 {
                    // Leave unresolved unless already set by another segment.
                    if bestByLine[index] == nil {
                        bestByLine[index] = PartialAlignedLine(
                            sourceLineIndex: index,
                            text: textLine,
                            status: .unresolved,
                            startTime: nil,
                            endTime: nil,
                            confidence: aligned.confidence,
                            segmentID: segment.segmentID,
                            evidenceKind: aligned.evidence.kind.rawValue
                        )
                    }
                    continue
                }
                let absStart = posStart + aligned.startTime
                let absEnd = aligned.endTime.map { posStart + $0 }
                let status: PartialLineStatus
                switch aligned.status {
                case .aligned: status = .resolved
                case .lowConfidence: status = .lowConfidence
                case .interpolated: status = .interpolated
                case .unmatched: status = .unresolved
                }
                let candidate = PartialAlignedLine(
                    sourceLineIndex: index,
                    text: textLine,
                    status: status,
                    startTime: absStart,
                    endTime: absEnd,
                    confidence: aligned.confidence,
                    segmentID: segment.segmentID,
                    evidenceKind: aligned.evidence.kind.rawValue,
                    speechRelativeStart: aligned.startTime,
                    speechRelativeEnd: aligned.endTime
                )
                if let existing = bestByLine[index] {
                    if shouldReplace(existing, with: candidate) {
                        bestByLine[index] = candidate
                    }
                } else {
                    bestByLine[index] = candidate
                }
            }
        }

        // Mark lines outside all captured ranges.
        var lines: [PartialAlignedLine] = []
        for index in plainLines.indices {
            if let row = bestByLine[index], row.startTime != nil {
                lines.append(row)
                continue
            }
            if let gt = groundTruthSyncedLines, index < gt.count {
                let gtTime = gt[index].timestamp
                let covered = ranges.contains { gtTime >= $0.start - 0.25 && gtTime <= $0.end + 0.25 }
                if !covered {
                    lines.append(
                        PartialAlignedLine(
                            sourceLineIndex: index,
                            text: plainLines[index].originalText,
                            status: .outsideCapturedRange,
                            startTime: nil,
                            endTime: nil,
                            confidence: 0,
                            segmentID: nil,
                            evidenceKind: "outsideCapturedRange"
                        )
                    )
                    continue
                }
            }
            // Inside capture window but unresolved, or no ground truth to judge coverage.
            if let row = bestByLine[index] {
                lines.append(row)
            } else {
                lines.append(
                    PartialAlignedLine(
                        sourceLineIndex: index,
                        text: plainLines[index].originalText,
                        status: .unresolved,
                        startTime: nil,
                        endTime: nil,
                        confidence: 0,
                        segmentID: nil,
                        evidenceKind: "noEvidence"
                    )
                )
            }
        }
        lines.sort { $0.sourceLineIndex < $1.sourceLineIndex }

        let resolved = lines.filter { $0.status == .resolved || $0.status == .interpolated }.count
        let low = lines.filter { $0.status == .lowConfidence }.count
        let unresolved = lines.filter { $0.status == .unresolved }.count
        let outside = lines.filter { $0.status == .outsideCapturedRange }.count
        let timed = lines.filter { $0.startTime != nil }
        let overall: Double = {
            guard !timed.isEmpty else { return 0 }
            return timed.map(\.confidence).reduce(0, +) / Double(timed.count)
        }()
        let coverage = plainLines.isEmpty ? 0 : Double(resolved + low) / Double(plainLines.count)

        let candidate = PartialAlignmentCandidate(
            trackIdentityDigest: String(identity.stableKey.prefix(48)),
            captureSessionID: session.sessionID,
            locale: localeRec.localeIdentifier,
            localeFallbackReason: localeRec.usedFallback ? localeRec.reason : nil,
            capturedRanges: ranges,
            lines: lines,
            overallConfidence: overall,
            resolvedCount: resolved,
            unresolvedCount: unresolved,
            lowConfidenceCount: low,
            outsideCapturedRangeCount: outside,
            coverageRatio: coverage,
            transcriptSegmentCount: totalTranscriptSegments,
            capturedDuration: totalCapturedDuration
        )

        let heldOut = evaluateHeldOut(
            candidateLines: lines,
            groundTruth: groundTruthSyncedLines
        )
        let judgment = makeJudgment(candidate: candidate, heldOut: heldOut)
        let report = PartialAlignmentReport(
            candidate: candidate,
            heldOut: heldOut,
            judgment: judgment,
            wavPaths: usable.compactMap(\.temporaryPCMReference)
        )
        try writeReport(report, sessionID: session.sessionID)
        SCKSpikeLog.log(
            "S3A done session=\(session.sessionID.uuidString.prefix(8)) lines=\(plainLines.count) resolved=\(resolved) low=\(low) unresolved=\(unresolved) outside=\(outside) coverage=\(fmt(coverage)) transcripts=\(totalTranscriptSegments) judgment=\(judgment)"
        )
        return report
    }

    /// Strip timestamps for algorithm input while preserving text order.
    public static func plainLines(from document: LyricsDocument) -> [LyricLine] {
        document.lines.map { line in
            LyricLine(
                id: line.id,
                timestamp: 0,
                originalText: line.originalText,
                endTime: nil,
                translationText: line.translationText,
                romajiText: line.romajiText,
                kanaText: line.kanaText,
                rubyTokens: line.rubyTokens
            )
        }
    }

    private static func shouldReplace(_ existing: PartialAlignedLine, with candidate: PartialAlignedLine) -> Bool {
        let rank: (PartialLineStatus) -> Int = { status in
            switch status {
            case .resolved: return 4
            case .interpolated: return 3
            case .lowConfidence: return 2
            case .unresolved: return 1
            case .outsideCapturedRange: return 0
            }
        }
        if rank(candidate.status) != rank(existing.status) {
            return rank(candidate.status) > rank(existing.status)
        }
        return candidate.confidence > existing.confidence
    }

    public static func evaluateHeldOut(
        candidateLines: [PartialAlignedLine],
        groundTruth: [LyricLine]?
    ) -> HeldOutErrorStats {
        guard let groundTruth, !groundTruth.isEmpty else {
            return .unavailable("no_held_out_synced_lyrics")
        }
        var errors: [TimeInterval] = []
        var obvious = 0
        for line in candidateLines {
            guard let start = line.startTime,
                  line.status == .resolved || line.status == .lowConfidence || line.status == .interpolated,
                  line.sourceLineIndex < groundTruth.count else { continue }
            let gt = groundTruth[line.sourceLineIndex].timestamp
            guard gt.isFinite, gt >= 0 else { continue }
            let err = abs(start - gt)
            errors.append(err)
            if err > 3.0 { obvious += 1 }
        }
        guard !errors.isEmpty else {
            return .unavailable("no_overlapping_timed_lines_for_comparison")
        }
        let sorted = errors.sorted()
        func percentile(_ p: Double) -> TimeInterval {
            let idx = min(sorted.count - 1, max(0, Int((Double(sorted.count - 1) * p).rounded())))
            return sorted[idx]
        }
        let mean = errors.reduce(0, +) / Double(errors.count)
        return HeldOutErrorStats(
            comparedLineCount: errors.count,
            medianAbsoluteError: percentile(0.5),
            p90AbsoluteError: percentile(0.9),
            p95AbsoluteError: percentile(0.95),
            meanAbsoluteError: mean,
            obviousMismatchCount: obvious,
            note: "held_out_start_time_abs_error_seconds"
        )
    }

    private static func makeJudgment(
        candidate: PartialAlignmentCandidate,
        heldOut: HeldOutErrorStats
    ) -> String {
        let coverage = candidate.coverageRatio
        let median = heldOut.medianAbsoluteError
        if coverage >= 0.45, let median, median <= 1.25, heldOut.obviousMismatchCount <= max(2, heldOut.comparedLineCount / 5) {
            return "A_speech_dp_usable"
        }
        if coverage >= 0.15 || (heldOut.comparedLineCount > 0 && (median ?? 99) < 4.0) {
            return "B_partial_needs_anchor_s3b"
        }
        return "C_speech_weak_on_singing"
    }

    private static func writeReport(_ report: PartialAlignmentReport, sessionID: UUID) throws {
        // Keep reports outside the capture tree so stop() scavengers don't
        // delete evidence before acceptance copies it.
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("spotifylyrics-s3a-reports", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let jsonURL = root.appendingPathComponent("partial-\(sessionID.uuidString.prefix(8)).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(report)
        try data.write(to: jsonURL, options: .atomic)

        let mdURL = root.appendingPathComponent("partial-\(sessionID.uuidString.prefix(8)).md")
        let c = report.candidate
        let h = report.heldOut
        var md = """
        # S3A Partial Alignment Report

        - session: `\(c.captureSessionID.uuidString)`
        - identity: `\(c.trackIdentityDigest)`
        - locale: `\(c.locale)` fallback: \(c.localeFallbackReason ?? "none")
        - capturedDuration: \(fmt(c.capturedDuration)) s
        - transcriptSegments: \(c.transcriptSegmentCount)
        - lines: \(c.lines.count)
        - resolved: \(c.resolvedCount)
        - lowConfidence: \(c.lowConfidenceCount)
        - unresolved: \(c.unresolvedCount)
        - outsideCapturedRange: \(c.outsideCapturedRangeCount)
        - coverageRatio: \(fmt(c.coverageRatio))
        - overallConfidence: \(fmt(c.overallConfidence))
        - judgment: **\(report.judgment)**

        ## Held-out errors
        - compared: \(h.comparedLineCount)
        - medianAbsErr: \(h.medianAbsoluteError.map(fmt) ?? "n/a")
        - p90: \(h.p90AbsoluteError.map(fmt) ?? "n/a")
        - p95: \(h.p95AbsoluteError.map(fmt) ?? "n/a")
        - mean: \(h.meanAbsoluteError.map(fmt) ?? "n/a")
        - obviousMismatch(>3s): \(h.obviousMismatchCount)
        - note: \(h.note)

        ## Lines (first 40)
        """
        for line in c.lines.prefix(40) {
            let t = line.startTime.map(fmt) ?? "-"
            md += "\n- [\(line.sourceLineIndex)] \(line.status.rawValue) t=\(t) conf=\(fmt(line.confidence)) \(line.text.prefix(40))"
        }
        try md.write(to: mdURL, atomically: true, encoding: .utf8)
        SCKSpikeLog.log("S3A report json=\(jsonURL.path)")
        SCKSpikeLog.log("S3A report md=\(mdURL.path)")
    }

    private static func fmt(_ value: TimeInterval) -> String {
        String(format: "%.3f", value)
    }
}
#endif

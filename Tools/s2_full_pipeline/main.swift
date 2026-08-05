#if DEBUG
import Foundation
import AVFoundation

/// Offline S2 harness: SpeechEngineResult JSON or live engine → S3A → S3B → Merger.
/// Never opens formal SQLite. Never adopts / saves lyrics.
@main
struct S2FullPipelineMain {
    static func main() async {
        do {
            try await run()
        } catch {
            fputs("S2_FAIL \(error)\n", stderr)
            exit(1)
        }
    }

    static func run() async throws {
        let args = Array(CommandLine.arguments.dropFirst())
        var map: [String: String] = [:]
        var i = 0
        while i < args.count {
            let a = args[i]
            if a.hasPrefix("--"), i + 1 < args.count {
                map[String(a.dropFirst(2))] = args[i + 1]
                i += 2
            } else {
                i += 1
            }
        }

        guard let wavPath = map["wav"],
              let lyricsPath = map["lyrics"],
              let outDir = map["out"] else {
            fputs("Usage: s2_full_pipeline --wav PATH --lyrics PATH --out DIR [--engine apple|whisper_small|whisper_medium] [--lang ja|zh|en] [--transcript-json PATH] [--gt PATH] [--title T] [--artist A]\n", stderr)
            exit(2)
        }

        let engineName = map["engine"] ?? "apple"
        let lang = map["lang"] ?? "ja"
        let title = map["title"] ?? "sample"
        let artist = map["artist"] ?? "unknown"
        let writeSidecar = (map["write-sidecar"] ?? "0") == "1"

        let fm = FileManager.default
        try fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)
        let wavURL = URL(fileURLWithPath: wavPath)
        guard fm.isReadableFile(atPath: wavPath) else {
            throw AlignmentError.invalidAudio("WAV unreadable: \(wavPath)")
        }

        let plainText = try String(contentsOfFile: lyricsPath, encoding: .utf8)
        let plainLines: [LyricLine] = plainText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { LyricLine(timestamp: 0, originalText: $0) }
        guard !plainLines.isEmpty else {
            throw AlignmentError.failed("empty lyrics")
        }

        let duration = try audioDuration(url: wavURL)
        let sampleCount = try estimateSampleCount(url: wavURL, duration: duration)

        // --- Speech ---
        let speechStarted = Date()
        let engineResult: SpeechEngineResult
        if let inject = map["transcript-json"], fm.isReadableFile(atPath: inject) {
            engineResult = try loadTranscriptJSON(path: inject, engineName: engineName, language: lang, duration: duration)
        } else {
            engineResult = try await runEngine(
                name: engineName,
                wavURL: wavURL,
                language: lang
            )
        }
        let speechElapsed = Date().timeIntervalSince(speechStarted)
        let transcript = engineResult.asTimedTranscript()

        // Persist raw speech result
        let speechOut = [
            "engine": engineResult.engineID.rawValue,
            "engine_label": engineName,
            "language": engineResult.language,
            "elapsed_seconds": engineResult.elapsedSeconds > 0 ? engineResult.elapsedSeconds : speechElapsed,
            "audio_duration": engineResult.audioDuration,
            "diagnostics": engineResult.diagnostics,
            "segments": engineResult.segments.map { seg -> [String: Any] in
                [
                    "index": seg.index,
                    "text": seg.text,
                    "start": seg.startTime,
                    "end": seg.endTime,
                    "confidence": seg.confidence as Any
                ]
            }
        ] as [String: Any]
        try writeJSON(speechOut, to: "\(outDir)/speech.json")

        // --- Captured session (single continuous segment spanning WAV) ---
        let identity = TrackIdentity(
            title: title,
            artist: artist,
            album: "",
            duration: duration
        )
        let sessionID = UUID()
        let segmentID = UUID()
        let segment = CapturedAudioSegment(
            segmentID: segmentID,
            sessionID: sessionID,
            trackIdentity: identity,
            spotifyPositionStart: 0,
            spotifyPositionEnd: duration,
            hostTimeStart: 0,
            hostTimeEnd: duration,
            audioPTSStart: 0,
            audioPTSEnd: duration,
            sampleRate: 16_000,
            channelCount: 1,
            sampleCount: sampleCount,
            bufferCount: max(1, sampleCount / 1600),
            duration: duration,
            continuityID: UUID(),
            startReason: .initial,
            endReason: .autoStop,
            temporaryPCMReference: wavPath,
            isContinuous: true
        )
        let session = CapturedAudioSession(
            sessionID: sessionID,
            trackIdentity: identity,
            trackDuration: duration,
            segments: [segment],
            terminalReason: .autoStop
        )

        var groundTruth: [LyricLine]? = nil
        if let gtPath = map["gt"], fm.isReadableFile(atPath: gtPath) {
            groundTruth = try loadGroundTruth(path: gtPath, plainLines: plainLines)
        }

        let locale: String = {
            switch lang {
            case "zh": return "zh-CN"
            case "en": return "en-US"
            default: return "ja-JP"
            }
        }()

        let report = try SegmentPartialAlignmentPipeline.alignFromTimedTranscript(
            session: session,
            segment: segment,
            plainLines: plainLines,
            transcript: transcript,
            languageHint: locale,
            localeOverride: locale,
            groundTruthSyncedLines: groundTruth,
            identity: identity,
            writeSidecar: writeSidecar
        )

        let mergeOut = AssistedCandidateMerger.mergeWithExplanation(report: report, plainLines: plainLines)
        let draft = mergeOut.draft

        // Encode reports
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        try enc.encode(report).write(to: URL(fileURLWithPath: "\(outDir)/alignment_report.json"), options: .atomic)
        try enc.encode(draft).write(to: URL(fileURLWithPath: "\(outDir)/merger_draft.json"), options: .atomic)
        try enc.encode(mergeOut.decisions).write(
            to: URL(fileURLWithPath: "\(outDir)/merger_decisions.json"),
            options: .atomic
        )

        // Transcript prep audit (normalize + split)
        let prep = SegmentPartialAlignmentPipeline.prepareTranscript(
            timed: transcript,
            plainLines: plainLines,
            languageHint: locale
        )
        var prepJSON: [String: Any] = [
            "raw_pieces": engineResult.segments.count,
            "prepared_pieces": prep.transcript.segments.count,
            "diagnostics": prep.diagnostics,
            "has_asr_confidence": engineResult.hasAsrConfidence,
            "subsegments": prep.split.subsegments.map { sub -> [String: Any] in
                [
                    "sourceIndex": sub.sourceIndex,
                    "text": sub.originalText,
                    "match": sub.matchText,
                    "start": sub.startTime,
                    "end": sub.endTime,
                    "asrConfidence": sub.asrConfidence as Any,
                    "timeProvenance": sub.timeProvenance.rawValue,
                    "splitReason": sub.splitReason,
                    "matchedLyricLineIndex": sub.matchedLyricLineIndex as Any
                ]
            }
        ]
        _ = prepJSON
        try writeJSON(prepJSON, to: "\(outDir)/transcript_prep.json")

        // Merger source breakdown
        let anchorN = draft.lines.filter { $0.status == .suggested && $0.source == .anchor }.count
        let speechN = draft.lines.filter { $0.status == .suggested && $0.source == .speechResolved }.count
        let s3aOnly = draft.lines.filter { $0.evidenceSummary.hasPrefix("s3a:") }.count
        let s3bOnly = draft.lines.filter { $0.evidenceSummary.hasPrefix("s3b:") }.count

        let metrics: [String: Any] = [
            "sample_title": title,
            "engine": engineName,
            "engine_id": engineResult.engineID.rawValue,
            "language": lang,
            "speech": [
                "pieces": engineResult.segments.count,
                "non_empty_chars": engineResult.segments.map(\.text).joined().filter { !$0.isWhitespace }.count,
                "empty_segments": engineResult.segments.filter { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count,
                "elapsed_seconds": engineResult.elapsedSeconds > 0 ? engineResult.elapsedSeconds : speechElapsed,
                "audio_duration": duration
            ],
            "s3a": candidateMetrics(report.s3aCandidate),
            "s3b": candidateMetrics(report.candidate),
            "s3b_anchors_accepted": report.acceptedAnchors.count,
            "s3b_anchors_rejected": report.rejectedAnchors.count,
            "s3b_used_constrained": report.usedConstrainedAlignment,
            "s3b_fallback": report.s3bFallbackReason as Any,
            "judgment": report.judgment,
            "held_out": heldOutMetrics(report.heldOut),
            "s3a_held_out": report.s3aHeldOut.map(heldOutMetrics) as Any,
            "merger": [
                "plain_line_count": draft.plainLineCount,
                "final_suggestions": draft.suggestedCount,
                "unresolved": draft.unresolvedCount,
                "outside": draft.outsideCapturedRangeCount,
                "from_anchor": anchorN,
                "from_speech_resolved": speechN,
                "evidence_s3a": s3aOnly,
                "evidence_s3b": s3bOnly,
                "suggestion_coverage": draft.plainLineCount > 0
                    ? Double(draft.suggestedCount) / Double(draft.plainLineCount) : 0
            ],
            "formal_db_opened": false
        ]
        try writeJSON(metrics, to: "\(outDir)/metrics.json")
        fputs("S2_OK engine=\(engineName) suggestions=\(draft.suggestedCount) s3a_cov=\(report.s3aCandidate?.coverageRatio ?? -1) s3b_cov=\(report.candidate.coverageRatio) anchors=\(report.acceptedAnchors.count)\n", stderr)
    }

    static func runEngine(name: String, wavURL: URL, language: String) async throws -> SpeechEngineResult {
        switch name {
        case "apple":
            let engine = AppleSpeechEngine(localeIdentifier: localeFor(language))
            return try await engine.transcribe(pcmURL: wavURL, languageHint: localeFor(language), progress: nil)
        case "whisper_small", "whisper_medium", "whisper":
            // Model path expected via SPOTIFYLYRICS_WHISPER_MODEL env.
            var env = ProcessInfo.processInfo.environment
            env[WhisperCLISpeechEngine.languageEnvironmentKey] = language
            let engine = WhisperCLISpeechEngine(environment: env)
            guard engine.isAvailable else {
                throw SpeechEngineError.unavailable("whisper CLI/model unavailable for \(name)")
            }
            return try await engine.transcribe(pcmURL: wavURL, languageHint: language, progress: nil)
        default:
            throw SpeechEngineError.unavailable("unknown engine \(name)")
        }
    }

    static func localeFor(_ language: String) -> String {
        switch language {
        case "zh": return "zh-CN"
        case "en": return "en-US"
        default: return "ja-JP"
        }
    }

    static func loadTranscriptJSON(path: String, engineName: String, language: String, duration: TimeInterval) throws -> SpeechEngineResult {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AlignmentError.failed("bad transcript json")
        }
        // Accept either harness speech.json or whisper -oj shape.
        var segments: [SpeechEngineSegment] = []
        if let segs = root["segments"] as? [[String: Any]] {
            for (i, row) in segs.enumerated() {
                let text = (row["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                let start = (row["start"] as? Double) ?? (row["startTime"] as? Double) ?? 0
                let end = (row["end"] as? Double) ?? (row["endTime"] as? Double) ?? (start + 0.1)
                segments.append(SpeechEngineSegment(index: segments.count, text: text, startTime: start, endTime: end, confidence: row["confidence"] as? Double))
                _ = i
            }
        } else if let rows = root["transcription"] as? [[String: Any]] {
            segments = try WhisperCLISpeechEngine.parseWhisperJSON(data)
            _ = rows
        } else {
            throw AlignmentError.failed("transcript json missing segments")
        }
        let engineID: SpeechEngineID = engineName.hasPrefix("whisper") ? .whisperCLI : .apple
        let audioDuration = (root["audio_duration"] as? Double) ?? max(duration, segments.map(\.endTime).max() ?? 0)
        return SpeechEngineResult(
            engineID: engineID,
            language: (root["language"] as? String) ?? language,
            segments: segments,
            audioDuration: audioDuration,
            diagnostics: ["source=inject:\(path)"],
            elapsedSeconds: (root["elapsed_seconds"] as? Double) ?? 0
        )
    }

    static func loadGroundTruth(path: String, plainLines: [LyricLine]) throws -> [LyricLine] {
        // Format: index<TAB>start_seconds per line, or LRC [mm:ss.xx]text
        let raw = try String(contentsOfFile: path, encoding: .utf8)
        var times: [Int: TimeInterval] = [:]
        for line in raw.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty || t.hasPrefix("#") { continue }
            if t.contains("\t") {
                let parts = t.split(separator: "\t")
                if parts.count >= 2, let idx = Int(parts[0]), let sec = Double(parts[1]) {
                    times[idx] = sec
                }
            } else if t.hasPrefix("["), let close = t.firstIndex(of: "]") {
                let stamp = String(t[t.index(after: t.startIndex)..<close])
                let body = String(t[t.index(after: close)...])
                if let sec = parseLRC(stamp) {
                    if let match = plainLines.firstIndex(where: { $0.originalText == body || body.hasSuffix($0.originalText) }) {
                        times[match] = sec
                    }
                }
            }
        }
        return plainLines.enumerated().map { i, line in
            LyricLine(
                id: line.id,
                timestamp: times[i] ?? line.timestamp,
                originalText: line.originalText,
                endTime: line.endTime
            )
        }
    }

    static func parseLRC(_ stamp: String) -> TimeInterval? {
        let parts = stamp.split(separator: ":")
        guard parts.count == 2, let m = Double(parts[0]), let s = Double(parts[1]) else { return nil }
        return m * 60 + s
    }

    static func audioDuration(url: URL) throws -> TimeInterval {
        let asset = AVURLAsset(url: url)
        let d = CMTimeGetSeconds(asset.duration)
        guard d.isFinite, d > 0 else { throw AlignmentError.invalidAudio("bad duration") }
        return d
    }

    static func estimateSampleCount(url: URL, duration: TimeInterval) throws -> Int {
        // Prefer file size for 16k mono s16le; else duration * 16000.
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        if let size = attrs[.size] as? NSNumber {
            let bytes = size.intValue
            if bytes > 44 {
                return max(1, (bytes - 44) / 2)
            }
        }
        return max(1, Int(duration * 16_000))
    }

    static func candidateMetrics(_ c: PartialAlignmentCandidate?) -> [String: Any] {
        guard let c else { return ["present": false] }
        let timed = c.lines.compactMap(\.startTime)
        var monoViolations = 0
        var last: TimeInterval = -1
        for t in timed {
            if t + 0.001 < last { monoViolations += 1 }
            last = max(last, t)
        }
        return [
            "present": true,
            "line_count": c.lines.count,
            "resolved": c.resolvedCount,
            "low": c.lowConfidenceCount,
            "unresolved": c.unresolvedCount,
            "outside": c.outsideCapturedRangeCount,
            "coverage": c.coverageRatio,
            "overall_confidence": c.overallConfidence,
            "transcript_segments": c.transcriptSegmentCount,
            "monotonic_violations": monoViolations
        ]
    }

    static func heldOutMetrics(_ h: HeldOutErrorStats) -> [String: Any] {
        [
            "compared": h.comparedLineCount,
            "median_abs_error": h.medianAbsoluteError as Any,
            "p90": h.p90AbsoluteError as Any,
            "mean": h.meanAbsoluteError as Any,
            "gt_3s_mismatch": h.obviousMismatchCount,
            "note": h.note
        ]
    }

    static func writeJSON(_ obj: [String: Any], to path: String) throws {
        let data = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}
#endif

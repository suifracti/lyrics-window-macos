import Foundation
import Speech
import AVFoundation

/// Production Speech-backed timed transcript adapter. The recognizer response
/// is kept in memory only and is converted to the small timed-segment model;
/// no transcript text is written to alignment provenance.
public final class SpeechTimedTranscriptProvider: TimedTranscriptProvider, @unchecked Sendable {
    public let id: String
    private let defaultLocaleIdentifier: String
    private let recognitionTimeoutNanoseconds: UInt64

    public init(
        localeIdentifier: String = "ja-JP",
        recognitionTimeoutNanoseconds: UInt64 = 120_000_000_000
    ) {
        self.defaultLocaleIdentifier = localeIdentifier
        self.recognitionTimeoutNanoseconds = recognitionTimeoutNanoseconds
        self.id = "speech-timed-\(localeIdentifier)-v1"
    }

    public func transcribe(
        pcmURL: URL,
        localeIdentifier: String,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> TimedTranscript {
        guard FileManager.default.isReadableFile(atPath: pcmURL.path) else {
            throw AlignmentError.invalidAudio("PCM 音频不可读")
        }
        try Task.checkCancellation()

        let locale = localeIdentifier.isEmpty ? defaultLocaleIdentifier : localeIdentifier
        let status = await withCheckedContinuation { (continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard status == .authorized else { throw AlignmentError.speechPermissionDenied }

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)),
              recognizer.isAvailable else {
            throw AlignmentError.recognizerUnavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: pcmURL)
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        if #available(macOS 13.0, *) {
            request.addsPunctuation = false
        }

        progress?(0.1)
        let transcription: SFTranscription
        do {
            transcription = try await withThrowingTaskGroup(of: SFTranscription.self) { group in
                group.addTask { [recognizer, request] in
                    try await self.runRecognition(recognizer: recognizer, request: request)
                }
                group.addTask { [timeout = recognitionTimeoutNanoseconds] in
                    try await Task.sleep(nanoseconds: timeout)
                    throw AlignmentError.failed("语音识别超时")
                }
                defer { group.cancelAll() }
                guard let first = try await group.next() else {
                    throw AlignmentError.failed("语音识别没有结果")
                }
                return first
            }
        } catch is CancellationError {
            throw AlignmentError.cancelled
        }
        try Task.checkCancellation()
        progress?(0.95)

        let asset = AVURLAsset(url: pcmURL)
        let audioDuration = CMTimeGetSeconds(asset.duration)
        guard audioDuration.isFinite, audioDuration > 0 else {
            throw AlignmentError.invalidAudio("无法读取 PCM 时长")
        }

        let segments = transcription.segments.enumerated().compactMap { entry -> TimedTranscriptSegment? in
            let segment = entry.element
            let text = segment.substring.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            let start = max(0, segment.timestamp)
            let end = min(audioDuration, start + max(0.02, segment.duration))
            return TimedTranscriptSegment(
                index: entry.offset,
                text: text,
                startTime: start,
                endTime: end,
                confidence: Double(max(0, segment.confidence))
            )
        }
        guard !segments.isEmpty else { throw AlignmentError.noSpeech }

        let transcript = TimedTranscript(
            backendID: id,
            segments: segments.enumerated().map { index, segment in
                TimedTranscriptSegment(
                    index: index,
                    text: segment.text,
                    startTime: segment.startTime,
                    endTime: segment.endTime,
                    confidence: segment.confidence
                )
            },
            audioDuration: audioDuration
        )
        guard transcript.isValid else {
            throw AlignmentError.failed("语音识别时间片段无效或不单调")
        }
        progress?(1)
        return transcript
    }

    private func runRecognition(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechURLRecognitionRequest
    ) async throws -> SFTranscription {
        let state = RecognitionTaskState()
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<SFTranscription, Error>) in
                state.install(continuation: continuation)
                let task = recognizer.recognitionTask(with: request) { result, error in
                    if let error {
                        state.finish(.failure(error))
                        return
                    }
                    guard let result, result.isFinal else { return }
                    state.finish(.success(result.bestTranscription))
                }
                state.install(task: task)
            }
        }, onCancel: {
            state.cancel(with: AlignmentError.cancelled)
        })
    }

    /// Bridges Swift task cancellation to the callback-only Speech API and
    /// guarantees that the continuation is resumed exactly once.
    private final class RecognitionTaskState: @unchecked Sendable {
        private let lock = NSLock()
        private var task: SFSpeechRecognitionTask?
        private var continuation: CheckedContinuation<SFTranscription, Error>?
        private var settled = false
        private var cancelled = false

        func install(continuation: CheckedContinuation<SFTranscription, Error>) {
            lock.lock()
            let shouldCancel = cancelled || settled
            if !shouldCancel { self.continuation = continuation }
            lock.unlock()

            if shouldCancel { continuation.resume(throwing: AlignmentError.cancelled) }
        }

        func install(task: SFSpeechRecognitionTask) {
            lock.lock()
            self.task = task
            let shouldCancel = cancelled || settled
            lock.unlock()
            if shouldCancel { task.cancel() }
        }

        func finish(_ result: Result<SFTranscription, Error>) {
            lock.lock()
            guard !settled else {
                lock.unlock()
                return
            }
            settled = true
            let continuation = self.continuation
            self.continuation = nil
            lock.unlock()
            continuation?.resume(with: result)
        }

        func cancel(with error: Error) {
            lock.lock()
            cancelled = true
            let task = self.task
            guard !settled else {
                lock.unlock()
                task?.cancel()
                return
            }
            settled = true
            let continuation = self.continuation
            self.continuation = nil
            lock.unlock()

            task?.cancel()
            continuation?.resume(throwing: error)
        }
    }
}

/// Known plain lyrics + local audio -> deterministic line-level alignment.
public final class SpeechForcedAlignmentService: AlignmentService, @unchecked Sendable {
    public let id = "speech-forced-v1"
    private let localeIdentifier: String
    private let transcriptProvider: any TimedTranscriptProvider

    public init(
        localeIdentifier: String = "ja-JP",
        recognitionTimeoutNanoseconds: UInt64 = 120_000_000_000,
        transcriptProvider: (any TimedTranscriptProvider)? = nil
    ) {
        self.localeIdentifier = localeIdentifier
        self.transcriptProvider = transcriptProvider
            ?? SpeechTimedTranscriptProvider(
                localeIdentifier: localeIdentifier,
                recognitionTimeoutNanoseconds: recognitionTimeoutNanoseconds
            )
    }

    public func align(
        _ request: AlignmentRequest,
        progress: (@Sendable (AlignmentProgress) -> Void)?
    ) async throws -> AlignmentReport {
        guard !request.plainLines.isEmpty else { throw AlignmentError.emptyLyrics }
        guard !request.sourceIsSynchronized else {
            throw AlignmentError.failed("已有时间轴的歌词不能直接覆盖；请创建新的纯文本来源版本")
        }
        try Task.checkCancellation()

        progress?(.preparingAudio(0.05))
        let prepared = try await AudioPCMConverter.prepare(audioURL: request.audioURL)
        defer { AudioPCMConverter.cleanup(prepared: prepared) }
        progress?(.preparingAudio(1.0))

        let duration = prepared.duration > 0
            ? prepared.duration
            : (request.durationHint ?? request.track.duration)
        if prepared.metadata.hasHardMetadataMismatch(title: request.track.title, artist: request.track.artist) {
            throw AlignmentError.invalidAudio("音频内嵌标题或艺人与当前歌曲不一致")
        }
        if prepared.metadata.missingEmbeddedTitleOrArtist,
           !request.allowMissingEmbeddedMetadata {
            throw AlignmentError.invalidAudio("音频缺少标题/艺人标签；请在确认预检警告后继续")
        }
        if let expectedDuration = request.durationHint,
           !AlignmentDurationValidator.isCompatible(
                audioDuration: duration,
                trackDuration: expectedDuration
           ) {
            throw AlignmentError.audioDurationMismatch(expected: expectedDuration, actual: duration)
        }

        progress?(.recognizing(0.05))
        let transcript = try await transcriptProvider.transcribe(
            pcmURL: prepared.pcmURL,
            localeIdentifier: localeIdentifier
        ) { value in
            progress?(.recognizing(value))
        }
        guard transcript.isValid else { throw AlignmentError.failed("识别结果无效") }
        progress?(.recognizing(1.0))

        progress?(.aligning(0.1))
        let enriched = LyricsLayerEnricher.enrich(lines: request.plainLines)
        let parameters = AlignmentParameters(
            recognizerID: transcript.backendID,
            localeIdentifier: localeIdentifier,
            sampleRate: Int(prepared.sampleRate.rounded()),
            channels: prepared.channels
        )
        let result = LineForcedAligner.align(
            lines: enriched,
            transcript: transcript,
            audioDuration: duration,
            parameters: parameters
        )
        progress?(.aligning(1.0))
        guard result.isComplete else {
            throw AlignmentError.insufficientEvidence(result.unresolvedLineIndices)
        }

        progress?(.scoring(0.5))
        let overall = overallConfidence(for: result.lines)
        progress?(.scoring(1.0))
        progress?(.finished)

        LyricsE2ELog.log(
            "ALIGN done model=\(id) lines=\(result.lines.count) overall=\(overall) audioHash=\(prepared.sha256.prefix(12)) segments=\(transcript.segments.count)"
        )

        return AlignmentReport(
            identity: request.identity,
            lines: result.lines,
            audioDuration: duration,
            audioSHA256: prepared.sha256,
            modelID: id,
            usedVocalsStem: false,
            overallConfidence: overall,
            sourceVersionID: request.sourceVersionID,
            sourceContentHash: request.sourceContentHash,
            parameters: parameters,
            sampleRate: Int((prepared.sourceSampleRate > 0 ? prepared.sourceSampleRate : prepared.sampleRate).rounded()),
            channels: prepared.sourceChannels > 0 ? prepared.sourceChannels : prepared.channels,
            reportEvidence: result.lines.map { $0.evidence }
        )
    }

    private func overallConfidence(for lines: [AlignedLyricLine]) -> Double {
        guard !lines.isEmpty else { return 0 }
        let confidence = lines.map(\.confidence).reduce(0, +) / Double(lines.count)
        let directRatio = Double(lines.filter { $0.evidence.kind == .directSpeech }.count) / Double(lines.count)
        return min(1, 0.75 * confidence + 0.25 * directRatio)
    }
}

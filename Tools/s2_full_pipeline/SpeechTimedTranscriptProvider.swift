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

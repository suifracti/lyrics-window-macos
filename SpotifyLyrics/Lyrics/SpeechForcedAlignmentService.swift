import Foundation
import Speech
import AVFoundation

/// V1 alignment backend: local Speech recognition tokens + deterministic line force-align.
/// Optional vocals stem path can be plugged later without changing SwiftUI.
public final class SpeechForcedAlignmentService: AlignmentService, @unchecked Sendable {
    public let id = "speech-forced-v1"
    private let localeIdentifier: String
    private let recognitionTimeoutNanoseconds: UInt64

    public init(localeIdentifier: String = "ja-JP", recognitionTimeoutNanoseconds: UInt64 = 30_000_000_000) {
        self.localeIdentifier = localeIdentifier
        self.recognitionTimeoutNanoseconds = recognitionTimeoutNanoseconds
    }

    public func align(
        _ request: AlignmentRequest,
        progress: (@Sendable (AlignmentProgress) -> Void)?
    ) async throws -> AlignmentReport {
        guard !request.plainLines.isEmpty else { throw AlignmentError.emptyLyrics }

        progress?(.preparingAudio(0.05))
        let prepared = try await AudioPCMConverter.prepare(audioURL: request.audioURL)
        defer { AudioPCMConverter.cleanup(prepared: prepared) }
        progress?(.preparingAudio(1.0))

        // Use the selected file's measured duration, but only after checking
        // that it is plausibly the current Spotify recording.
        let duration = prepared.duration > 0
            ? prepared.duration
            : (request.durationHint ?? request.track.duration)

        if let expectedDuration = request.durationHint,
           !AlignmentDurationValidator.isCompatible(
                audioDuration: duration,
                trackDuration: expectedDuration
           ) {
            throw AlignmentError.audioDurationMismatch(
                expected: expectedDuration,
                actual: duration
            )
        }

        progress?(.recognizing(0.05))
        let tokens = try await recognizeTokens(pcmURL: prepared.pcmURL) { p in
            progress?(.recognizing(p))
        }
        progress?(.recognizing(1.0))

        progress?(.aligning(0.1))
        // Ensure kana on plain lines without destroying originals.
        let enriched = LyricsLayerEnricher.enrich(lines: request.plainLines)
        let aligned = LineForcedAligner.align(
            lines: enriched,
            tokens: tokens,
            audioDuration: duration
        )
        progress?(.aligning(1.0))

        progress?(.scoring(0.5))
        let overall: Double = {
            guard !aligned.isEmpty else { return 0 }
            let sum = aligned.map(\.confidence).reduce(0, +)
            let alignedRatio = Double(aligned.filter { $0.status == .aligned }.count) / Double(aligned.count)
            return min(1, 0.7 * (sum / Double(aligned.count)) + 0.3 * alignedRatio)
        }()
        progress?(.scoring(1.0))
        progress?(.finished)

        LyricsE2ELog.log(
            "ALIGN done model=\(id) lines=\(aligned.count) overall=\(overall) audioHash=\(prepared.sha256.prefix(12)) tokens=\(tokens.count)"
        )

        return AlignmentReport(
            identity: request.identity,
            lines: aligned,
            audioDuration: duration,
            audioSHA256: prepared.sha256,
            modelID: id,
            usedVocalsStem: false,
            overallConfidence: overall
        )
    }

    private func recognizeTokens(
        pcmURL: URL,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> [LineForcedAligner.TimedToken] {
        let status = await withCheckedContinuation { (cont: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        guard status == .authorized else { throw AlignmentError.speechPermissionDenied }

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)),
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
        let transcription: SFTranscription = try await withThrowingTaskGroup(of: SFTranscription.self) { group in
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
        progress?(0.95)

        let segments = transcription.segments
        guard !segments.isEmpty else { throw AlignmentError.noSpeech }

        return segments.map { seg in
            let surface = seg.substring
            let kana = JapaneseKanaGenerator.kanaPreservingOriginal(surface) ?? surface
            let norm = LineForcedAligner.normalize(kana)
            let start = seg.timestamp
            let end = seg.timestamp + max(seg.duration, 0.02)
            return LineForcedAligner.TimedToken(
                surface: surface,
                norm: norm.isEmpty ? LineForcedAligner.normalize(surface) : norm,
                start: start,
                end: end
            )
        }.filter { !$0.norm.isEmpty }
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

    /// Bridges Swift task cancellation to the otherwise callback-only Speech
    /// recognition API and guarantees that the continuation is resumed once.
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

            if shouldCancel {
                continuation.resume(throwing: AlignmentError.cancelled)
            }
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

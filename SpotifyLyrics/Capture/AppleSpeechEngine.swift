import Foundation

/// Adapts the production Speech timed-transcript path to `LyricsSpeechEngine`.
/// Behavior matches the pre-S1 `SpeechTimedTranscriptProvider` baseline.
public struct AppleSpeechEngine: LyricsSpeechEngine {
    public let engineID: SpeechEngineID = .apple
    private let provider: SpeechTimedTranscriptProvider

    public init(localeIdentifier: String = "ja-JP") {
        self.provider = SpeechTimedTranscriptProvider(localeIdentifier: localeIdentifier)
    }

    public var isAvailable: Bool { true }

    public func transcribe(
        pcmURL: URL,
        languageHint: String?,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> SpeechEngineResult {
        let locale = (languageHint?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            ?? "ja-JP"
        let started = Date()
        do {
            let transcript = try await provider.transcribe(
                pcmURL: pcmURL,
                localeIdentifier: locale,
                progress: progress
            )
            let elapsed = Date().timeIntervalSince(started)
            let segments = transcript.segments.map {
                SpeechEngineSegment(
                    index: $0.index,
                    text: $0.text,
                    startTime: $0.startTime,
                    endTime: $0.endTime,
                    confidence: $0.confidence
                )
            }
            SCKSpikeLog.log(
                "SPEECH engine=apple pieces=\(segments.count) elapsed=\(String(format: "%.2f", elapsed))s locale=\(locale)"
            )
            return SpeechEngineResult(
                engineID: .apple,
                language: locale,
                segments: segments,
                audioDuration: transcript.audioDuration,
                diagnostics: ["backend=\(transcript.backendID)"],
                elapsedSeconds: elapsed
            )
        } catch let error as AlignmentError {
            throw mapAlignment(error)
        } catch is CancellationError {
            throw SpeechEngineError.cancelled
        } catch {
            throw SpeechEngineError.failed(error.localizedDescription)
        }
    }

    private func mapAlignment(_ error: AlignmentError) -> SpeechEngineError {
        switch error {
        case .speechPermissionDenied: return .permissionDenied
        case .recognizerUnavailable: return .unavailable("Apple Speech 不可用")
        case .noSpeech: return .failed("音频中没有可识别的人声")
        case .invalidAudio(let m): return .invalidAudio(m)
        case .cancelled: return .cancelled
        case .failed(let m) where m.contains("超时"): return .timeout
        case .failed(let m): return .failed(m)
        default: return .failed(error.localizedDescription)
        }
    }
}

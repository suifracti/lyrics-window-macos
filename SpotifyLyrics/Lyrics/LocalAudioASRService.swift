import Foundation
import Speech
import AVFoundation

public enum LocalAudioASRError: Error, Equatable {
    case speechPermissionDenied
    case recognizerUnavailable
    case noSpeech
    case failed(String)
}

/// Minimal on-device ASR draft generator for local audio files.
/// Does not read Spotify DRM streams.
public final class LocalAudioASRService: @unchecked Sendable {
    public init() {}

    public func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status)
            }
        }
    }

    /// Transcribe a local audio file in Japanese and build a machine-generated lyrics document.
    public func makeLyricsDocument(
        audioURL: URL,
        identity: TrackIdentity,
        track: Track,
        localeIdentifier: String = "ja-JP"
    ) async throws -> LyricsDocument {
        let status = await requestAuthorization()
        guard status == .authorized else { throw LocalAudioASRError.speechPermissionDenied }

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)),
              recognizer.isAvailable else {
            throw LocalAudioASRError.recognizerUnavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false
        request.taskHint = .dictation

        let transcription: SFTranscription = try await withCheckedThrowingContinuation { cont in
            var finished = false
            recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    if !finished {
                        finished = true
                        cont.resume(throwing: error)
                    }
                    return
                }
                guard let result, result.isFinal else { return }
                if !finished {
                    finished = true
                    cont.resume(returning: result.bestTranscription)
                }
            }
        }

        let lines = Self.lines(from: transcription)
        guard !lines.isEmpty else { throw LocalAudioASRError.noSpeech }

        let enriched = LyricsLayerEnricher.enrich(lines: lines)
        let hasTiming = enriched.contains { $0.timestamp > 0 }
        return LyricsDocument(
            identity: identity,
            title: track.title,
            artist: track.artist,
            album: track.album,
            duration: track.duration > 0 ? track.duration : nil,
            lines: enriched,
            isSynchronized: hasTiming,
            source: .asrMachineGenerated,
            confidence: 0.35
        )
    }

    /// Prefer speech segments (with timestamps) when available; otherwise split plain text.
    public static func lines(from transcription: SFTranscription) -> [LyricLine] {
        let segments = transcription.segments
        if segments.count >= 2 {
            // Group segments into phrase-sized lines (~1.6s gap or punctuation).
            var lines: [LyricLine] = []
            var buffer: [SFTranscriptionSegment] = []
            func flush() {
                guard !buffer.isEmpty else { return }
                let text = buffer.map(\.substring).joined()
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    let ts = buffer.first?.timestamp ?? 0
                    lines.append(LyricLine(timestamp: ts, originalText: text))
                }
                buffer.removeAll(keepingCapacity: true)
            }
            for (idx, seg) in segments.enumerated() {
                buffer.append(seg)
                let next = idx + 1 < segments.count ? segments[idx + 1] : nil
                let gap = next.map { $0.timestamp - (seg.timestamp + seg.duration) } ?? 999
                let punct = seg.substring.rangeOfCharacter(from: CharacterSet(charactersIn: "。！？!?、\n")) != nil
                if punct || gap > 0.85 || buffer.count >= 14 {
                    flush()
                }
            }
            flush()
            if !lines.isEmpty { return lines }
        }

        let text = transcription.formattedString
            .replacingOccurrences(of: "。", with: "。\n")
            .replacingOccurrences(of: "！", with: "！\n")
            .replacingOccurrences(of: "？", with: "？\n")
        return text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { LyricLine(timestamp: 0, originalText: $0) }
    }
}

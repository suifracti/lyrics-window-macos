import Foundation
import AVFoundation
import CoreMedia
import CryptoKit

/// Converts user audio to a temporary mono PCM WAV for alignment.
/// Never mutates the original file.
public enum AudioPCMConverter {
    public struct PreparedAudio: Equatable, Sendable {
        public let originalURL: URL
        public let pcmURL: URL
        public let duration: TimeInterval
        public let sha256: String
        public let sampleRate: Double
    }

    public static func prepare(
        audioURL: URL,
        workDirectory: URL = FileManager.default.temporaryDirectory
    ) async throws -> PreparedAudio {
        guard FileManager.default.isReadableFile(atPath: audioURL.path) else {
            throw AlignmentError.invalidAudio("音频不可读")
        }

        let ext = audioURL.pathExtension.lowercased()
        let allowed: Set<String> = ["mp3", "wav", "aiff", "aif", "m4a", "aac", "flac", "caf"]
        guard ext.isEmpty || allowed.contains(ext) else {
            throw AlignmentError.invalidAudio("不支持的音频类型：\(audioURL.pathExtension)")
        }

        let sha = try sha256(of: audioURL)
        let duration = try await probeDuration(audioURL)
        guard duration.isFinite, duration > 0.5 else {
            throw AlignmentError.invalidAudio("音频时长无效")
        }

        let outDir = workDirectory
            .appendingPathComponent("SpotifyLyricsAlignment", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
            let pcmURL = outDir.appendingPathComponent("audio_16k_mono.wav")

            // Prefer ffmpeg for broad format support; fall back to AVFoundation.
            if let ffmpeg = resolveFFmpeg() {
                try runFFmpeg(ffmpeg, input: audioURL, output: pcmURL)
            } else {
                try await convertWithAVFoundation(input: audioURL, output: pcmURL)
            }

            guard FileManager.default.fileExists(atPath: pcmURL.path) else {
                throw AlignmentError.invalidAudio("PCM 转换失败")
            }

            return PreparedAudio(
                originalURL: audioURL,
                pcmURL: pcmURL,
                duration: duration,
                sha256: sha,
                sampleRate: 16_000
            )
        } catch {
            // Also remove partial output when conversion or validation fails;
            // the caller only receives a PreparedAudio after a complete run.
            try? FileManager.default.removeItem(at: outDir)
            throw error
        }
    }

    public static func cleanup(prepared: PreparedAudio) {
        let dir = prepared.pcmURL.deletingLastPathComponent()
        try? FileManager.default.removeItem(at: dir)
    }

    private static func sha256(of url: URL) throws -> String {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func probeDuration(_ url: URL) async throws -> TimeInterval {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        return CMTimeGetSeconds(duration)
    }

    private static func resolveFFmpeg() -> URL? {
        let candidates = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    private static func runFFmpeg(_ ffmpeg: URL, input: URL, output: URL) throws {
        let process = Process()
        process.executableURL = ffmpeg
        process.arguments = [
            "-y", "-i", input.path,
            "-ac", "1",
            "-ar", "16000",
            "-c:a", "pcm_s16le",
            output.path
        ]
        let err = Pipe()
        process.standardError = err
        process.standardOutput = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw AlignmentError.invalidAudio("ffmpeg 失败: \(msg.suffix(200))")
        }
    }

    private static func convertWithAVFoundation(input: URL, output: URL) async throws {
        let audioFile = try AVAudioFile(forReading: input)
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true)!
        let converter = AVAudioConverter(from: audioFile.processingFormat, to: format)!
        let outFile = try AVAudioFile(forWriting: output, settings: format.settings)
        let inputCapacity: AVAudioFrameCount = 4096
        let inputBuffer = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat, frameCapacity: inputCapacity)!
        var done = false
        while !done {
            try audioFile.read(into: inputBuffer)
            if inputBuffer.frameLength == 0 {
                done = true
                break
            }
            let outBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8192)!
            var error: NSError?
            let status = converter.convert(to: outBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return inputBuffer
            }
            if status == .error {
                throw AlignmentError.invalidAudio(error?.localizedDescription ?? "AVAudioConverter error")
            }
            if outBuffer.frameLength > 0 {
                try outFile.write(from: outBuffer)
            }
            if status == .endOfStream { done = true }
        }
    }
}

import Foundation
import AVFoundation
import CoreMedia
import CryptoKit

/// Converts user audio to a temporary mono PCM WAV for alignment.
///
/// The selected source is read-only. Hashing/probing and conversion happen
/// away from MainActor, cancellation terminates an in-flight ffmpeg process,
/// and every temporary directory is removed by the caller or on failure.
public enum AudioPCMConverter {
    public struct PreparedAudio: Equatable, Sendable {
        public let originalURL: URL
        public let pcmURL: URL
        public let duration: TimeInterval
        public let sha256: String
        /// The normalized PCM format consumed by recognition.
        public let sampleRate: Double
        public let channels: Int
        /// The source-file format requested for provenance.
        public let sourceSampleRate: Double
        public let sourceChannels: Int
        public let metadata: AudioInputMetadata

        public init(
            originalURL: URL,
            pcmURL: URL,
            duration: TimeInterval,
            sha256: String,
            sampleRate: Double,
            channels: Int = 1,
            sourceSampleRate: Double = 0,
            sourceChannels: Int = 0,
            metadata: AudioInputMetadata? = nil
        ) {
            self.originalURL = originalURL
            self.pcmURL = pcmURL
            self.duration = duration
            self.sha256 = sha256
            self.sampleRate = sampleRate
            self.channels = channels
            self.sourceSampleRate = sourceSampleRate
            self.sourceChannels = sourceChannels
            self.metadata = metadata ?? AudioInputMetadata(
                duration: duration,
                sampleRate: sourceSampleRate,
                channels: sourceChannels,
                fileExtension: originalURL.pathExtension.lowercased(),
                sha256: sha256,
                fileSize: 0
            )
        }
    }

    private struct FileSignature: Equatable, Sendable {
        let size: Int64
        let modificationDate: Date?
        let sha256: String
        let metadata: AudioInputMetadata
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
        guard allowed.contains(ext) else {
            throw AlignmentError.invalidAudio("不支持的音频类型：\(audioURL.pathExtension)")
        }

        let signatureBefore = try await Task.detached(priority: .utility) {
            try inspect(audioURL: audioURL)
        }.value
        try Task.checkCancellation()
        guard signatureBefore.metadata.duration.isFinite, signatureBefore.metadata.duration > 0.5 else {
            throw AlignmentError.invalidAudio("音频时长无效")
        }

        let outDir = workDirectory
            .appendingPathComponent("SpotifyLyricsAlignment", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
            let pcmURL = outDir.appendingPathComponent("audio_16k_mono.wav")

            if let ffmpeg = resolveFFmpeg() {
                try await runFFmpeg(ffmpeg, input: audioURL, output: pcmURL)
            } else {
                let conversionTask = Task.detached(priority: .utility) {
                    try convertWithAVFoundation(input: audioURL, output: pcmURL)
                }
                try await withTaskCancellationHandler(operation: {
                    try await conversionTask.value
                }, onCancel: {
                    conversionTask.cancel()
                })
            }
            try Task.checkCancellation()

            guard FileManager.default.fileExists(atPath: pcmURL.path) else {
                throw AlignmentError.invalidAudio("PCM 转换失败")
            }
            let signatureAfter = try await Task.detached(priority: .utility) {
                try fileSignature(audioURL)
            }.value
            guard signatureBefore == signatureAfter else {
                throw AlignmentError.invalidAudio("原始音频在转换期间发生变化，已取消排轴")
            }

            return PreparedAudio(
                originalURL: audioURL,
                pcmURL: pcmURL,
                duration: signatureBefore.metadata.duration,
                sha256: signatureBefore.metadata.sha256,
                sampleRate: 16_000,
                channels: 1,
                sourceSampleRate: signatureBefore.metadata.sampleRate,
                sourceChannels: signatureBefore.metadata.channels,
                metadata: signatureBefore.metadata
            )
        } catch is CancellationError {
            try? FileManager.default.removeItem(at: outDir)
            throw AlignmentError.cancelled
        } catch let error as AlignmentError {
            try? FileManager.default.removeItem(at: outDir)
            throw error
        } catch {
            try? FileManager.default.removeItem(at: outDir)
            throw AlignmentError.invalidAudio(error.localizedDescription)
        }
    }

    /// Measures the selected source without creating a PCM copy.  The result
    /// is intentionally value-only; the URL remains owned by the current
    /// alignment task and is never part of provenance.
    public static func inspectMetadata(audioURL: URL) async throws -> AudioInputMetadata {
        guard FileManager.default.isReadableFile(atPath: audioURL.path) else {
            throw AlignmentError.invalidAudio("音频不可读")
        }
        let ext = audioURL.pathExtension.lowercased()
        let allowed: Set<String> = ["mp3", "wav", "aiff", "aif", "m4a", "aac", "flac", "caf"]
        guard allowed.contains(ext) else {
            throw AlignmentError.invalidAudio("不支持的音频类型：\(audioURL.pathExtension)")
        }
        let metadata = try await Task.detached(priority: .utility) {
            try fileSignature(audioURL).metadata
        }.value
        try Task.checkCancellation()
        guard metadata.duration.isFinite, metadata.duration > 0.5 else {
            throw AlignmentError.invalidAudio("音频时长无效")
        }
        return metadata
    }

    public static func cleanup(prepared: PreparedAudio) {
        let dir = prepared.pcmURL.deletingLastPathComponent()
        try? FileManager.default.removeItem(at: dir)
    }

    private static func inspect(audioURL: URL) throws -> FileSignature {
        let signature = try fileSignature(audioURL)
        return signature
    }

    private static func fileSignature(_ url: URL) throws -> FileSignature {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        guard size > 0 else { throw AlignmentError.invalidAudio("音频文件为空") }
        let modified = attributes[.modificationDate] as? Date
        let metadata = try probeMetadata(url)
        let digest = try streamingSHA256(of: url)
        let measured = AudioInputMetadata(
            duration: metadata.duration,
            sampleRate: metadata.sampleRate,
            channels: metadata.channels,
            fileExtension: url.pathExtension.lowercased(),
            sha256: digest,
            fileSize: size,
            embeddedTitle: metadata.title,
            embeddedArtist: metadata.artist
        )
        return FileSignature(
            size: size,
            modificationDate: modified,
            sha256: digest,
            metadata: measured
        )
    }

    private struct ProbedMetadata: Sendable {
        let duration: TimeInterval
        let sampleRate: Double
        let channels: Int
        let title: String?
        let artist: String?
    }

    private static func probeMetadata(_ url: URL) throws -> ProbedMetadata {
        let asset = AVURLAsset(url: url)
        let duration = CMTimeGetSeconds(asset.duration)
        guard duration.isFinite, duration > 0 else {
            throw AlignmentError.invalidAudio("无法读取音频时长")
        }

        var sampleRate = 0.0
        var channels = 0
        if let audioFile = try? AVAudioFile(forReading: url) {
            sampleRate = audioFile.processingFormat.sampleRate
            channels = Int(audioFile.processingFormat.channelCount)
        }
        let title = AVMetadataItem.metadataItems(
            from: asset.commonMetadata,
            filteredByIdentifier: .commonIdentifierTitle
        ).first?.stringValue
        let artist = AVMetadataItem.metadataItems(
            from: asset.commonMetadata,
            filteredByIdentifier: .commonIdentifierArtist
        ).first?.stringValue
        return ProbedMetadata(
            duration: duration,
            sampleRate: sampleRate,
            channels: channels,
            title: title,
            artist: artist
        )
    }

    private static func streamingSHA256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func resolveFFmpeg() -> URL? {
        let candidates = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg"
        ]
        return candidates
            .map(URL.init(fileURLWithPath:))
            .first(where: { FileManager.default.isExecutableFile(atPath: $0.path) })
    }

    private final class ProcessCancellationState: @unchecked Sendable {
        private let lock = NSLock()
        private var process: Process?
        private var cancelled = false

        func install(_ process: Process) {
            lock.lock()
            self.process = process
            let shouldCancel = cancelled
            lock.unlock()
            if shouldCancel { process.terminate() }
        }

        func cancel() {
            lock.lock()
            cancelled = true
            let process = self.process
            lock.unlock()
            process?.terminate()
        }

        var wasCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return cancelled
        }
    }

    private static func runFFmpeg(_ ffmpeg: URL, input: URL, output: URL) async throws {
        let state = ProcessCancellationState()
        do {
            try await withTaskCancellationHandler(operation: {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    DispatchQueue.global(qos: .utility).async {
                        do {
                            let process = Process()
                            process.executableURL = ffmpeg
                            process.arguments = [
                                "-nostdin", "-y", "-i", input.path,
                                "-ac", "1", "-ar", "16000", "-c:a", "pcm_s16le",
                                output.path
                            ]
                            let errorPipe = Pipe()
                            process.standardError = errorPipe
                            process.standardOutput = Pipe()
                            try process.run()
                            state.install(process)
                            process.waitUntilExit()
                            if state.wasCancelled {
                                continuation.resume(throwing: CancellationError())
                                return
                            }
                            guard process.terminationStatus == 0 else {
                                let message = String(
                                    data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                                    encoding: .utf8
                                ) ?? ""
                                continuation.resume(throwing: AlignmentError.invalidAudio("ffmpeg 失败：\(message.suffix(200))"))
                                return
                            }
                                continuation.resume(returning: ())
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                }
            }, onCancel: {
                state.cancel()
            })
        } catch is CancellationError {
            throw AlignmentError.cancelled
        }
    }

    private static func convertWithAVFoundation(input: URL, output: URL) throws {
        let audioFile = try AVAudioFile(forReading: input)
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true)!
        guard let converter = AVAudioConverter(from: audioFile.processingFormat, to: format) else {
            throw AlignmentError.invalidAudio("无法创建 PCM 转换器")
        }
        let outFile = try AVAudioFile(forWriting: output, settings: format.settings)
        let inputCapacity: AVAudioFrameCount = 4096
        let inputBuffer = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat, frameCapacity: inputCapacity)!
        var done = false
        while !done {
            try Task.checkCancellation()
            try audioFile.read(into: inputBuffer)
            if inputBuffer.frameLength == 0 { break }
            let outBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8192)!
            var conversionError: NSError?
            let status = converter.convert(to: outBuffer, error: &conversionError) { _, outputStatus in
                outputStatus.pointee = .haveData
                return inputBuffer
            }
            if status == .error {
                throw AlignmentError.invalidAudio(conversionError?.localizedDescription ?? "AVAudioConverter error")
            }
            if outBuffer.frameLength > 0 { try outFile.write(from: outBuffer) }
            if status == .endOfStream { done = true }
        }
    }
}

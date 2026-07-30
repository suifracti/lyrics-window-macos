import Foundation

enum AlignmentError: Error {
    case invalidAudio(String)
    case cancelled
}

@main
struct AudioPCMContract {
    static func main() async {
        let sourceURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TEST_AUDIO_PATH"]!)
        let workDirectory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TEST_WORK_DIR"]!, isDirectory: true)
        let beforeData = try! Data(contentsOf: sourceURL)
        let beforeAttributes = try! FileManager.default.attributesOfItem(atPath: sourceURL.path)

        do {
            let inspected = try await AudioPCMConverter.inspectMetadata(audioURL: sourceURL)
            precondition(inspected.duration > 0.5)
            precondition(inspected.sha256.count == 64)
            precondition(inspected.missingEmbeddedTitleOrArtist)
            let prepared = try await AudioPCMConverter.prepare(audioURL: sourceURL, workDirectory: workDirectory)
            precondition(prepared.duration > 0.5)
            precondition(prepared.sampleRate == 16_000)
            precondition(prepared.channels == 1)
            precondition(prepared.sha256.count == 64)
            precondition(prepared.metadata.sha256 == prepared.sha256)
            precondition(prepared.metadata.fileSize == Int64(beforeData.count))
            precondition(FileManager.default.fileExists(atPath: prepared.pcmURL.path))

            let afterData = try! Data(contentsOf: sourceURL)
            let afterAttributes = try! FileManager.default.attributesOfItem(atPath: sourceURL.path)
            precondition(beforeData == afterData, "source audio bytes changed")
            precondition(beforeAttributes[.modificationDate] as? Date == afterAttributes[.modificationDate] as? Date)

            let tempDirectory = prepared.pcmURL.deletingLastPathComponent()
            AudioPCMConverter.cleanup(prepared: prepared)
            precondition(!FileManager.default.fileExists(atPath: tempDirectory.path))
        } catch {
            fatalError("valid TEST WAV rejected: \(error)")
        }

        let invalidURL = workDirectory.appendingPathComponent("invalid.txt")
        try! Data("not audio".utf8).write(to: invalidURL)
        do {
            _ = try await AudioPCMConverter.prepare(audioURL: invalidURL, workDirectory: workDirectory)
            fatalError("invalid extension accepted")
        } catch is AlignmentError {
            // expected
        } catch {
            fatalError("wrong invalid-audio error: \(error)")
        }
        try? FileManager.default.removeItem(at: invalidURL)
        try? FileManager.default.removeItem(at: workDirectory)
        print("audio PCM contract passed (TEST WAV; source unchanged; temp cleaned)")
    }
}

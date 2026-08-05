import Foundation
import CoreMedia
import AVFoundation

/// Thread-safe segment PCM writer.
/// Accumulates mono Float samples at the capture sample rate, then writes a
/// 16-bit mono WAV and optionally downsamples to 16 kHz for Speech.
public final class SegmentWAVWriter: @unchecked Sendable {
    public let fileURL: URL
    private let lock = NSLock()
    private var monoFloat: [Float] = []
    private var finished = false
    private(set) public var framesWritten: Int = 0
    private(set) public var inputSampleRate: Double = 48_000
    private(set) public var inputChannels: Int = 2

    public init(directory: URL, segmentID: UUID) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("seg-\(segmentID.uuidString.prefix(8))-mono.wav")
    }

    public func append(_ sampleBuffer: CMSampleBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        guard CMSampleBufferIsValid(sampleBuffer),
              let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else {
            return
        }
        let asbd = asbdPtr.pointee
        if asbd.mSampleRate > 0 { inputSampleRate = asbd.mSampleRate }
        if asbd.mChannelsPerFrame > 0 { inputChannels = Int(asbd.mChannelsPerFrame) }

        var bufferListSize = 0
        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &bufferListSize,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: nil
        )
        guard bufferListSize > 0 else { return }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: bufferListSize, alignment: MemoryLayout<Int>.alignment)
        defer { raw.deallocate() }
        let ablPtr = raw.bindMemory(to: AudioBufferList.self, capacity: 1)
        var blockOut: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: ablPtr,
            bufferListSize: bufferListSize,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockOut
        )
        guard status == noErr else { return }
        _ = blockOut

        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frameCount > 0 else { return }
        let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let abl = UnsafeMutableAudioBufferListPointer(ablPtr)
        let channelCount = max(1, Int(asbd.mChannelsPerFrame))

        var mono = [Float](repeating: 0, count: frameCount)
        if isFloat {
            if asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0 {
                for ch in 0..<min(channelCount, abl.count) {
                    guard let data = abl[ch].mData else { continue }
                    let ptr = data.assumingMemoryBound(to: Float.self)
                    for i in 0..<frameCount {
                        mono[i] += ptr[i]
                    }
                }
                let inv = 1.0 / Float(min(channelCount, abl.count))
                for i in 0..<frameCount { mono[i] *= inv }
            } else if let data = abl.first?.mData {
                let ptr = data.assumingMemoryBound(to: Float.self)
                for i in 0..<frameCount {
                    var sum: Float = 0
                    for ch in 0..<channelCount {
                        sum += ptr[i * channelCount + ch]
                    }
                    mono[i] = sum / Float(channelCount)
                }
            }
        } else {
            if let data = abl.first?.mData {
                let ptr = data.assumingMemoryBound(to: Int16.self)
                let interleaved = (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) == 0
                if interleaved {
                    for i in 0..<frameCount {
                        var sum: Float = 0
                        for ch in 0..<channelCount {
                            sum += Float(ptr[i * channelCount + ch]) / Float(Int16.max)
                        }
                        mono[i] = sum / Float(channelCount)
                    }
                } else {
                    for ch in 0..<min(channelCount, abl.count) {
                        guard let chData = abl[ch].mData else { continue }
                        let chPtr = chData.assumingMemoryBound(to: Int16.self)
                        for i in 0..<frameCount {
                            mono[i] += Float(chPtr[i]) / Float(Int16.max)
                        }
                    }
                    let inv = 1.0 / Float(min(channelCount, abl.count))
                    for i in 0..<frameCount { mono[i] *= inv }
                }
            }
        }
        monoFloat.append(contentsOf: mono)
        framesWritten += frameCount
    }

    /// Writes 16 kHz mono Int16 WAV for Speech. Returns nil if empty.
    public func finish() throws -> URL? {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else {
            return FileManager.default.fileExists(atPath: fileURL.path) ? fileURL : nil
        }
        finished = true
        guard framesWritten > 0, !monoFloat.isEmpty else { return nil }

        let sourceRate = max(1, inputSampleRate)
        let targetRate = 16_000.0
        let ratio = sourceRate / targetRate
        let outCount = max(1, Int(Double(monoFloat.count) / ratio))
        var int16 = [Int16](repeating: 0, count: outCount)
        for i in 0..<outCount {
            let srcIndex = min(monoFloat.count - 1, Int(Double(i) * ratio))
            let clipped = max(-1.0, min(1.0, monoFloat[srcIndex]))
            int16[i] = Int16(clipped * Float(Int16.max))
        }
        monoFloat.removeAll(keepingCapacity: false)

        var data = Data()
        let dataSize = UInt32(outCount * 2)
        func appendU32(_ v: UInt32) {
            var le = v.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }
        func appendU16(_ v: UInt16) {
            var le = v.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: Array("RIFF".utf8))
        appendU32(36 + dataSize)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        appendU32(16)
        appendU16(1)
        appendU16(1)
        appendU32(16_000)
        appendU32(16_000 * 2)
        appendU16(2)
        appendU16(16)
        data.append(contentsOf: Array("data".utf8))
        appendU32(dataSize)
        int16.withUnsafeBytes { data.append(contentsOf: $0) }
        try data.write(to: fileURL, options: .atomic)
        framesWritten = outCount
        inputSampleRate = 16_000
        inputChannels = 1
        return fileURL
    }

    public func abandon() {
        lock.lock()
        finished = true
        monoFloat.removeAll(keepingCapacity: false)
        lock.unlock()
        try? FileManager.default.removeItem(at: fileURL)
    }
}

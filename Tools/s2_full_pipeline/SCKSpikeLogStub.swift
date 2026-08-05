#if DEBUG
import Foundation

/// Minimal log sink for offline S2 harness (avoids linking ScreenCaptureKit spike).
enum SCKSpikeLog {
    static func reset() {}
    static func log(_ message: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        fputs("[\(ts)] \(message)\n", stderr)
    }
}
#endif

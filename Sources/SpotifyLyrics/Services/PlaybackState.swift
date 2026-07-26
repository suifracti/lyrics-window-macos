import Foundation
import Combine

@MainActor
public class PlaybackState: ObservableObject {
    @Published public var currentTrack: Track = MockData.sampleTrack
    @Published public var lyrics: [LyricLine] = MockData.sampleLyrics
    @Published public var currentTime: TimeInterval = 0.0
    @Published public var isPlaying: Bool = false
    @Published public var currentMode: LyricsDisplayMode = .mainWindow
    @Published public var preferences: DisplayPreferences = DisplayPreferences()
    
    // Auxiliary display states
    @Published public var showFloatingWindow: Bool = false
    @Published public var showCapsulePlayer: Bool = false
    @Published public var showFullScreen: Bool = false

    private var timer: Timer?

    public init() {}

    public func togglePlayPause() {
        isPlaying.toggle()
        if isPlaying {
            startTimer()
        } else {
            stopTimer()
        }
    }

    public func seek(to time: TimeInterval) {
        currentTime = max(0, min(time, currentTrack.duration))
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.isPlaying else { return }
                self.currentTime += 0.2
                if self.currentTime >= self.currentTrack.duration {
                    self.currentTime = 0
                    self.isPlaying = false
                    self.stopTimer()
                }
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    public var currentLineIndex: Int? {
        guard !lyrics.isEmpty else { return nil }
        let matched = lyrics.enumerated().filter { $0.element.timestamp <= currentTime }
        return matched.last?.offset
    }
}

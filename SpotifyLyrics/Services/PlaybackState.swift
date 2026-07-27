import Combine
import Foundation

@MainActor
public final class PlaybackState: ObservableObject {
    @Published public var currentTrack: Track = MockData.sampleTrack
    @Published public var lyrics: [LyricLine] = MockData.sampleLyrics
    @Published public private(set) var currentTime: TimeInterval = 0
    @Published public private(set) var isPlaying = false
    @Published public var currentMode: LyricsDisplayMode = .mainWindow
    @Published public var preferences: DisplayPreferences = DisplayPreferences()
    @Published public private(set) var providerStatus: PlaybackProviderState = .connecting

    // Auxiliary display states remain available to the existing window manager.
    @Published public var showFloatingWindow = false
    @Published public var showCapsulePlayer = false
    @Published public var showFullScreen = false

    private let provider: PlaybackProvider
    private let mockProvider: MockPlaybackProvider
    private var timer: Timer?
    private var isProviderStarted = false
    private var isRefreshingProvider = false
    private var providerRefreshTask: Task<Void, Never>?
    private var playbackAnchorPosition: TimeInterval = 0
    private var playbackAnchorDate = Date()
    private var lastProviderRefreshDate = Date.distantPast
    private let tickInterval: TimeInterval = 0.2
    private let calibrationInterval: TimeInterval = 2.0

    public init(provider: PlaybackProvider? = nil) {
        self.provider = provider ?? SpotifyDesktopProvider()
        self.mockProvider = MockPlaybackProvider()
    }

    deinit {
        timer?.invalidate()
        providerRefreshTask?.cancel()
    }

    public var canControlSpotify: Bool {
        providerStatus.isReady
    }

    public var isUsingMockPreview: Bool {
        !providerStatus.isReady
    }

    public var providerStatusMessage: String {
        guard isUsingMockPreview, providerStatus != .mockPreview else {
            return providerStatus.userFacingMessage
        }
        return "\(providerStatus.userFacingMessage) · 正在使用 Mock 预览"
    }

    public func startProvider() {
        guard !isProviderStarted else { return }
        isProviderStarted = true
        startTimer()
        providerRefreshTask = Task { @MainActor [weak self] in
            await self?.refreshProvider()
        }
    }

    public func reconnectSpotify() {
        providerStatus = .connecting
        providerRefreshTask?.cancel()
        providerRefreshTask = Task { @MainActor [weak self] in
            await self?.refreshProvider()
        }
    }

    public func togglePlayPause() {
        if canControlSpotify {
            let shouldPlay = !isPlaying
            isPlaying = shouldPlay
            resetPlaybackAnchor(to: currentTime)
            providerRefreshTask = Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    if shouldPlay {
                        try await self.provider.play()
                    } else {
                        try await self.provider.pause()
                    }
                    await self.refreshProvider()
                } catch {
                    self.handleProviderError(error)
                }
            }
        } else {
            isPlaying.toggle()
            resetPlaybackAnchor(to: currentTime)
        }
    }

    public func previousTrack() {
        guard canControlSpotify else { return }
        runProviderCommand { provider in
            try await provider.previous()
        }
    }

    public func nextTrack() {
        guard canControlSpotify else { return }
        runProviderCommand { provider in
            try await provider.next()
        }
    }

    public func seek(to time: TimeInterval) {
        let clampedTime = max(0, min(time, currentTrack.duration))
        resetPlaybackAnchor(to: clampedTime)

        guard canControlSpotify else { return }
        runProviderCommand { provider in
            try await provider.seek(to: clampedTime)
        }
    }

    public var currentLineIndex: Int? {
        guard !lyrics.isEmpty else { return nil }
        let matched = lyrics.enumerated().filter { $0.element.timestamp <= currentTime }
        return matched.last?.offset
    }

    private func refreshProvider() async {
        guard !isRefreshingProvider else { return }
        isRefreshingProvider = true
        let snapshot = await provider.refresh()
        synchronize(with: snapshot)
        isRefreshingProvider = false
        lastProviderRefreshDate = Date()
    }

    private func synchronize(with snapshot: PlaybackSnapshot) {
        providerStatus = snapshot.status

        guard snapshot.status.isReady, let providerTrack = snapshot.track else {
            switchToMockFallback()
            return
        }

        let hasChangedTrack = currentTrack.id != providerTrack.id
        if hasChangedTrack {
            currentTrack = Track(providerTrack: providerTrack)
        } else if currentTrack.artworkURL != providerTrack.artworkURL || currentTrack.title != providerTrack.title {
            currentTrack = Track(providerTrack: providerTrack)
        }

        isPlaying = snapshot.isPlaying
        resetPlaybackAnchor(to: snapshot.position)
    }

    private func switchToMockFallback() {
        if currentTrack.id != MockData.sampleTrack.id {
            currentTrack = MockData.sampleTrack
        }
        isPlaying = false
        currentTime = min(currentTime, currentTrack.duration)
        resetPlaybackAnchor(to: currentTime)
        _ = mockProvider
    }

    private func runProviderCommand(_ command: @escaping @MainActor (PlaybackProvider) async throws -> Void) {
        providerRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await command(self.provider)
                // Spotify applies transport commands asynchronously. Give its
                // player a short moment to publish the new track/position before
                // the post-command calibration read.
                try? await Task.sleep(nanoseconds: 250_000_000)
                await self.refreshProvider()
            } catch {
                self.handleProviderError(error)
            }
        }
    }

    private func handleProviderError(_ error: Error) {
        if let providerError = error as? PlaybackProviderError {
            switch providerError {
            case .notInstalled:
                providerStatus = .notInstalled
            case .notRunning:
                providerStatus = .notRunning
            case .permissionDenied:
                providerStatus = .permissionDenied
            case .noTrack:
                providerStatus = .noTrack
            case .commandFailed(let message):
                providerStatus = .unavailable(message)
            }
        } else {
            providerStatus = .unavailable(error.localizedDescription)
        }
        switchToMockFallback()
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
    }

    private func tick() {
        if providerStatus.isReady {
            if isPlaying {
                let elapsed = Date().timeIntervalSince(playbackAnchorDate)
                currentTime = min(currentTrack.duration, playbackAnchorPosition + elapsed)
                if currentTime >= currentTrack.duration {
                    isPlaying = false
                    resetPlaybackAnchor(to: currentTrack.duration)
                }
            } else {
                currentTime = playbackAnchorPosition
            }
        } else if isPlaying {
            currentTime = min(currentTrack.duration, currentTime + tickInterval)
            if currentTime >= currentTrack.duration {
                isPlaying = false
                resetPlaybackAnchor(to: currentTrack.duration)
            }
        }

        let shouldRetryConnection: Bool
        switch providerStatus {
        case .permissionDenied, .mockPreview:
            shouldRetryConnection = false
        default:
            shouldRetryConnection = true
        }

        if shouldRetryConnection,
           Date().timeIntervalSince(lastProviderRefreshDate) >= calibrationInterval,
           !isRefreshingProvider {
            providerRefreshTask = Task { @MainActor [weak self] in
                await self?.refreshProvider()
            }
        }
    }

    private func resetPlaybackAnchor(to position: TimeInterval) {
        playbackAnchorPosition = max(0, min(position, currentTrack.duration))
        playbackAnchorDate = Date()
        currentTime = playbackAnchorPosition
    }
}

private extension Track {
    init(providerTrack: ProviderTrack) {
        self.init(
            id: providerTrack.id,
            title: providerTrack.title,
            artist: providerTrack.artist,
            album: providerTrack.album,
            duration: providerTrack.duration,
            artworkName: "music.note",
            spotifyId: providerTrack.id,
            artworkURL: providerTrack.artworkURL,
            spotifyURL: providerTrack.spotifyURL
        )
    }
}

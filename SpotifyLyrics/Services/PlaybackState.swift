import Combine
import Foundation

@MainActor
public final class PlaybackState: ObservableObject {
    @Published public private(set) var currentTrack: Track = .emptyPlaybackPlaceholder
    @Published public private(set) var currentTime: TimeInterval = 0
    @Published public private(set) var isPlaying = false
    @Published public var currentMode: LyricsDisplayMode = .mainWindow
    @Published public var preferences: DisplayPreferences = DisplayPreferences()
    @Published public private(set) var providerStatus: PlaybackProviderState = .connecting
    @Published public private(set) var isMockPreviewMode = false
    @Published public private(set) var hasLiveTrack = false

    // Auxiliary display states remain available to the existing window manager.
    @Published public var showFloatingWindow = false
    @Published public var showCapsulePlayer = false
    @Published public var showFullScreen = false

    private let provider: PlaybackProvider
    private let lyricsSession: LyricsSessionController
    private var lyricsSessionCancellable: AnyCancellable?
    private var timer: Timer?
    private var isProviderStarted = false
    private var isRefreshingProvider = false
    private var providerRefreshGeneration: UInt64 = 0
    private var refreshRequestedWhileBusy = false
    private var providerRefreshTask: Task<Void, Never>?
    private var playbackAnchorPosition: TimeInterval = 0
    private var playbackAnchorDate = Date()
    private var lastProviderRefreshDate = Date.distantPast
    private let tickInterval: TimeInterval = 0.2
    private let calibrationInterval: TimeInterval = 2.0

    public init(
        provider: PlaybackProvider? = nil,
        lyricsProvider: LyricsProvider? = nil
    ) {
        self.provider = provider ?? SpotifyDesktopProvider()
        self.lyricsSession = LyricsSessionController(
            provider: lyricsProvider ?? CompositeLyricsProvider(
                providers: [
                    LocalLyricsProvider(),
                    LRCLIBLyricsProvider()
                ]
            )
        )
        self.lyricsSessionCancellable = nil
        self.lyricsSessionCancellable = self.lyricsSession.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    deinit {
        timer?.invalidate()
        providerRefreshTask?.cancel()
        lyricsSessionCancellable?.cancel()
    }

    public var lyrics: [LyricLine] { lyricsSession.lyrics }
    public var lyricsState: LyricsLoadState { lyricsSession.state }
    public var lyricsAreSynchronized: Bool { lyricsSession.isSynchronized }
    public var lyricsSessionRevision: UInt64 { lyricsSession.revision }
    public var currentTrackIdentity: TrackIdentity? {
        guard hasLiveTrack, !isMockPreviewMode else { return nil }
        return lyricsSession.activeIdentity
    }

    public var canControlSpotify: Bool {
        providerStatus.isReady && hasLiveTrack && !isMockPreviewMode
    }

    /// True only after the user explicitly enters Mock Preview.
    public var isUsingMockPreview: Bool { isMockPreviewMode }

    public var canInteractWithPlayback: Bool {
        canControlSpotify || isMockPreviewMode
    }

    public var providerStatusMessage: String {
        if isMockPreviewMode {
            return "Mock Preview"
        }
        if providerStatus.isReady, hasLiveTrack {
            return providerStatus.userFacingMessage
        }
        return "\(providerStatus.userFacingMessage) · 未进入 Mock Preview"
    }

    public var lyricsStatusMessage: String {
        lyricsState.userFacingMessage
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
        guard !isMockPreviewMode else { return }
        providerRefreshGeneration &+= 1
        refreshRequestedWhileBusy = true
        providerStatus = .connecting
        clearLiveTrackIfNeeded()
        providerRefreshTask?.cancel()
        providerRefreshTask = Task { @MainActor [weak self] in
            await self?.refreshProvider()
        }
    }

    public func enterMockPreview() {
        providerRefreshGeneration &+= 1
        refreshRequestedWhileBusy = false
        providerRefreshTask?.cancel()
        isMockPreviewMode = true
        hasLiveTrack = false
        providerStatus = .mockPreview
        currentTrack = MockData.sampleTrack
        lyricsSession.enterMockPreview(lines: MockData.sampleLyrics)
        isPlaying = false
        resetPlaybackAnchor(to: 0)
    }

    public func exitMockPreview() {
        providerRefreshGeneration &+= 1
        refreshRequestedWhileBusy = true
        isMockPreviewMode = false
        hasLiveTrack = false
        currentTrack = .emptyPlaybackPlaceholder
        lyricsSession.clear()
        isPlaying = false
        resetPlaybackAnchor(to: 0)
        providerStatus = .connecting
        providerRefreshTask?.cancel()
        providerRefreshTask = Task { @MainActor [weak self] in
            await self?.refreshProvider()
        }
    }

    public func togglePlayPause() {
        if isMockPreviewMode {
            isPlaying.toggle()
            resetPlaybackAnchor(to: currentTime)
            return
        }

        guard canControlSpotify else { return }
        invalidateProviderRefresh()
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
        guard canInteractWithPlayback else { return }
        let clampedTime = max(0, min(time, currentTrack.duration))
        resetPlaybackAnchor(to: clampedTime)

        guard canControlSpotify else { return }
        invalidateProviderRefresh()
        runProviderCommand { provider in
            try await provider.seek(to: clampedTime)
        }
    }

    public func retryLyrics() {
        guard hasLiveTrack, let identity = currentTrackIdentity else { return }
        lyricsSession.retry(track: currentTrack, identity: identity)
    }

    public func adoptLyricsCandidate(_ candidate: LyricsCandidate) {
        lyricsSession.adopt(candidate: candidate)
    }

    public var currentLineIndex: Int? {
        LyricsTimeline.activeLineIndex(
            lines: lyrics,
            time: currentTime,
            isSynchronized: lyricsAreSynchronized
        )
    }

    private func refreshProvider() async {
        guard !isMockPreviewMode else { return }
        guard !isRefreshingProvider else {
            refreshRequestedWhileBusy = true
            return
        }

        let generation = providerRefreshGeneration
        isRefreshingProvider = true
        refreshRequestedWhileBusy = false
        let snapshot = await provider.refresh()
        isRefreshingProvider = false

        let shouldApply = !Task.isCancelled && generation == providerRefreshGeneration && !isMockPreviewMode
        if shouldApply {
            synchronize(with: snapshot)
            lastProviderRefreshDate = Date()
        }

        let shouldQueueRefresh = refreshRequestedWhileBusy
        refreshRequestedWhileBusy = false
        if shouldQueueRefresh && !isMockPreviewMode {
            providerRefreshTask = Task { @MainActor [weak self] in
                await self?.refreshProvider()
            }
        }
    }

    private func synchronize(with snapshot: PlaybackSnapshot) {
        // A refresh that was already in flight when Mock Preview was entered
        // must not be allowed to resurrect a real Spotify session.
        guard !isMockPreviewMode else { return }
        providerStatus = snapshot.status

        guard snapshot.status.isReady, let providerTrack = snapshot.track else {
            clearLiveTrackIfNeeded()
            return
        }

        let nextTrack = Track(providerTrack: providerTrack)
        let nextIdentity = TrackIdentity(track: nextTrack)
        let identityChanged = !hasLiveTrack || lyricsSession.activeIdentity != nextIdentity

        if identityChanged {
            hasLiveTrack = true
            isMockPreviewMode = false
            currentTrack = nextTrack
            lyricsSession.begin(track: nextTrack, identity: nextIdentity)
        } else if currentTrack != nextTrack {
            // Metadata/artwork may change without a lyric identity change. The
            // background view receives the new artwork URL and rekeys itself.
            currentTrack = nextTrack
        }

        isPlaying = snapshot.isPlaying
        resetPlaybackAnchor(to: snapshot.position)
    }

    private func clearLiveTrackIfNeeded() {
        guard !isMockPreviewMode else { return }
        let hadLiveState = hasLiveTrack || lyricsSession.activeIdentity != nil || !lyrics.isEmpty
        hasLiveTrack = false
        if hadLiveState {
            currentTrack = .emptyPlaybackPlaceholder
            lyricsSession.clear()
        }
        isPlaying = false
        resetPlaybackAnchor(to: 0)
    }

    private func runProviderCommand(_ command: @escaping @MainActor (PlaybackProvider) async throws -> Void) {
        invalidateProviderRefresh()
        providerRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await command(self.provider)
                try? await Task.sleep(nanoseconds: 250_000_000)
                await self.refreshProvider()
            } catch {
                self.handleProviderError(error)
            }
        }
    }

    private func invalidateProviderRefresh() {
        providerRefreshGeneration &+= 1
        if isRefreshingProvider {
            refreshRequestedWhileBusy = true
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
        clearLiveTrackIfNeeded()
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
        if isMockPreviewMode {
            currentTime = min(currentTrack.duration, currentTime + (isPlaying ? tickInterval : 0))
            if currentTime >= currentTrack.duration {
                isPlaying = false
                resetPlaybackAnchor(to: currentTrack.duration)
            }
        } else if providerStatus.isReady, hasLiveTrack {
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
        } else {
            currentTime = 0
        }

        let shouldRefreshProvider = !isMockPreviewMode &&
            Date().timeIntervalSince(lastProviderRefreshDate) >= calibrationInterval
        if shouldRefreshProvider && !isRefreshingProvider {
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
    static let emptyPlaybackPlaceholder = Track(
        id: "no-live-track",
        title: "等待 Spotify 播放",
        artist: "Spotify Desktop",
        album: "",
        duration: 0,
        artworkName: "music.note"
    )

    init(providerTrack: ProviderTrack) {
        let fallbackID = TrackIdentity.metadataFingerprint(
            title: providerTrack.title,
            artist: providerTrack.artist,
            album: providerTrack.album,
            duration: providerTrack.duration
        )
        self.init(
            id: providerTrack.id ?? "metadata-\(fallbackID)",
            title: providerTrack.title,
            artist: providerTrack.artist,
            album: providerTrack.album,
            duration: providerTrack.duration,
            artworkName: "music.note",
            isrc: providerTrack.isrc,
            spotifyId: providerTrack.id,
            artworkURL: providerTrack.artworkURL,
            spotifyURL: providerTrack.spotifyURL
        )
    }
}

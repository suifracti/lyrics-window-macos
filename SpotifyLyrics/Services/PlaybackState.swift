import Combine
import AppKit
import UniformTypeIdentifiers
import Foundation
import Network
#if DEBUG
import os
#endif

@MainActor
public final class PlaybackState: ObservableObject {
#if DEBUG
    private static let seekLogger = Logger(subsystem: "com.spotifylyrics.app", category: "seek")
#endif
    @Published public private(set) var currentTrack: Track = .emptyPlaybackPlaceholder
    @Published public private(set) var currentTime: TimeInterval = 0
    @Published public private(set) var isPlaying = false
    @Published public var currentMode: LyricsDisplayMode = .mainWindow
    @Published public var preferences: DisplayPreferences = DisplayPreferences()
    @Published public private(set) var providerStatus: PlaybackProviderState = .connecting
    @Published public private(set) var isMockPreviewMode = false
    @Published public private(set) var hasLiveTrack = false
    @Published public private(set) var songSearchSelectionMessage = ""

    // Auxiliary display states remain available to the existing window manager.
    @Published public var showFloatingWindow = false
    @Published public var showCapsulePlayer = false
    @Published public var showFullScreen = false

    private let provider: PlaybackProvider
    private let lyricsSession: LyricsSessionController
    public let songSearchManager: SongSearchManager
    private var lyricsSessionCancellable: AnyCancellable?
    private var timer: Timer?
    private var isProviderStarted = false
    private var isRefreshingProvider = false
    private var providerRefreshGeneration: UInt64 = 0
    private var refreshRequestedWhileBusy = false
    private var providerRefreshTask: Task<Void, Never>?
    private var networkRecoveryMonitor: NWPathMonitor?
    private var networkWasSatisfied = false
    private var playbackAnchorPosition: TimeInterval = 0
    private var playbackAnchorDate = Date()
    private var lastProviderRefreshDate = Date.distantPast
    private let tickInterval: TimeInterval = 0.2
    private let calibrationInterval: TimeInterval = 2.0

    public init(
        provider: PlaybackProvider? = nil,
        lyricsProvider: LyricsProvider? = nil
    ) {
        let resolvedProvider = provider ?? SpotifyDesktopProvider()
        self.provider = resolvedProvider
        let sharedIndex = LocalLyricsIndex.shared
        let lyricsProviders: [LyricsProvider]
        if let lyricsProvider {
            lyricsProviders = [lyricsProvider]
        } else {
            lyricsProviders = Self.makeDefaultLyricsProviders(index: sharedIndex)
        }
        LyricsE2ELog.reset()
        LyricsE2ELog.log("PlaybackState init providers=" + lyricsProviders.map { $0.name }.joined(separator: ","))
        self.lyricsSession = LyricsSessionController(providers: lyricsProviders)
        // Track search is metadata-only: local index + current Spotify track.
        // LRCLIB stays isolated inside the lyrics session path.
        self.songSearchManager = SongSearchManager(providers: [
            LocalSearchProvider(index: sharedIndex),
            CurrentTrackResolver(playbackProvider: resolvedProvider)
        ] as [TrackSearchProvider])
        self.lyricsSessionCancellable = nil
        self.lyricsSessionCancellable = self.lyricsSession.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
            // `@Published` emits objectWillChange before the session property
            // is mutated. Forwarding only that pre-change pulse can leave a
            // paused UI showing the previous loading/no-match state forever;
            // publish once on the next main-actor turn after the mutation too.
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.objectWillChange.send()
                self.tryAutoAlignIfRequested()
            }
        }
    }


    private static func makeDefaultLyricsProviders(index: LocalLyricsIndex) -> [LyricsProvider] {
        var providers: [LyricsProvider] = [
            LocalLyricsProvider(index: index),
            LRCLIBLyricsProvider()
        ]
        // Experimental NetEase: catalog≠body (あやふや / 水曜日の約束 Kawasaki.Rio empty lrc).
        if ProcessInfo.processInfo.environment["SPOTIFYLYRICS_DISABLE_NETEASE"] != "1" {
            providers.append(NetEaseExperimentalLyricsProvider())
        }
        // Experimental QQ: single-track audit proved body for 水曜日の約束/Kawasaki.Rio.
        if ProcessInfo.processInfo.environment["SPOTIFYLYRICS_DISABLE_QQ"] != "1" {
            providers.append(QQExperimentalLyricsProvider())
        }
        return providers
    }

    deinit {
        timer?.invalidate()
        providerRefreshTask?.cancel()
        networkRecoveryMonitor?.cancel()
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
        startNetworkRecoveryMonitor()
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
        alignmentTask?.cancel()
        didAutoAlignForIdentity = nil
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
        alignmentTask?.cancel()
        didAutoAlignForIdentity = nil
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

    public func seek(to time: TimeInterval, source: String = "programmatic") {
        guard canInteractWithPlayback else { return }
        guard time.isFinite,
              time >= 0,
              currentTrack.duration.isFinite,
              currentTrack.duration > 0,
              time <= currentTrack.duration else {
            #if DEBUG
            Self.seekLogger.debug("rejected source=\(source, privacy: .public) time=\(time, privacy: .public) duration=\(self.currentTrack.duration, privacy: .public) identity=\(self.currentTrackIdentity?.stableKey ?? "none", privacy: .public)")
            #endif
            return
        }

        let seekTime = time
        #if DEBUG
        Self.seekLogger.debug("accepted source=\(source, privacy: .public) time=\(String(format: "%.3f", seekTime), privacy: .public) identity=\(self.currentTrackIdentity?.stableKey ?? "none", privacy: .public)")
        #endif
        resetPlaybackAnchor(to: seekTime)

        guard canControlSpotify else { return }
        invalidateProviderRefresh()
        runProviderCommand { provider in
            try await provider.seek(to: seekTime)
        }
    }

    public func retryLyrics() {
        autoCompleteLyrics()
    }

    /// Product default: one-button lyrics auto-complete for the live TrackIdentity.
    public func autoCompleteLyrics() {
        guard hasLiveTrack, let identity = currentTrackIdentity else { return }
        LyricsE2ELog.log("UI autoCompleteLyrics identity=\(identity.stableKey) title=\(currentTrack.title) pos=\(currentTime)")
        let posBefore = currentTime
        lyricsSession.autoComplete(track: currentTrack, identity: identity)
        LyricsE2ELog.log("UI autoCompleteLyrics dispatched posBefore=\(posBefore) (must not seek)")
    }

    /// noTextSource fallback: pick a local audio file and build an ASR lyrics draft.

    private let alignmentService: any AlignmentService = SpeechForcedAlignmentService()
    private var alignmentTask: Task<Void, Never>?
    private var didAutoAlignForIdentity: TrackIdentity?

    /// Debug-only acceptance hook. It is opt-in and keyed by the live
    /// TrackIdentity so state publications cannot start duplicate work.
    private func tryAutoAlignIfRequested() {
        guard ProcessInfo.processInfo.environment["SPOTIFYLYRICS_AUTO_ALIGN"] == "1",
              hasLiveTrack,
              let identity = currentTrackIdentity,
              didAutoAlignForIdentity != identity else {
            return
        }
        guard case .alignmentQueued = lyricsSession.state else { return }

        didAutoAlignForIdentity = identity
        LyricsE2ELog.log("UI autoAlign env trigger identity=\(identity.stableKey)")
        alignCurrentLyricsWithLocalAudio()
    }

    /// Known plain lyrics + local audio -> line-level forced alignment preview.
    public func alignCurrentLyricsWithLocalAudio() {
        guard hasLiveTrack, let identity = currentTrackIdentity, !isMockPreviewMode else {
            songSearchSelectionMessage = "需要当前 Spotify 歌曲"
            return
        }
        guard let plain = lyricsSession.state.plainDocument ?? lyricsSession.state.document else {
            songSearchSelectionMessage = "当前没有可排轴的歌词正文"
            return
        }

        let url: URL
        if let override = ProcessInfo.processInfo.environment["SPOTIFYLYRICS_ALIGN_AUDIO"],
           !override.isEmpty {
            url = URL(fileURLWithPath: override)
            guard FileManager.default.isReadableFile(atPath: url.path) else {
                songSearchSelectionMessage = "排轴音频不可读：\(override)"
                return
            }
        } else {
            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            panel.allowedContentTypes = [.mp3, .wav, .aiff, .mpeg4Audio]
            panel.title = "选择本地音频（逐行自动排轴）"
            panel.message = "不会修改原音频，也不会从 Spotify 取流。确认前不会覆盖当前歌词。"
            guard panel.runModal() == .OK, let picked = panel.url else { return }
            url = picked
        }

        let posBefore = currentTime
        LyricsE2ELog.log("UI align start identity=\(identity.stableKey) audio=\(url.lastPathComponent) pos=\(posBefore)")
        alignmentTask?.cancel()
        lyricsSession.beginAlignment(identity: identity, plain: plain)
        alignmentTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let request = AlignmentRequest(
                    identity: identity,
                    track: self.currentTrack,
                    plainLines: plain.lines,
                    audioURL: url,
                    durationHint: self.currentTrack.duration
                )
                let report = try await self.alignmentService.align(request) { prog in
                    Task { @MainActor [weak self] in
                        guard let self, self.currentTrackIdentity == identity else { return }
                        let value: Double
                        switch prog {
                        case .preparingAudio(let p): value = 0.05 + 0.15 * p
                        case .recognizing(let p): value = 0.20 + 0.45 * p
                        case .aligning(let p): value = 0.65 + 0.25 * p
                        case .scoring(let p): value = 0.90 + 0.09 * p
                        case .finished: value = 1
                        }
                        self.lyricsSession.updateAlignmentProgress(identity: identity, plain: plain, progress: value)
                        self.songSearchSelectionMessage = "自动排轴 \(Int(value * 100))%"
                    }
                }
                guard !Task.isCancelled, self.currentTrackIdentity == identity else { return }
                let timed = report.makeDocument(base: plain, source: .automaticAlignment)
                self.lyricsSession.presentAlignmentPreview(
                    identity: identity,
                    plain: plain,
                    timed: timed,
                    report: report
                )
                self.songSearchSelectionMessage = String(
                    format: "排轴预览：总置信度 %.0f%%，低置信 %d 行。确认后保存。",
                    report.overallConfidence * 100,
                    report.lowConfidenceCount
                )
                LyricsE2ELog.log("UI align preview ready overall=\(report.overallConfidence) low=\(report.lowConfidenceCount) pos=\(self.currentTime) before=\(posBefore)")
            } catch {
                guard self.currentTrackIdentity == identity else { return }
                self.lyricsSession.adopt(document: plain)
                self.songSearchSelectionMessage = "自动排轴失败：\(error.localizedDescription)"
                LyricsE2ELog.log("UI align failed \(error.localizedDescription)")
            }
        }
    }

    public func confirmAlignmentPreview(saveLocal: Bool = true) {
        guard hasLiveTrack, let identity = currentTrackIdentity else { return }
        guard case .alignmentPreview(_, _, let timed, let report) = lyricsSession.state else { return }
        let posBefore = currentTime
        do {
            let url = try lyricsSession.confirmAlignment(
                identity: identity,
                timed: timed,
                report: report,
                saveLocal: saveLocal
            )
            if let url {
                songSearchSelectionMessage = "已确认并保存：\(url.lastPathComponent)"
            } else {
                songSearchSelectionMessage = "已确认排轴结果"
            }
            LyricsE2ELog.log("UI align confirmed save=\(saveLocal) posBefore=\(posBefore) posAfter=\(currentTime)")
        } catch {
            songSearchSelectionMessage = "保存失败：\(error.localizedDescription)"
        }
    }

    public func cancelAlignmentPreview() {
        guard hasLiveTrack, let identity = currentTrackIdentity else { return }
        if case .alignmentPreview(_, let plain, _, _) = lyricsSession.state {
            lyricsSession.cancelAlignmentPreview(identity: identity, plain: plain)
            songSearchSelectionMessage = "已返回未排轴歌词"
            return
        }
        if case .alignmentRunning(_, let plain, _) = lyricsSession.state {
            alignmentTask?.cancel()
            lyricsSession.adopt(document: plain)
            songSearchSelectionMessage = "已取消排轴"
        }
    }

    public func importLocalAudioForASR() {
        guard hasLiveTrack, let identity = currentTrackIdentity, !isMockPreviewMode else {
            songSearchSelectionMessage = "需要当前 Spotify 歌曲身份才能生成 ASR 草稿"
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.mp3, .wav, .aiff, .mpeg4Audio]
        panel.title = "选择本地音频（ASR 歌词草稿）"
        panel.message = "不会从 Spotify 取受保护音频。生成结果为机器草稿，需人工校正。"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { @MainActor in
            await self.runLocalAudioASR(url: url, identity: identity)
        }
    }

    public func runLocalAudioASR(url: URL, identity: TrackIdentity) async {
        guard hasLiveTrack, currentTrackIdentity == identity else { return }
        lyricsSession.beginLoadingPlaceholder(identity: identity, message: "ASR 识别中…")
        do {
            let service = LocalAudioASRService()
            let document = try await service.makeLyricsDocument(
                audioURL: url,
                identity: identity,
                track: currentTrack
            )
            guard currentTrackIdentity == identity else { return }
            lyricsSession.adopt(document: document)
            if case .alignmentQueued = lyricsSession.state {
                songSearchSelectionMessage = "ASR 草稿已生成（待对齐/待校正）"
            } else {
                songSearchSelectionMessage = "ASR 草稿已生成（机器生成，待校正）"
            }
        } catch {
            guard currentTrackIdentity == identity else { return }
            lyricsSession.fail(identity: identity, failure: .unknown("ASR 失败：\(error.localizedDescription)"))
            songSearchSelectionMessage = "ASR 失败：\(error.localizedDescription)"
        }
    }


    /// Applies a selected track-search result to the current lyric session
    /// without changing Spotify playback or its time anchor.
    /// Track search results are metadata-only; local lyrics are resolved from
    /// the shared read-only index when the selected track matches the live song.
    public func loadSearchResult(_ result: SongSearchResult) {
        guard !isMockPreviewMode else {
            songSearchSelectionMessage = "请先退出 Mock Preview，再加载真实歌曲歌词"
            return
        }
        guard hasLiveTrack, let activeIdentity = currentTrackIdentity else {
            songSearchSelectionMessage = "当前没有可加载歌词的 Spotify 歌曲"
            return
        }

        let resolvedLyrics = result.lyrics ?? Self.localLyrics(for: result, identity: activeIdentity)

        if let lyrics = resolvedLyrics {
            let candidate = LyricsCandidate(
                id: result.id,
                identity: activeIdentity,
                title: result.track.title,
                artist: result.track.artist,
                album: result.track.album,
                duration: result.track.duration,
                lines: lyrics.lines,
                isSynchronized: lyrics.isSynchronized,
                source: lyrics.source,
                confidence: result.confidence
            )
            let metadataConfidence = LyricsMatcher.score(track: currentTrack, candidate: candidate)
            guard LyricsMatcher.isHighConfidence(metadataConfidence) else {
                songSearchSelectionMessage = "搜索结果与当前歌曲匹配度不足，未加载"
                return
            }

            let remapped = LyricsDocument(
                identity: activeIdentity,
                title: lyrics.title ?? result.track.title,
                artist: lyrics.artist ?? result.track.artist,
                album: lyrics.album ?? result.track.album,
                duration: lyrics.duration ?? result.track.duration,
                lines: lyrics.lines,
                isSynchronized: lyrics.isSynchronized,
                source: lyrics.source,
                confidence: metadataConfidence
            )
            lyricsSession.adopt(document: remapped)
            songSearchSelectionMessage = "已加载搜索结果歌词，播放位置未改变"
            return
        }

        let trackResult = result.asTrackSearchResult()
        let metadataProbe = LyricsCandidate(
            id: trackResult.id,
            identity: activeIdentity,
            title: trackResult.track.title,
            artist: trackResult.track.artist,
            album: trackResult.track.album,
            duration: trackResult.track.duration,
            lines: [LyricLine(timestamp: 0, originalText: ".")],
            source: .local,
            confidence: trackResult.confidence
        )
        let metadataConfidence = LyricsMatcher.score(track: currentTrack, candidate: metadataProbe)

        if TrackIdentity(track: result.track) == activeIdentity || LyricsMatcher.isHighConfidence(metadataConfidence) {
            retryLyrics()
            songSearchSelectionMessage = "已重新搜索当前歌曲歌词"
            return
        }

        songSearchSelectionMessage = "该结果不是当前 Spotify 歌曲，未改变播放"
    }

    private static func localLyrics(for result: SongSearchResult, identity: TrackIdentity) -> LyricsDocument? {
        guard result.source == .local else { return nil }
        guard let entry = LocalLyricsIndex.shared.entry(id: result.id) else { return nil }
        return LocalLyricsIndex.shared.document(for: entry, identity: identity, confidence: result.confidence)
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
        defer {
            // A cancelled or failed refresh must release the single-flight
            // guard as well. Otherwise a stale Apple Events task can leave
            // the state permanently disconnected.
            isRefreshingProvider = false
        }
        let snapshot = await provider.refresh()
        // Throttle from the end of every bounded attempt, including an
        // unavailable/timeout result. Do not start a new task every timer tick
        // while a previous Apple Events request is unwinding.
        lastProviderRefreshDate = Date()

        let shouldApply = !Task.isCancelled && generation == providerRefreshGeneration && !isMockPreviewMode
        if shouldApply {
            synchronize(with: snapshot)
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
            alignmentTask?.cancel()
            didAutoAlignForIdentity = nil
            hasLiveTrack = true
            isMockPreviewMode = false
            currentTrack = nextTrack
            songSearchSelectionMessage = ""
            LyricsE2ELog.log("Playback trackChange identity=\(nextIdentity.stableKey) title=\(nextTrack.title) artist=\(nextTrack.artist) duration=\(nextTrack.duration)")
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
        alignmentTask?.cancel()
        didAutoAlignForIdentity = nil
        let hadLiveState = hasLiveTrack || lyricsSession.activeIdentity != nil || !lyrics.isEmpty
        hasLiveTrack = false
        if hadLiveState {
            currentTrack = .emptyPlaybackPlaceholder
            lyricsSession.clear()
        }
        songSearchSelectionMessage = ""
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

    private func startNetworkRecoveryMonitor() {
        guard networkRecoveryMonitor == nil else { return }

        let monitor = NWPathMonitor()
        networkRecoveryMonitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            let isSatisfied = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self else { return }
                let wasSatisfied = self.networkWasSatisfied
                self.networkWasSatisfied = isSatisfied
                guard isSatisfied, !wasSatisfied else { return }
                self.retryLyricsAfterNetworkRecovery()
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.spotifylyrics.network-recovery"))
    }

    private func retryLyricsAfterNetworkRecovery() {
        guard hasLiveTrack,
              let identity = currentTrackIdentity else { return }
        _ = lyricsSession.retryAfterNetworkRecovery(track: currentTrack, identity: identity)
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

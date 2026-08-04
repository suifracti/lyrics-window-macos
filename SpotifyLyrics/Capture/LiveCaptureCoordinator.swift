#if DEBUG
import Foundation
import Combine
import CoreMedia
import AVFoundation

/// S2: binds ScreenCaptureKit audio samples to Spotify playback position and
/// splits discontinuous capture into `CapturedAudioSegment`s.
///
/// - No ASR / alignment / SQLite lyrics writes.
/// - Observes existing `PlaybackState` publishers (no second Spotify poller).
/// - Local Combine subscriptions are cancelled on stop.
@MainActor
public final class LiveCaptureCoordinator: ObservableObject {
    public static let shared = LiveCaptureCoordinator()

    public enum State: String, Sendable {
        case idle
        case running
        case stopping
        case failed
    }

    @Published public private(set) var state: State = .idle
    @Published public private(set) var lastError: String?
    @Published public private(set) var completedSessions: [CapturedAudioSession] = []
    @Published public private(set) var activeSession: CapturedAudioSession?

    private weak var playback: PlaybackState?
    private var cancellables = Set<AnyCancellable>()
    private var openSegment: MutableSegment?
    private var lastPosition: TimeInterval = 0
    private var lastHostTime: TimeInterval = 0
    private var lastIsPlaying = false
    private var lastIdentityKey: String?
    private var lastAudioHostTime: TimeInterval = 0
    private var lastAnchorLogHostTime: TimeInterval = 0
    private var sessionWorkDirectory: URL?
    private var autoStopTask: Task<Void, Never>?
    private var gapWatchTask: Task<Void, Never>?
    private var alignmentGeneration: UInt64 = 0
    private let generationFlag = GenerationFlag()
    private var alignmentTask: Task<Void, Never>?
    @Published public private(set) var lastPartialReport: PartialAlignmentReport?

    private init() {
        LiveCaptureCoordinator.scavengeOrphanTemp()
        let s3a = ProcessInfo.processInfo.environment["SPOTIFYLYRICS_SCK_S3A"] == "1"
        let s2 = ProcessInfo.processInfo.environment["SPOTIFYLYRICS_SCK_S2"] == "1" || s3a
        if s2 {
            let defaultSeconds = s3a ? "75" : "55"
            let seconds = Double(ProcessInfo.processInfo.environment["SPOTIFYLYRICS_SCK_S2_SECONDS"]
                ?? ProcessInfo.processInfo.environment["SPOTIFYLYRICS_SCK_S3A_SECONDS"]
                ?? defaultSeconds) ?? 75
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await self.start(autoStopAfter: max(20, seconds), runPartialAlignment: s3a)
            }
        }
    }

    public func bind(playback: PlaybackState) {
        self.playback = playback
        SCKSpikeLog.log("S2 bind playback ok")
    }

    /// Called from PlaybackState when a large position discontinuity is known
    /// (local seek API or Desktop snapshot jump). Safe no-op when idle.
    public func notifyPlaybackPositionJump(
        from previous: TimeInterval,
        to next: TimeInterval,
        isPlaying playing: Bool
    ) {
        guard state == .running, activeSession != nil else { return }
        let host = Date().timeIntervalSince1970
        let reason: SegmentBoundaryReason = next >= previous ? .seekForward : .seekBackward
        endOpenSegment(reason: reason, position: previous)
        if playing {
            beginSegment(reason: reason, position: next, host: host)
        }
        lastPosition = next
        lastHostTime = host
        lastIsPlaying = playing
        SCKSpikeLog.log(
            "S2 SEEK reason=\(reason.rawValue) from=\(fmt(previous)) to=\(fmt(next)) source=playbackNotify"
        )
    }

    // MARK: - Start / stop

    private var shouldRunPartialAlignment = false

    public func start(autoStopAfter seconds: TimeInterval? = nil, runPartialAlignment: Bool = false) async {
        guard state == .idle || state == .failed else {
            SCKSpikeLog.log("S2 start ignored state=\(state.rawValue)")
            return
        }
        lastError = nil
        lastPartialReport = nil
        completedSessions = []
        activeSession = nil
        openSegment = nil
        shouldRunPartialAlignment = runPartialAlignment
            || ProcessInfo.processInfo.environment["SPOTIFYLYRICS_SCK_S3A"] == "1"
        alignmentGeneration &+= 1
        generationFlag.value = alignmentGeneration
        alignmentTask?.cancel()
        SCKSpikeLog.log(
            "S2 SESSION_BOOT formal_db_opened=NO partial=\(shouldRunPartialAlignment) gen=\(alignmentGeneration)"
        )

        // Ensure low-level capture is running and samples are forwarded here.
        SpotifyScreenCaptureAudioSpike.shared.audioSampleHandler = { [weak self] buffer in
            // Append PCM on the capture queue path first (writer is thread-safe).
            self?.appendPCM(buffer)
            self?.handleAudioSample(buffer)
        }

        if SpotifyScreenCaptureAudioSpike.shared.state != .capturing {
            await SpotifyScreenCaptureAudioSpike.shared.start(autoStopAfter: nil)
        }
        guard SpotifyScreenCaptureAudioSpike.shared.state == .capturing else {
            lastError = SpotifyScreenCaptureAudioSpike.shared.lastError ?? "capture failed"
            state = .failed
            SCKSpikeLog.log("S2 failed to start underlying spike error=\(lastError ?? "")")
            return
        }

        installPlaybackObservers()
        state = .running

        if let identity = playback?.currentTrackIdentity, playback?.hasLiveTrack == true {
            beginSession(identity: identity, trackDuration: playback?.currentTrack.duration ?? 0, reason: .initial)
        } else {
            SCKSpikeLog.log("S2 waiting for live track before first session")
        }

        autoStopTask?.cancel()
        if let seconds {
            autoStopTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                guard !Task.isCancelled else { return }
                // Spawn a fresh task so cancelling `autoStopTask` inside stop()
                // cannot cancel Speech/alignment work.
                Task { @MainActor in
                    await self.stop(reason: .autoStop)
                }
            }
        }

        gapWatchTask?.cancel()
        gapWatchTask = Task { @MainActor in
            while !Task.isCancelled, self.state == .running {
                try? await Task.sleep(nanoseconds: 250_000_000)
                self.evaluateAudioGap()
            }
        }
    }

    public func stop(reason: CaptureTerminalReason = .userStop) async {
        guard state == .running || state == .failed else { return }
        state = .stopping
        SCKSpikeLog.log("S2 stop reason=\(reason.rawValue)")
        autoStopTask?.cancel()
        autoStopTask = nil
        gapWatchTask?.cancel()
        gapWatchTask = nil
        cancellables.removeAll()

        endOpenSegment(reason: boundary(from: reason), position: playback?.currentTime)
        if var session = activeSession {
            session.terminalReason = reason
            finalizeSession(session, reason: reason)
        }
        activeSession = nil

        SpotifyScreenCaptureAudioSpike.shared.audioSampleHandler = nil

        // Align while WAVs still exist; S1 spike stop scavenges capture temp.
        if shouldRunPartialAlignment {
            await runPartialAlignmentIfNeeded(stopReason: reason)
        }

        await SpotifyScreenCaptureAudioSpike.shared.stop(reason: "s2-\(reason.rawValue)")

        // Delete capture WAVs / session sidecars after alignment; keep s3a reports.
        cleanupSessionDirectory()
        LiveCaptureCoordinator.scavengeOrphanTemp()
        state = .idle
        SCKSpikeLog.log("S2 stopped idle sessions=\(completedSessions.count)")
        logSummaryTable()
    }

    private func appendPCM(_ sampleBuffer: CMSampleBuffer) {
        // Called from capture queue via handler; writer is thread-safe.
        // openSegment is MainActor-isolated — use a lock-free snapshot of the writer.
        // We hop: writers are only swapped on MainActor, so we take a local ref under MainActor.
        Task { @MainActor in
            self.openSegment?.wavWriter?.append(sampleBuffer)
        }
    }

    // MARK: - Playback observation (no second Spotify poller)

    private func installPlaybackObservers() {
        cancellables.removeAll()
        guard let playback else {
            SCKSpikeLog.log("S2 no playback bound")
            return
        }

        lastPosition = playback.currentTime
        lastHostTime = Date().timeIntervalSince1970
        lastIsPlaying = playback.isPlaying
        lastIdentityKey = playback.currentTrackIdentity?.stableKey

        // Reuse PlaybackState's existing timer-driven publishers.
        playback.$currentTime
            .receive(on: DispatchQueue.main)
            .sink { [weak self] position in
                self?.onPosition(position)
            }
            .store(in: &cancellables)

        playback.$isPlaying
            .receive(on: DispatchQueue.main)
            .sink { [weak self] playing in
                self?.onPlayingChanged(playing)
            }
            .store(in: &cancellables)

        playback.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.onPlaybackObjectWillChange()
            }
            .store(in: &cancellables)
    }

    private func onPlaybackObjectWillChange() {
        // Identity is not a separate publisher; re-read after the next main turn.
        Task { @MainActor in
            self.evaluateIdentityChange()
        }
    }

    private func onPlayingChanged(_ playing: Bool) {
        guard state == .running else { return }
        let host = Date().timeIntervalSince1970
        let position = playback?.currentTime ?? lastPosition
        if lastIsPlaying && !playing {
            endOpenSegment(reason: .pause, position: position)
            SCKSpikeLog.log("S2 PLAYBACK paused position=\(fmt(position))")
        } else if !lastIsPlaying && playing {
            if activeSession != nil {
                beginSegment(reason: .resume, position: position, host: host)
            }
            SCKSpikeLog.log("S2 PLAYBACK resumed position=\(fmt(position))")
        }
        lastIsPlaying = playing
        lastPosition = position
        lastHostTime = host
    }

    private func onPosition(_ position: TimeInterval) {
        guard state == .running else { return }
        let host = Date().timeIntervalSince1970
        evaluateIdentityChange()

        guard activeSession != nil else {
            lastPosition = position
            lastHostTime = host
            return
        }

        let dtHost = max(0, host - lastHostTime)
        let expected = lastIsPlaying ? lastPosition + dtHost : lastPosition
        let deltaFromExpected = position - expected
        let absJump = abs(position - lastPosition)

        // Primary: raw Spotify position jump (provider refresh after seek).
        // Secondary: deviation from host-clock expected progress (catches
        // jumps that land near a "plausible" interpolated value).
        let looksLikeSeek = absJump > CaptureContinuityPolicy.seekJumpThreshold
            || (lastIsPlaying
                && abs(deltaFromExpected) > CaptureContinuityPolicy.seekJumpThreshold
                && absJump > CaptureContinuityPolicy.positionJitterTolerance)

        if looksLikeSeek, openSegment != nil || lastIsPlaying {
            let reason: SegmentBoundaryReason = position >= lastPosition ? .seekForward : .seekBackward
            endOpenSegment(reason: reason, position: lastPosition)
            if playback?.isPlaying == true {
                beginSegment(reason: reason, position: position, host: host)
            }
            SCKSpikeLog.log(
                "S2 SEEK reason=\(reason.rawValue) from=\(fmt(lastPosition)) to=\(fmt(position)) expected=\(fmt(expected)) jump=\(fmt(absJump)) drift=\(fmt(deltaFromExpected))"
            )
        } else if openSegment != nil, lastIsPlaying {
            openSegment?.spotifyPositionEnd = position
            maybeLogAnchor(position: position, host: host, audioPTS: openSegment?.audioPTSEnd)
        }

        lastPosition = position
        lastHostTime = host
    }

    private func evaluateIdentityChange() {
        guard state == .running else { return }
        let identity = playback?.currentTrackIdentity
        let key = identity?.stableKey
        if key == lastIdentityKey { return }

        let previous = lastIdentityKey
        lastIdentityKey = key
        SCKSpikeLog.log("S2 IDENTITY previous=\(short(previous)) next=\(short(key))")

        // Invalidate any in-flight S3A work for the previous song.
        alignmentGeneration &+= 1
        generationFlag.value = alignmentGeneration
        alignmentTask?.cancel()
        SCKSpikeLog.log("S3A cancel gen=\(alignmentGeneration) reason=trackChanged")

        endOpenSegment(reason: .trackChanged, position: lastPosition)
        if var session = activeSession {
            session.terminalReason = .trackChanged
            finalizeSession(session, reason: .trackChanged)
        }
        activeSession = nil

        if let identity, playback?.hasLiveTrack == true {
            beginSession(
                identity: identity,
                trackDuration: playback?.currentTrack.duration ?? 0,
                reason: .trackChanged
            )
        } else {
            SCKSpikeLog.log("S2 no live track after identity change")
        }
    }

    // MARK: - Session / segment

    private func beginSession(identity: TrackIdentity, trackDuration: TimeInterval, reason: SegmentBoundaryReason) {
        let sessionID = UUID()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(CaptureContinuityPolicy.temporaryRootName, isDirectory: true)
            .appendingPathComponent(CaptureContinuityPolicy.s2SessionsFolderName, isDirectory: true)
            .appendingPathComponent(sessionID.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        sessionWorkDirectory = root

        var session = CapturedAudioSession(
            sessionID: sessionID,
            trackIdentity: identity,
            trackDuration: trackDuration
        )
        activeSession = session
        SCKSpikeLog.log(
            "SESSION start sessionID=\(sessionID.uuidString) identity=\(session.identityDigest) duration=\(fmt(trackDuration)) source=\(session.captureSource) reason=\(reason.rawValue)"
        )
        // Start a segment only when currently playing; pause waits for resume.
        let host = Date().timeIntervalSince1970
        let position = playback?.currentTime ?? 0
        lastPosition = position
        lastHostTime = host
        lastIsPlaying = playback?.isPlaying ?? false
        if lastIsPlaying {
            beginSegment(reason: reason == .trackChanged ? .initial : reason, position: position, host: host)
        } else {
            SCKSpikeLog.log("SESSION waiting for play position=\(fmt(position))")
        }
        _ = session
    }

    private func beginSegment(reason: SegmentBoundaryReason, position: TimeInterval, host: TimeInterval) {
        guard let session = activeSession else { return }
        if openSegment != nil {
            endOpenSegment(reason: .sessionReplaced, position: position)
        }
        let continuity = UUID()
        let segmentID = UUID()
        var writer: SegmentWAVWriter?
        if let dir = sessionWorkDirectory {
            writer = try? SegmentWAVWriter(directory: dir, segmentID: segmentID)
        }
        let segment = MutableSegment(
            segmentID: segmentID,
            sessionID: session.sessionID,
            trackIdentity: session.trackIdentity,
            spotifyPositionStart: position,
            hostTimeStart: host,
            continuityID: continuity,
            startReason: reason,
            wavWriter: writer
        )
        openSegment = segment
        SCKSpikeLog.log(
            "SEGMENT start segmentID=\(segment.segmentID.uuidString) sessionID=\(session.sessionID.uuidString) identity=\(segment.identityDigest) reason=\(reason.rawValue) position=\(fmt(position)) hostTime=\(fmt(host)) continuityID=\(continuity.uuidString) wav=\(writer?.fileURL.lastPathComponent ?? "none")"
        )
    }

    private func endOpenSegment(reason: SegmentBoundaryReason, position: TimeInterval?) {
        guard var segment = openSegment else { return }
        openSegment = nil
        let host = Date().timeIntervalSince1970
        segment.hostTimeEnd = host
        segment.spotifyPositionEnd = position ?? segment.spotifyPositionEnd ?? segment.spotifyPositionStart
        segment.endReason = reason
        if segment.sampleRate > 0 {
            segment.duration = Double(segment.sampleCount) / segment.sampleRate
        } else {
            segment.duration = max(0, host - segment.hostTimeStart)
        }
        segment.isContinuous = (reason == .pause || reason == .userStop || reason == .autoStop || reason == .trackChanged)

        // Finalize WAV first so temporaryPCMReference points at audio for S3A.
        if let wavURL = try? segment.wavWriter?.finish() {
            segment.temporaryPCMReference = wavURL.path
            SCKSpikeLog.log("WAV ready path=\(wavURL.path) frames=\(segment.wavWriter?.framesWritten ?? 0)")
        } else {
            segment.wavWriter?.abandon()
            // Fall back to JSON sidecar metadata only.
            segment.temporaryPCMReference = writeSegmentSidecar(segment.frozen())
        }
        // Always write metadata sidecar alongside (when dir exists).
        _ = writeSegmentSidecar(segment.frozen())

        let frozen = segment.frozen()
        if var session = activeSession {
            session.segments.append(frozen)
            activeSession = session
        }
        SCKSpikeLog.log(
            "SEGMENT end segmentID=\(frozen.segmentID.uuidString) sessionID=\(frozen.sessionID.uuidString) identity=\(frozen.identityDigest) reason=\(reason.rawValue) posStart=\(fmt(frozen.spotifyPositionStart)) posEnd=\(fmt(frozen.spotifyPositionEnd ?? -1)) hostStart=\(fmt(frozen.hostTimeStart)) hostEnd=\(fmt(frozen.hostTimeEnd ?? -1)) ptsStart=\(fmt(frozen.audioPTSStart ?? -1)) ptsEnd=\(fmt(frozen.audioPTSEnd ?? -1)) samples=\(frozen.sampleCount) buffers=\(frozen.bufferCount) duration=\(fmt(frozen.duration)) rate=\(frozen.sampleRate) ch=\(frozen.channelCount) continuous=\(frozen.isContinuous) pcm=\(frozen.temporaryPCMReference ?? "none")"
        )
    }

    private func runPartialAlignmentIfNeeded(stopReason: CaptureTerminalReason) async {
        let gen = alignmentGeneration
        guard isGenerationCurrent(gen) else {
            SCKSpikeLog.log("S3A skip stale generation")
            return
        }
        // Prefer the longest completed session with WAV-backed segments.
        let sessions = completedSessions
        guard let session = sessions.max(by: { lhs, rhs in
            lhs.segments.map(\.duration).reduce(0, +) < rhs.segments.map(\.duration).reduce(0, +)
        }) else {
            SCKSpikeLog.log("S3A no completed sessions")
            return
        }
        let wavSegments = session.segments.filter { ($0.temporaryPCMReference ?? "").hasSuffix(".wav") }
        guard !wavSegments.isEmpty else {
            SCKSpikeLog.log("S3A no wav segments session=\(session.sessionID.uuidString.prefix(8))")
            return
        }

        guard let playback else {
            SCKSpikeLog.log("S3A no playback for lyrics")
            return
        }
        // Held-out: use current synced lyrics times only for evaluation AFTER
        // alignment. Algorithm input always uses plain lines (timestamps zeroed).
        let liveLines = playback.liveLyrics
        guard !liveLines.isEmpty else {
            SCKSpikeLog.log("S3A no lyrics lines")
            return
        }
        let plain = liveLines.map {
            LyricLine(
                id: $0.id,
                timestamp: 0,
                originalText: $0.originalText,
                endTime: nil,
                translationText: $0.translationText,
                romajiText: $0.romajiText,
                kanaText: $0.kanaText,
                rubyTokens: $0.rubyTokens
            )
        }
        let groundTruth: [LyricLine]? = playback.liveLyricsAreSynchronized ? liveLines : nil
        if playback.liveLyricsAreSynchronized {
            SCKSpikeLog.log("S3A held_out=enabled lines=\(liveLines.count) (timestamps hidden from aligner)")
        } else {
            SCKSpikeLog.log("S3A held_out=disabled plain_or_unsynced")
        }

        let localeOverride = ProcessInfo.processInfo.environment["SPOTIFYLYRICS_S3A_LOCALE"]
        do {
            SCKSpikeLog.log("S3A align begin session=\(session.sessionID.uuidString.prefix(8)) segments=\(wavSegments.count)")
            let flag = generationFlag
            let report = try await SegmentPartialAlignmentPipeline.align(
                session: session,
                segments: wavSegments,
                plainLines: plain,
                languageHint: playback.liveLyricsLanguage,
                localeOverride: localeOverride,
                groundTruthSyncedLines: groundTruth,
                identity: session.trackIdentity,
                generation: gen,
                isGenerationCurrent: { flag.matches(gen) }
            )
            guard isGenerationCurrent(gen) else {
                SCKSpikeLog.log("S3A drop stale report gen=\(gen)")
                return
            }
            lastPartialReport = report
            SCKSpikeLog.log(
                "S3B judgment=\(report.judgment) constrained=\(report.usedConstrainedAlignment) anchors=\(report.acceptedAnchors.count)/rej=\(report.rejectedAnchors.count) fallback=\(report.s3bFallbackReason ?? "none")"
            )
            if let s3a = report.s3aCandidate {
                SCKSpikeLog.log(
                    "S3B AB s3a_cov=\(String(format: "%.3f", s3a.coverageRatio)) s3b_cov=\(String(format: "%.3f", report.candidate.coverageRatio)) s3a_res=\(s3a.resolvedCount) s3b_res=\(report.candidate.resolvedCount)"
                )
            }
        } catch {
            if !isGenerationCurrent(gen) {
                SCKSpikeLog.log("S3A cancelled gen=\(gen)")
            } else {
                SCKSpikeLog.log("S3A failed error=\(error.localizedDescription)")
            }
        }
    }

    private func isGenerationCurrent(_ gen: UInt64) -> Bool {
        alignmentGeneration == gen
    }

    private func finalizeSession(_ session: CapturedAudioSession, reason: CaptureTerminalReason) {
        var closed = session
        closed.terminalReason = reason
        completedSessions.append(closed)
        SCKSpikeLog.log(
            "SESSION end sessionID=\(closed.sessionID.uuidString) identity=\(closed.identityDigest) reason=\(reason.rawValue) segments=\(closed.segments.count)"
        )
        writeSessionSidecar(closed)
    }

    // MARK: - Audio samples

    private func handleAudioSample(_ sampleBuffer: CMSampleBuffer) {
        // Called on capture queue via handler; hop to MainActor.
        Task { @MainActor in
            self.ingestOnMain(sampleBuffer)
        }
    }

    private func ingestOnMain(_ sampleBuffer: CMSampleBuffer) {
        guard state == .running else { return }
        let host = Date().timeIntervalSince1970
        lastAudioHostTime = host

        // Drop late buffers from a previous session/identity.
        guard let session = activeSession else { return }
        if let live = playback?.currentTrackIdentity, live != session.trackIdentity {
            SCKSpikeLog.log("S2 DROP late buffer identity mismatch")
            return
        }

        // While paused, still count stream health but do not invent segments.
        if CaptureContinuityPolicy.ignoreAudioActivityWhilePaused,
           playback?.isPlaying == false,
           openSegment == nil {
            return
        }

        if openSegment == nil, playback?.isPlaying == true {
            beginSegment(reason: .resume, position: playback?.currentTime ?? lastPosition, host: host)
        }
        guard var segment = openSegment else { return }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let ptsSec = pts.isValid ? CMTimeGetSeconds(pts) : Double.nan
        if ptsSec.isFinite {
            if segment.audioPTSStart == nil { segment.audioPTSStart = ptsSec }
            segment.audioPTSEnd = ptsSec
        }

        if let format = CMSampleBufferGetFormatDescription(sampleBuffer),
           let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee {
            if asbd.mSampleRate > 0 { segment.sampleRate = asbd.mSampleRate }
            if asbd.mChannelsPerFrame > 0 { segment.channelCount = Int(asbd.mChannelsPerFrame) }
        }
        let frames = CMSampleBufferGetNumSamples(sampleBuffer)
        if frames > 0 {
            segment.sampleCount += frames
            segment.bufferCount += 1
        }
        segment.spotifyPositionEnd = playback?.currentTime ?? segment.spotifyPositionEnd
        openSegment = segment
    }

    private func evaluateAudioGap() {
        guard state == .running, openSegment != nil else { return }
        let host = Date().timeIntervalSince1970
        guard lastAudioHostTime > 0 else { return }
        let gap = host - lastAudioHostTime
        guard gap >= CaptureContinuityPolicy.audioGapTimeout else { return }
        if let open = openSegment, (host - open.hostTimeStart) < CaptureContinuityPolicy.minimumSegmentDurationBeforeGapClose {
            return
        }
        // Only gap-close while we believe playback is still running; pause already closed.
        if playback?.isPlaying == true {
            endOpenSegment(reason: .audioGap, position: playback?.currentTime)
            SCKSpikeLog.log("S2 AUDIO_GAP closed segment gap=\(fmt(gap))")
        }
    }

    private func maybeLogAnchor(position: TimeInterval, host: TimeInterval, audioPTS: TimeInterval?) {
        if host - lastAnchorLogHostTime < CaptureContinuityPolicy.anchorLogInterval { return }
        lastAnchorLogHostTime = host
        SCKSpikeLog.log(
            "ANCHOR sessionID=\(activeSession?.sessionID.uuidString ?? "-") segmentID=\(openSegment?.segmentID.uuidString ?? "-") position=\(fmt(position)) hostTime=\(fmt(host)) audioPTS=\(fmt(audioPTS ?? -1)) playing=\(playback?.isPlaying ?? false)"
        )
    }

    // MARK: - Sidecars (no audio payload by default)

    @discardableResult
    private func writeSegmentSidecar(_ segment: CapturedAudioSegment) -> String? {
        guard let dir = sessionWorkDirectory else { return nil }
        let url = dir.appendingPathComponent("seg-\(segment.segmentID.uuidString.prefix(8)).json")
        let payload: [String: Any] = [
            "segmentID": segment.segmentID.uuidString,
            "sessionID": segment.sessionID.uuidString,
            "identityDigest": segment.identityDigest,
            "spotifyPositionStart": segment.spotifyPositionStart,
            "spotifyPositionEnd": segment.spotifyPositionEnd as Any,
            "hostTimeStart": segment.hostTimeStart,
            "hostTimeEnd": segment.hostTimeEnd as Any,
            "audioPTSStart": segment.audioPTSStart as Any,
            "audioPTSEnd": segment.audioPTSEnd as Any,
            "sampleRate": segment.sampleRate,
            "channelCount": segment.channelCount,
            "sampleCount": segment.sampleCount,
            "bufferCount": segment.bufferCount,
            "duration": segment.duration,
            "continuityID": segment.continuityID.uuidString,
            "startReason": segment.startReason.rawValue,
            "endReason": segment.endReason?.rawValue as Any,
            "isContinuous": segment.isContinuous,
            "note": "S2 sidecar metadata only; no PCM payload"
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]) else {
            return nil
        }
        try? data.write(to: url, options: .atomic)
        SCKSpikeLog.log("TEMP sidecar path=\(url.path)")
        return url.path
    }

    private func writeSessionSidecar(_ session: CapturedAudioSession) {
        guard let dir = sessionWorkDirectory else { return }
        let url = dir.appendingPathComponent("session.json")
        let payload: [String: Any] = [
            "sessionID": session.sessionID.uuidString,
            "identityDigest": session.identityDigest,
            "trackDuration": session.trackDuration,
            "segmentCount": session.segments.count,
            "terminalReason": session.terminalReason?.rawValue as Any,
            "captureSource": session.captureSource
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]) {
            try? data.write(to: url, options: .atomic)
            SCKSpikeLog.log("TEMP session sidecar path=\(url.path)")
        }
    }

    private func cleanupSessionDirectory() {
        if let dir = sessionWorkDirectory {
            try? FileManager.default.removeItem(at: dir)
            let exists = FileManager.default.fileExists(atPath: dir.path)
            SCKSpikeLog.log("CLEANUP sessionDir=\(dir.path) exists_after=\(exists)")
        }
        sessionWorkDirectory = nil
        // Also remove completed session folders under s2-sessions.
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(CaptureContinuityPolicy.temporaryRootName, isDirectory: true)
            .appendingPathComponent(CaptureContinuityPolicy.s2SessionsFolderName, isDirectory: true)
        if let children = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            for child in children {
                try? FileManager.default.removeItem(at: child)
                SCKSpikeLog.log("CLEANUP removed=\(child.lastPathComponent)")
            }
        }
    }

    static func scavengeOrphanTemp() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(CaptureContinuityPolicy.temporaryRootName, isDirectory: true)
        guard let children = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
            return
        }
        for child in children {
            try? FileManager.default.removeItem(at: child)
            SCKSpikeLog.log("TEMP scavenge removed=\(child.lastPathComponent)")
        }
    }

    private func logSummaryTable() {
        SCKSpikeLog.log("SUMMARY sessions=\(completedSessions.count)")
        for session in completedSessions {
            SCKSpikeLog.log(
                "SUMMARY_SESSION id=\(session.sessionID.uuidString.prefix(8)) identity=\(session.identityDigest) terminal=\(session.terminalReason?.rawValue ?? "-") segments=\(session.segments.count)"
            )
            for (i, seg) in session.segments.enumerated() {
                SCKSpikeLog.log(
                    "SUMMARY_SEG i=\(i) id=\(seg.segmentID.uuidString.prefix(8)) start=\(seg.startReason.rawValue) end=\(seg.endReason?.rawValue ?? "-") pos=\(fmt(seg.spotifyPositionStart))->\(fmt(seg.spotifyPositionEnd ?? -1)) dur=\(fmt(seg.duration)) samples=\(seg.sampleCount)"
                )
            }
        }
    }

    private func boundary(from reason: CaptureTerminalReason) -> SegmentBoundaryReason {
        switch reason {
        case .trackChanged: return .trackChanged
        case .userStop: return .userStop
        case .autoStop: return .autoStop
        case .streamError: return .streamInterrupted
        case .spotifyUnavailable: return .spotifyUnavailable
        case .appExit: return .appExit
        case .noLiveTrack: return .trackChanged
        }
    }

    private func fmt(_ value: TimeInterval) -> String {
        String(format: "%.3f", value)
    }

    private func short(_ key: String?) -> String {
        guard let key, !key.isEmpty else { return "-" }
        return String(key.prefix(40))
    }
}

// MARK: - Generation flag (Sendable)

private final class GenerationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: UInt64 = 0
    var value: UInt64 {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); _value = newValue; lock.unlock() }
    }
    func matches(_ expected: UInt64) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return _value == expected
    }
}

// MARK: - Mutable open segment

private final class MutableSegment {
    let segmentID: UUID
    let sessionID: UUID
    let trackIdentity: TrackIdentity
    var spotifyPositionStart: TimeInterval
    var spotifyPositionEnd: TimeInterval?
    let hostTimeStart: TimeInterval
    var hostTimeEnd: TimeInterval?
    var audioPTSStart: TimeInterval?
    var audioPTSEnd: TimeInterval?
    var sampleRate: Double = 0
    var channelCount: Int = 0
    var sampleCount: Int = 0
    var bufferCount: Int = 0
    var duration: TimeInterval = 0
    let continuityID: UUID
    let startReason: SegmentBoundaryReason
    var endReason: SegmentBoundaryReason?
    var temporaryPCMReference: String?
    var isContinuous: Bool = true
    let wavWriter: SegmentWAVWriter?

    var identityDigest: String { String(trackIdentity.stableKey.prefix(48)) }

    init(
        segmentID: UUID,
        sessionID: UUID,
        trackIdentity: TrackIdentity,
        spotifyPositionStart: TimeInterval,
        hostTimeStart: TimeInterval,
        continuityID: UUID,
        startReason: SegmentBoundaryReason,
        wavWriter: SegmentWAVWriter? = nil
    ) {
        self.segmentID = segmentID
        self.sessionID = sessionID
        self.trackIdentity = trackIdentity
        self.spotifyPositionStart = spotifyPositionStart
        self.hostTimeStart = hostTimeStart
        self.continuityID = continuityID
        self.startReason = startReason
        self.wavWriter = wavWriter
    }

    func frozen() -> CapturedAudioSegment {
        CapturedAudioSegment(
            segmentID: segmentID,
            sessionID: sessionID,
            trackIdentity: trackIdentity,
            spotifyPositionStart: spotifyPositionStart,
            spotifyPositionEnd: spotifyPositionEnd,
            hostTimeStart: hostTimeStart,
            hostTimeEnd: hostTimeEnd,
            audioPTSStart: audioPTSStart,
            audioPTSEnd: audioPTSEnd,
            sampleRate: sampleRate,
            channelCount: channelCount,
            sampleCount: sampleCount,
            bufferCount: bufferCount,
            duration: duration,
            continuityID: continuityID,
            startReason: startReason,
            endReason: endReason,
            temporaryPCMReference: temporaryPCMReference,
            isContinuous: isContinuous
        )
    }
}
#endif

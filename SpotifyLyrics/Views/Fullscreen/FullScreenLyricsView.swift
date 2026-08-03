import SwiftUI

/// The formal fullscreen renderer.  It is a read-only surface over the live
/// PlaybackState projection; it owns no provider, session, clock, cache, or
/// fullscreen-specific display preferences.
struct FullScreenLyricsView: View {
    @ObservedObject var state: PlaybackState
    @ObservedObject var windowController: FullScreenLyricsWindowController

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lastScrolledLineIndex: Int?
    @State private var draftSeekTime: Double?

    private var liveIdentityKey: String {
        state.currentTrackIdentity?.stableKey ?? "no-live-track"
    }

    private var liveArtworkKey: String {
        state.currentTrack.artworkURL?.absoluteString ?? state.currentTrack.artworkName
    }

    private var surface: FullScreenLyricsSurface {
        FullScreenLyricsPresentation.surface(
            lines: state.liveLyrics,
            state: state.liveLyricsState,
            isSynchronized: state.liveLyricsAreSynchronized,
            currentIndex: state.liveCurrentLineIndex,
            visibleRowBudget: 6
        )
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                background
                    .id("fullscreen-backdrop|\(liveIdentityKey)|\(liveArtworkKey)")

                content(in: geometry)
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .overlay(alignment: .top) {
                topBar
                    .padding(.top, 26)
                    .padding(.horizontal, 34)
                    .opacity(windowController.controlsVisible ? 1 : 0)
                    .allowsHitTesting(windowController.controlsVisible)
            }
            .overlay(alignment: .bottom) {
                if state.currentTrackIdentity != nil {
                    bottomBar
                        .padding(.horizontal, 34)
                        .padding(.bottom, 26 + windowController.extraBottomContentInset)
                        .opacity(windowController.controlsVisible ? 1 : 0)
                        .allowsHitTesting(windowController.controlsVisible)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active:
                    windowController.revealControls()
                case .ended:
                    windowController.scheduleControlsHide()
                }
            }
            .onChange(of: liveIdentityKey) { _, _ in
                lastScrolledLineIndex = nil
                draftSeekTime = nil
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("全屏歌词")
    }

    @ViewBuilder
    private var background: some View {
        if let identity = state.currentTrackIdentity {
            AppleMusicImmersiveV3BackdropView(
                track: state.currentTrack,
                identity: identity
            )
        } else {
            Color.black
                .overlay(Color.white.opacity(0.025))
        }
    }

    private var topBar: some View {
        HStack(spacing: 18) {
            if state.currentTrackIdentity != nil {
                HStack(spacing: 12) {
                    ArtworkView(
                        track: state.currentTrack,
                        size: 42,
                        showsAlbumLabel: false,
                        cornerRadiusRatio: 0.12
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.currentTrack.title)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(state.currentTrack.artist)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.68))
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            Button {
                WindowManager.shared.hideFullScreen()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.82))
            .help("隐藏全屏歌词（Esc）")
            .accessibilityLabel("隐藏全屏歌词")
        }
    }

    @ViewBuilder
    private func content(in geometry: GeometryProxy) -> some View {
        if state.currentTrackIdentity == nil {
            status(title: "等待歌曲", detail: "等待 Spotify 当前歌曲")
        } else {
            switch surface {
            case .synchronized(let currentIndex, let visibleIndices):
                synchronizedRows(
                    currentIndex: currentIndex,
                    visibleIndices: visibleIndices,
                    width: max(420, geometry.size.width * 0.58)
                )
            case .plainText(let statusText, let visibleIndices):
                plainRows(
                    statusText: statusText,
                    visibleIndices: visibleIndices,
                    width: max(360, geometry.size.width * 0.66)
                )
            case .status(let title, let detail):
                status(title: title, detail: detail)
            }
        }
    }

    @ViewBuilder
    private func synchronizedRows(
        currentIndex: Int?,
        visibleIndices: [Int],
        width: CGFloat
    ) -> some View {
        let rows = state.liveLyrics
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(visibleIndices, id: \.self) { index in
                        if rows.indices.contains(index) {
                            let distance = currentIndex.map { abs(index - $0) } ?? 0
                            LyricLineView(
                                line: rows[index],
                                isActive: currentIndex == index,
                                distance: distance,
                                isSynchronized: true,
                                preferences: state.preferences,
                                availableWidth: width,
                                visibleLayerCount: visibleLayerCount(for: rows[index]),
                                language: state.liveLyricsLanguage
                            )
                            .id(rows[index].id)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 42)
                .padding(.vertical, 24)
            }
            .scrollIndicators(.hidden)
            // Replace a live document directly.  This prevents a rapid
            // A→B→A switch from animating rows from the previous song.
            .id("lyrics-document-\(state.liveLyricsSessionRevision)")
            .frame(maxWidth: width, maxHeight: .infinity, alignment: .center)
            .onChange(of: state.currentTime) { _, _ in
                guard let index = state.liveCurrentLineIndex,
                      index != lastScrolledLineIndex,
                      rows.indices.contains(index) else { return }
                lastScrolledLineIndex = index
                LyricsTransitionPolicy.perform(reduceMotion: reduceMotion) {
                    proxy.scrollTo(rows[index].id, anchor: .center)
                }
            }
            .onChange(of: state.preferences) { _, _ in
                guard let index = state.liveCurrentLineIndex,
                      rows.indices.contains(index) else { return }
                lastScrolledLineIndex = index
                LyricsTransitionPolicy.perform(reduceMotion: reduceMotion) {
                    proxy.scrollTo(rows[index].id, anchor: .center)
                }
            }
            .task {
                guard let index = currentIndex,
                      rows.indices.contains(index) else { return }
                lastScrolledLineIndex = index
                proxy.scrollTo(rows[index].id, anchor: .center)
            }
        }
    }

    @ViewBuilder
    private func plainRows(
        statusText: String,
        visibleIndices: [Int],
        width: CGFloat
    ) -> some View {
        let rows = state.liveLyrics
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 10) {
                Text(statusText)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.62))
                    .padding(.bottom, 10)

                ForEach(visibleIndices, id: \.self) { index in
                    if rows.indices.contains(index) {
                        LyricLineView(
                            line: rows[index],
                            isActive: false,
                            distance: 0,
                            isSynchronized: false,
                            preferences: state.preferences,
                            availableWidth: width,
                            visibleLayerCount: visibleLayerCount(for: rows[index]),
                            language: state.liveLyricsLanguage
                        )
                        .id(rows[index].id)
                    }
                }
            }
            .frame(maxWidth: width, alignment: .leading)
            .padding(.horizontal, 42)
            .padding(.vertical, 28)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: width, maxHeight: .infinity, alignment: .center)
    }

    private func status(title: String, detail: String) -> some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
            Text(detail)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.58))
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 560)
        .padding(40)
    }

    private var bottomBar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 18) {
                Button { state.previousTrack() } label: {
                    Image(systemName: "backward.fill")
                }
                .buttonStyle(.plain)
                .help("上一首")

                Button { state.togglePlayPause() } label: {
                    Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .help(state.isPlaying ? "暂停" : "播放")

                Button { state.nextTrack() } label: {
                    Image(systemName: "forward.fill")
                }
                .buttonStyle(.plain)
                .help("下一首")

                Text(timeLabel)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.68))
                    .frame(minWidth: 104, alignment: .leading)
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white.opacity(0.9))

            Slider(value: seekBinding, in: 0...max(1, state.currentTrack.duration), onEditingChanged: seekEditingChanged)
                .controlSize(.small)
                .tint(.white.opacity(0.9))
                .frame(maxWidth: 520)
        }
        .frame(maxWidth: .infinity)
    }

    private var seekBinding: Binding<Double> {
        Binding(
            get: { draftSeekTime ?? max(0, state.currentTime) },
            set: { draftSeekTime = $0 }
        )
    }

    private func seekEditingChanged(_ isEditing: Bool) {
        if isEditing {
            draftSeekTime = max(0, min(state.currentTime, state.currentTrack.duration))
            return
        }

        guard let draftSeekTime else { return }
        self.draftSeekTime = nil
        state.seek(to: draftSeekTime, source: "fullscreen-slider")
    }

    private var timeLabel: String {
        let current = draftSeekTime ?? state.currentTime
        return "\(formatTime(current)) / \(formatTime(state.currentTrack.duration))"
    }

    private func formatTime(_ value: TimeInterval) -> String {
        guard value.isFinite, value >= 0 else { return "00:00" }
        let seconds = Int(value.rounded(.down))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func visibleLayerCount(for line: LyricLine) -> Int {
        let preferences = state.preferences
        var count = preferences.showOriginal && !line.originalText.isEmpty ? 1 : 0
        count += preferences.showTranslation && !(line.translationText ?? "").isEmpty ? 1 : 0
        count += preferences.showRomaji && !(line.romajiText ?? "").isEmpty ? 1 : 0
        count += preferences.showKana && !(line.kanaText ?? "").isEmpty ? 1 : 0
        return max(1, count)
    }
}

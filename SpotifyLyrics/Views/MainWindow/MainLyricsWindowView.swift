import SwiftUI

struct MainLyricsWindowView: View {
    @EnvironmentObject private var state: PlaybackState
    @State private var isPreferencesPresented = false

    var body: some View {
        GeometryReader { _ in
            ZStack {
                TrackBackdropView(
                    track: state.currentTrack,
                    identity: state.currentTrackIdentity,
                    isLiveTrack: state.hasLiveTrack
                )

                VStack(spacing: 0) {
                    header
                        .padding(.horizontal, 28)
                        .padding(.top, 22)
                        .padding(.bottom, 16)

                    Divider()
                        .overlay(LyricsDesignTokens.controlBorder)

                    providerStatusBar
                        .padding(.horizontal, 28)
                        .padding(.top, 10)

                    LyricsCanvasView(state: state)

                    playbackBar
                        .padding(.horizontal, 28)
                        .padding(.bottom, 22)
                }
            }
        }
        .frame(
            minWidth: LyricsDesignTokens.minimumMainWindowSize.width,
            minHeight: LyricsDesignTokens.minimumMainWindowSize.height
        )
        .preferredColorScheme(.dark)
        .task {
            state.startProvider()
        }
    }

    private var header: some View {
        HStack(spacing: LyricsDesignTokens.headerSpacing) {
            windowModeMenu

            TrackHeaderView(track: state.currentTrack)

            Spacer(minLength: 20)

            Button {
                isPreferencesPresented.toggle()
            } label: {
                Label("显示设置", systemImage: "slider.horizontal.3")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(LyricsDesignTokens.secondaryText)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(isPreferencesPresented ? LyricsDesignTokens.controlBackground.opacity(1.5) : .clear)
                    )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isPreferencesPresented, arrowEdge: .top) {
                LyricsPreferencesPopover(
                    preferences: $state.preferences,
                    playbackState: state
                )
            }
            .help("歌词与显示窗口设置")
        }
    }

    private var windowModeMenu: some View {
        Menu {
            Button("主窗口", systemImage: "macwindow") {
                state.currentMode = .mainWindow
            }
            Divider()
            Button("悬浮歌词", systemImage: "rectangle.on.rectangle") {
                WindowManager.shared.toggleFloatingWindow(state: state)
            }
            Button("顶部胶囊", systemImage: "capsule") {
                WindowManager.shared.toggleCapsulePlayer(state: state)
            }
            Button("全屏歌词", systemImage: "arrow.up.left.and.arrow.down.right") {
                WindowManager.shared.toggleFullScreen(state: state)
            }
        } label: {
            Label("窗口模式", systemImage: "rectangle.on.rectangle")
                .labelStyle(.iconOnly)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(LyricsDesignTokens.secondaryText)
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(LyricsDesignTokens.controlBackground)
                        .overlay(Circle().stroke(LyricsDesignTokens.controlBorder, lineWidth: 1))
                )
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .help("窗口模式：主窗口、悬浮歌词、顶部胶囊或全屏歌词")
        .accessibilityLabel("窗口模式")
    }

    private var playbackBar: some View {
        VStack(spacing: 10) {
            Slider(
                value: Binding(
                    get: { state.currentTime },
                    set: { state.seek(to: $0) }
                ),
                in: 0...max(0.1, state.currentTrack.duration)
            )
            .tint(LyricsDesignTokens.accent)

            HStack(spacing: 14) {
                transportButton(
                    systemImage: "backward.fill",
                    label: "上一首",
                    help: state.canControlSpotify ? "上一首" : "Spotify 未连接",
                    isEnabled: state.canControlSpotify
                ) {
                    state.previousTrack()
                }

                Button {
                    state.togglePlayPause()
                } label: {
                    Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(LyricsDesignTokens.primaryText)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(LyricsDesignTokens.controlBackground))
                }
                .buttonStyle(.plain)
                .disabled(!state.canInteractWithPlayback)
                .opacity(state.canInteractWithPlayback ? 1 : 0.42)
                .accessibilityLabel(state.isPlaying ? "暂停" : "播放")

                transportButton(
                    systemImage: "forward.fill",
                    label: "下一首",
                    help: state.canControlSpotify ? "下一首" : "Spotify 未连接",
                    isEnabled: state.canControlSpotify
                ) {
                    state.nextTrack()
                }

                Text("\(formatTime(state.currentTime)) / \(formatTime(state.currentTrack.duration))")
                    .font(.system(size: 12, design: .rounded).monospacedDigit())
                    .foregroundStyle(LyricsDesignTokens.mutedText)

                Spacer()

                Text(state.isPlaying ? "正在播放" : "已暂停")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(LyricsDesignTokens.mutedText)
            }
        }
    }

    private var providerStatusBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(state.canControlSpotify ? Color.green : Color.orange)
                .frame(width: 7, height: 7)

            Text(state.providerStatusMessage)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(LyricsDesignTokens.mutedText)
                .lineLimit(1)

            Spacer(minLength: 8)

            if state.isUsingMockPreview {
                Button("退出 Mock Preview") {
                    state.exitMockPreview()
                }
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .buttonStyle(.borderless)
                .foregroundStyle(LyricsDesignTokens.accent)
                .help("退出 Mock Preview 并恢复真实 Spotify 歌曲会话")
            } else if state.canControlSpotify {
                if case .failed = state.lyricsState {
                    Button("重试歌词") {
                        state.retryLyrics()
                    }
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .buttonStyle(.borderless)
                    .foregroundStyle(LyricsDesignTokens.accent)
                } else if case .noMatch = state.lyricsState {
                    Button("重试歌词") {
                        state.retryLyrics()
                    }
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .buttonStyle(.borderless)
                    .foregroundStyle(LyricsDesignTokens.accent)
                }
            } else {
                Button("进入 Mock Preview") {
                    state.enterMockPreview()
                }
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .buttonStyle(.borderless)
                .foregroundStyle(LyricsDesignTokens.accent)
                .help("明确进入 Mock 预览，不使用真实歌曲歌词")

                Button("重试 Spotify") {
                    state.reconnectSpotify()
                }
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .buttonStyle(.borderless)
                .foregroundStyle(LyricsDesignTokens.accent)
                .help("重新读取 Spotify Desktop 的播放状态")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(LyricsDesignTokens.controlBackground.opacity(0.52))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(LyricsDesignTokens.controlBorder.opacity(0.7), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("播放来源：\(state.providerStatusMessage)")
    }

    private func transportButton(
        systemImage: String,
        label: String,
        help: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(LyricsDesignTokens.primaryText)
                .frame(width: 30, height: 30)
                .background(Circle().fill(LyricsDesignTokens.controlBackground))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.42)
        .accessibilityLabel(label)
        .help(help)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let remainder = Int(seconds) % 60
        return String(format: "%02d:%02d", minutes, remainder)
    }
}

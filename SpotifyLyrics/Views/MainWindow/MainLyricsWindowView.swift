import SwiftUI

struct MainLyricsWindowView: View {
    @EnvironmentObject private var state: PlaybackState
    @State private var isPreferencesPresented = false

    var body: some View {
        GeometryReader { _ in
            ZStack {
                LyricsDesignTokens.backdropGradient
                    .ignoresSafeArea()

                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(0.34)
                    .ignoresSafeArea()

                TrackArtworkView(
                    track: state.currentTrack,
                    size: LyricsDesignTokens.backdropArtworkSize,
                    showsAlbumLabel: false
                )
                .opacity(0.11)
                .blur(radius: 14)
                .rotationEffect(.degrees(-8))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 190)
                .padding(.trailing, 52)
                .allowsHitTesting(false)

                VStack(spacing: 0) {
                    header
                        .padding(.horizontal, 28)
                        .padding(.top, 22)
                        .padding(.bottom, 16)

                    Divider()
                        .overlay(LyricsDesignTokens.controlBorder)

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
                in: 0...state.currentTrack.duration
            )
            .tint(LyricsDesignTokens.accent)

            HStack(spacing: 14) {
                transportButton(
                    systemImage: "backward.fill",
                    label: "上一首",
                    help: "单曲 Mock 暂无上一首",
                    isEnabled: false
                ) {}

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
                .accessibilityLabel(state.isPlaying ? "暂停" : "播放")

                transportButton(
                    systemImage: "forward.fill",
                    label: "下一首",
                    help: "单曲 Mock 暂无下一首",
                    isEnabled: false
                ) {}

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

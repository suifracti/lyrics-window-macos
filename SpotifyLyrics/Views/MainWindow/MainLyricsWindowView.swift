import SwiftUI

struct MainLyricsWindowView: View {
    @EnvironmentObject private var state: PlaybackState
    @AppStorage("mainWindowLayoutStyle") private var layoutStyleRawValue = MainWindowLayoutStyle.lyricsFocus.rawValue
    @State private var isPreferencesPresented = false
    @State private var isSearchPresented = false

    private var layoutStyle: MainWindowLayoutStyle {
        MainWindowLayoutStyle(rawValue: layoutStyleRawValue) ?? .lyricsFocus
    }

    var body: some View {
        GeometryReader { geometry in
            let topBarHeight: CGFloat = layoutStyle == .lyricsFocus ? 116 : 68
            let contentHeight = max(0, geometry.size.height - topBarHeight)

            ZStack(alignment: .top) {
                ArtworkBackgroundView(state: state)

                layoutBody
                    .frame(maxWidth: .infinity)
                    .frame(height: contentHeight, alignment: .top)
                    .offset(y: topBarHeight)

                VStack(spacing: 0) {
                    topBar
                        .padding(.horizontal, LyricsDesignTokens.immersiveWindowPadding)
                        .padding(.top, 18)
                        .padding(.bottom, 14)

                    Divider()
                        .overlay(LyricsDesignTokens.controlBorder)

                }
                .frame(height: topBarHeight)
                .background(Color.black.opacity(0.14))
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

    @ViewBuilder
    private var layoutBody: some View {
        switch layoutStyle {
        case .lyricsFocus:
            lyricsFocusLayout
        case .immersiveSplit:
            ImmersiveSplitWindowView(state: state)
        }
    }

    private var topBar: some View {
        HStack(spacing: LyricsDesignTokens.headerSpacing) {
            windowModeMenu

            if layoutStyle == .lyricsFocus {
                TrackHeaderView(track: state.currentTrack)
            } else {
                HStack(spacing: 10) {
                    Image(systemName: MainWindowLayoutStyle.immersiveSplit.systemImage)
                        .foregroundStyle(LyricsDesignTokens.accent)
                    Text(MainWindowLayoutStyle.immersiveSplit.title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(LyricsDesignTokens.primaryText)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("当前主窗口布局：沉浸分栏")
            }

            Spacer(minLength: 20)

            providerStatusMenu
            searchButton
            layoutMenu
            preferencesButton
        }
    }

    private var lyricsFocusLayout: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                if !state.canControlSpotify || state.isUsingMockPreview {
                    providerRecoveryBar
                        .padding(.horizontal, LyricsDesignTokens.immersiveWindowPadding)
                        .padding(.top, 10)
                }

                LyricsViewport(state: state)
            }

            PlaybackControlsView(state: state)
                .padding(.horizontal, LyricsDesignTokens.immersiveWindowPadding)
                .padding(.top, 10)
                .padding(.bottom, 22)
                .frame(maxWidth: .infinity)
                .background(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.02),
                            Color.black.opacity(0.52)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .allowsHitTesting(false)
                )
        }
    }

    private var preferencesButton: some View {
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
        .accessibilityLabel("显示设置")
    }

    private var searchButton: some View {
        Button {
            isSearchPresented.toggle()
        } label: {
            Label("搜索歌曲", systemImage: "magnifyingglass")
                .labelStyle(.iconOnly)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(LyricsDesignTokens.secondaryText)
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(isSearchPresented ? LyricsDesignTokens.controlBackground.opacity(1.5) : .clear)
                )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isSearchPresented, arrowEdge: .top) {
            SongSearchPopover(
                manager: state.songSearchManager,
                playbackState: state
            )
        }
        .help("搜索歌曲或歌词")
        .accessibilityLabel("搜索歌曲")
    }

    private var layoutMenu: some View {
        Menu {
            Section("主窗口布局") {
                ForEach(MainWindowLayoutStyle.allCases) { style in
                    Button {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            layoutStyleRawValue = style.rawValue
                        }
                    } label: {
                        Label(style.title, systemImage: style.systemImage)
                    }
                }
            }
        } label: {
            Label("布局：\(layoutStyle.title)", systemImage: layoutStyle.systemImage)
                .labelStyle(.iconOnly)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(LyricsDesignTokens.secondaryText)
                .frame(width: 36, height: 36)
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .help("切换主窗口布局，不会重置播放或歌词位置")
        .accessibilityLabel("主窗口布局：\(layoutStyle.title)")
    }

    private var providerStatusMenu: some View {
        Menu {
            Text(state.providerStatusMessage)

            if state.isUsingMockPreview {
                Button("退出 Mock Preview") {
                    state.exitMockPreview()
                }
            } else if state.canControlSpotify {
                if case .failed = state.lyricsState {
                    Button("重新搜索歌词") {
                        state.retryLyrics()
                    }
                } else if case .noMatch = state.lyricsState {
                    Button("重新搜索歌词") {
                        state.retryLyrics()
                    }
                }
            } else {
                Button("进入 Mock Preview") {
                    state.enterMockPreview()
                }
                Button("重试 Spotify") {
                    state.reconnectSpotify()
                }
            }
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(state.canControlSpotify ? Color.green : Color.orange)
                    .frame(width: 7, height: 7)
                Text(state.canControlSpotify ? "Spotify 已连接" : "播放来源")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(LyricsDesignTokens.mutedText)
                    .lineLimit(1)
            }
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .help("播放来源与歌词重试")
        .accessibilityLabel("播放来源：\(state.providerStatusMessage)")
    }

    private var providerRecoveryBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(state.isUsingMockPreview ? Color.orange : Color.orange.opacity(0.86))
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
                .buttonStyle(.borderless)
                .foregroundStyle(LyricsDesignTokens.accent)
            } else {
                Button("进入 Mock Preview") {
                    state.enterMockPreview()
                }
                .buttonStyle(.borderless)
                .foregroundStyle(LyricsDesignTokens.accent)

                Button("重试 Spotify") {
                    state.reconnectSpotify()
                }
                .buttonStyle(.borderless)
                .foregroundStyle(LyricsDesignTokens.accent)
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
}

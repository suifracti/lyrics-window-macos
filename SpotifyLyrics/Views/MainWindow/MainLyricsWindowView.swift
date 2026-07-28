import SwiftUI

struct MainLyricsWindowView: View {
    @EnvironmentObject private var state: PlaybackState
    @AppStorage("mainWindowLayoutStyle") private var layoutStyleRawValue = MainWindowLayoutStyle.immersiveSplit.rawValue
    @State private var isPreferencesPresented = false
    @State private var isSearchPresented = false

    private var layoutStyle: MainWindowLayoutStyle {
        MainWindowLayoutStyle(rawValue: layoutStyleRawValue) ?? .immersiveSplit
    }

    var body: some View {
        Group {
            if layoutStyle == .appleMusicImmersiveV3 {
                AppleMusicImmersiveV3WindowView(state: state)
            } else {
                legacyWindowBody
            }
        }
        .frame(
            minWidth: layoutStyle == .appleMusicImmersiveV3 ? 800 : LyricsDesignTokens.minimumMainWindowSize.width,
            minHeight: layoutStyle == .appleMusicImmersiveV3 ? 600 : LyricsDesignTokens.minimumMainWindowSize.height
        )
        .preferredColorScheme(.dark)
        .background(Color.clear)
        .task {
            state.startProvider()
        }
    }

    private var legacyWindowBody: some View {
        GeometryReader { geometry in
            let topBarHeight: CGFloat = layoutStyle == .lyricsFocus ? 116 : 64
            let contentHeight = max(0, geometry.size.height - topBarHeight)

            ZStack(alignment: .top) {
                ArtworkBackgroundView(state: state)

                layoutBody
                    .animation(.easeInOut(duration: 0.24), value: layoutStyle)
                    .frame(maxWidth: .infinity)
                    .frame(height: contentHeight, alignment: .top)
                    .offset(y: topBarHeight)

                VStack(spacing: 0) {
                    topBar
                        .padding(.horizontal, LyricsDesignTokens.immersiveWindowPadding)
                        .padding(.top, layoutStyle == .lyricsFocus ? 18 : 8)
                        .padding(.bottom, layoutStyle == .lyricsFocus ? 14 : 8)

                    Divider()
                        .overlay(LyricsDesignTokens.controlBorder)

                }
                .frame(height: topBarHeight)
                .background {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .opacity(layoutStyle == .lyricsFocus ? 0.22 : 0.14)
                }
            }
        }
    }

    @ViewBuilder
    private var layoutBody: some View {
        switch layoutStyle {
        case .lyricsFocus:
            lyricsFocusLayout
        case .immersiveSplit:
            ImmersiveSplitWindowView(state: state)
        case .appleMusicImmersiveV3:
            EmptyView()
        }
    }

    private var topBar: some View {
        HStack(spacing: LyricsDesignTokens.headerSpacing) {
            windowModeMenu

            if layoutStyle == .lyricsFocus {
                TrackHeaderView(track: state.currentTrack)
            } else {
                Image(systemName: MainWindowLayoutStyle.immersiveSplit.systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(LyricsDesignTokens.accent)
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
                let showAutoComplete: Bool = {
                    switch state.lyricsState {
                    case .failed, .noMatch, .noLyrics, .alignmentQueued, .alignmentRunning, .alignmentPreview, .candidates, .loading:
                        return true
                    default:
                        return false
                    }
                }()
                if showAutoComplete {
                    Button("自动补全歌词") {
                        state.autoCompleteLyrics()
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
            Circle()
                .fill(state.canControlSpotify ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
                .padding(14)
                .background(
                    Circle()
                        .fill(LyricsDesignTokens.controlBackground.opacity(0.58))
                )
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

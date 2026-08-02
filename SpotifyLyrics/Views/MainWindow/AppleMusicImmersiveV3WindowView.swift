import SwiftUI

enum MainWindowResponsiveThresholds {
    static let technicalMinimumSize = LyricsDesignTokens.technicalMinimumMainWindowSize
    static let comfortableMinimumSize = LyricsDesignTokens.comfortableMainWindowSize
    // Compatibility aliases for callers and older contracts.
    static let minimumWidth: CGFloat = technicalMinimumSize.width
    static let minimumHeight: CGFloat = technicalMinimumSize.height
    static let wideBreakpoint: CGFloat = 1_080
    static let compactLyricsFocusWidth: CGFloat = 900
    static let compactLyricsFocusHeight: CGFloat = 640
    static let toolbarRevealHeight: CGFloat = 96
}

/// Independent Apple Music-inspired main canvas. V2 and Lyrics Focus remain
/// separate layouts; this view owns only the V3 canvas and its transient tools.
struct AppleMusicImmersiveV3WindowView: View {
    @ObservedObject var state: PlaybackState
    @Binding var layoutStyleRawValue: String
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var settings: AppSettingsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isSearchPresented = false
    // The canvas starts clean. Controls reveal only when the pointer reaches
    // the top edge, so playback remains content-first without sacrificing
    // access to search, layout, and settings.
    @State private var toolsVisible = false
    @State private var interactionToken = 0
    @State private var isAlignmentDetailsPresented = false

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
                AppleMusicImmersiveV3BackdropView(
                    track: state.currentTrack,
                    identity: state.currentTrackIdentity
                )

                layout(for: geometry)

                toolBar
                    .padding(.top, 18)
                    .padding(.trailing, 26)
                    .opacity(toolsVisible ? 1 : 0)
                    .allowsHitTesting(toolsVisible)
                    .animation(
                        LyricsDesignTokens.Motion.animation(reduceMotion: reduceMotion),
                        value: toolsVisible
                    )
            }
            .contentShape(Rectangle())
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let location) where location.y <= MainWindowResponsiveThresholds.toolbarRevealHeight:
                    revealTools()
                case .active(_), .ended:
                    break
                }
            }
            .task(id: interactionToken) {
                guard interactionToken > 0 else { return }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(LyricsDesignTokens.Motion.animation(reduceMotion: reduceMotion)) {
                    toolsVisible = false
                }
            }
        }
        .frame(
            minWidth: MainWindowResponsiveThresholds.technicalMinimumSize.width,
            minHeight: MainWindowResponsiveThresholds.technicalMinimumSize.height
        )
        .preferredColorScheme(.dark)
        .sheet(isPresented: $isAlignmentDetailsPresented) {
            if let report = state.liveLyricsState.alignmentReport {
                AlignmentPreviewView(report: report)
            }
        }
    }

    @ViewBuilder
    private func layout(for geometry: GeometryProxy) -> some View {
        switch MainWindowResponsiveMode.resolve(
            width: geometry.size.width,
            height: geometry.size.height,
            automaticLyricsFocus: settings.automaticCompactLyricsFocus,
            wideBreakpoint: MainWindowResponsiveThresholds.wideBreakpoint,
            comfortableSize: MainWindowResponsiveThresholds.comfortableMinimumSize,
            compactFocusWidth: MainWindowResponsiveThresholds.compactLyricsFocusWidth,
            compactFocusHeight: MainWindowResponsiveThresholds.compactLyricsFocusHeight
        ) {
        case .wide:
            wideLayout(in: geometry)
        case .medium:
            mediumLayout(in: geometry)
        case .small:
            smallLayout(in: geometry)
        case .lyricsFocus:
            compactLyricsFocusLayout(in: geometry)
        }
    }

    // Compatibility helpers retained for the Phase 2.2 contract and for
    // diagnostics that name the automatic projection explicitly. The actual
    // layout selection is centralized in MainWindowResponsiveMode.resolve.
    private func isAutomaticCompactLyricsFocus(in geometry: GeometryProxy) -> Bool {
        MainWindowResponsiveMode.resolve(
            width: geometry.size.width,
            height: geometry.size.height,
            automaticLyricsFocus: settings.automaticCompactLyricsFocus,
            wideBreakpoint: MainWindowResponsiveThresholds.wideBreakpoint,
            comfortableSize: MainWindowResponsiveThresholds.comfortableMinimumSize,
            compactFocusWidth: MainWindowResponsiveThresholds.compactLyricsFocusWidth,
            compactFocusHeight: MainWindowResponsiveThresholds.compactLyricsFocusHeight
        ) == .lyricsFocus
    }

    private func compactLyricsFocus(in geometry: GeometryProxy) -> Bool {
        isAutomaticCompactLyricsFocus(in: geometry)
    }

    private func compactLyricsFocusLayout(in geometry: GeometryProxy) -> some View {
        ZStack(alignment: .topTrailing) {
            lyricsColumn(
                width: max(1, geometry.size.width - 48),
                compact: true,
                lyricsFocus: true,
                onSearch: { isSearchPresented = true }
            )
            .padding(.horizontal, LyricsDesignTokens.Spacing.windowSmall)
            .padding(.top, LyricsDesignTokens.Spacing.xl + 18)
            .padding(.bottom, LyricsDesignTokens.Spacing.xl + 22)

            VStack(spacing: 0) {
                HStack(spacing: LyricsDesignTokens.Spacing.xs) {
                    searchButton
                    preferencesButton
                }
                .padding(.top, LyricsDesignTokens.Spacing.md + 2)
                .padding(.horizontal, LyricsDesignTokens.Spacing.windowSmall)

                Spacer()

                AppleMusicImmersiveV3FocusTransportControls(
                    state: state,
                    reduceMotion: reduceMotion
                )
                .padding(.bottom, LyricsDesignTokens.Spacing.md)
            }
        }
    }

    private func wideLayout(in geometry: GeometryProxy) -> some View {
        let horizontalPadding = LyricsDesignTokens.Spacing.windowWide
        let verticalPadding = LyricsDesignTokens.Spacing.xl + LyricsDesignTokens.Spacing.sm
        let contentWidth = max(1, geometry.size.width - horizontalPadding * 2)
        let leftWidth = contentWidth * 0.45
        let rightWidth = contentWidth * 0.55
        let coverSize = min(leftWidth * 0.84, geometry.size.height * 0.52)

        return HStack(spacing: 0) {
            trackColumn(
                width: leftWidth,
                availableHeight: geometry.size.height - verticalPadding * 2,
                coverSize: coverSize,
                alignment: .leading,
                compact: false,
                progressDensity: .wide
            )
            .frame(width: leftWidth)
            .frame(maxHeight: .infinity)

            lyricsColumn(width: rightWidth, compact: false)
                .frame(width: rightWidth)
                .frame(maxHeight: .infinity)
        }
        .frame(
            width: contentWidth,
            height: max(1, geometry.size.height - verticalPadding * 2),
            alignment: .center
        )
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
    }

    private func mediumLayout(in geometry: GeometryProxy) -> some View {
        let horizontalPadding = LyricsDesignTokens.Spacing.windowMedium
        let verticalPadding = LyricsDesignTokens.Spacing.xl + LyricsDesignTokens.Spacing.xxs
        let contentWidth = max(1, geometry.size.width - horizontalPadding * 2)
        let leftWidth = contentWidth * 0.4
        let rightWidth = contentWidth * 0.6
        let coverSize = min(leftWidth * 0.76, geometry.size.height * 0.42)

        return HStack(spacing: 0) {
            trackColumn(
                width: leftWidth,
                availableHeight: geometry.size.height - verticalPadding * 2,
                coverSize: max(190, coverSize),
                alignment: .leading,
                compact: true,
                progressDensity: .medium
            )
            .frame(width: leftWidth)
            .frame(maxHeight: .infinity)

            lyricsColumn(width: rightWidth, compact: true)
                .frame(width: rightWidth)
                .frame(maxHeight: .infinity)
        }
        .frame(
            width: contentWidth,
            height: max(1, geometry.size.height - verticalPadding * 2),
            alignment: .center
        )
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
    }

    private func smallLayout(in geometry: GeometryProxy) -> some View {
        let horizontalPadding = LyricsDesignTokens.Spacing.windowSmall
        let coverSize = min(geometry.size.width * 0.62, geometry.size.height * 0.34)

        return ScrollView(.vertical) {
            VStack(alignment: .center, spacing: LyricsDesignTokens.Spacing.lg) {
                trackColumn(
                    width: geometry.size.width - horizontalPadding * 2,
                    availableHeight: coverSize + 190,
                    coverSize: max(180, coverSize),
                    alignment: .center,
                    compact: true,
                    progressDensity: .small
                )
                .frame(maxWidth: .infinity)

                lyricsColumn(
                    width: geometry.size.width - horizontalPadding * 2,
                    compact: true
                )
                .frame(minHeight: max(420, geometry.size.height * 0.62))
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, LyricsDesignTokens.Spacing.xl + LyricsDesignTokens.Spacing.xxs)
        }
        .scrollIndicators(.hidden)
    }

    private func trackColumn(
        width: CGFloat,
        availableHeight: CGFloat,
        coverSize: CGFloat,
        alignment: HorizontalAlignment,
        compact: Bool,
        progressDensity: AppleMusicImmersiveV3ProgressDensity
    ) -> some View {
        VStack(alignment: alignment, spacing: 0) {
            ArtworkView(
                track: state.currentTrack,
                size: coverSize,
                showsAlbumLabel: false,
                cornerRadiusRatio: 0.04
            )
            .frame(maxWidth: width, alignment: alignment == .center ? .center : .leading)

            Spacer().frame(height: compact ? LyricsDesignTokens.Spacing.lg - 2 : LyricsDesignTokens.Spacing.xl)

            TrackMetadataView(
                track: state.currentTrack,
                titleSize: min(compact ? 26 : 30, max(compact ? 18 : 22, coverSize * 0.075)),
                alignment: alignment
            )
            .frame(maxWidth: width, alignment: alignment == .center ? .center : .leading)

            Spacer().frame(height: compact ? LyricsDesignTokens.Spacing.md + 2 : LyricsDesignTokens.Spacing.lg)

            AppleMusicImmersiveV3TransportControls(
                state: state,
                alignment: alignment,
                progressDensity: progressDensity
            )
            .frame(maxWidth: width, alignment: alignment == .center ? .center : .leading)
        }
        // Give the column the actual content height. Without an explicit
        // proposal, the two flexible spacers can resolve against the
        // intrinsic height of the lyrics column and push metadata/transport
        // below the window on a 760pt-tall canvas.
        .frame(
            width: width,
            height: max(1, availableHeight),
            alignment: .center
        )
    }

    private func lyricsColumn(
        width: CGFloat,
        compact: Bool,
        lyricsFocus: Bool = false,
        onSearch: (() -> Void)? = nil
    ) -> some View {
        AppleMusicImmersiveV3LyricsViewport(
            state: state,
            availableWidth: max(240, width - (compact ? 22 : 34)),
            compact: compact,
            lyricsFocus: lyricsFocus,
            onSearch: onSearch
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var toolBar: some View {
        HStack(spacing: LyricsDesignTokens.Spacing.xs) {
            windowModeMenu
            providerStatusMenu
            searchButton
            layoutMenu
            preferencesButton
        }
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(.white.opacity(LyricsDesignTokens.Material.primaryTextOpacity))
    }

    private var windowModeMenu: some View {
        Menu {
            Button("主窗口", systemImage: "macwindow") {
                state.currentMode = .mainWindow
            }
            Divider()
            Button("悬浮歌词", systemImage: "rectangle.on.rectangle") {
                WindowManager.shared.toggleFloatingLyrics(state: state)
            }
            Menu("悬浮歌词交互") {
                Button("可编辑 / 可拖动") {
                    WindowManager.shared.setFloatingInteractionMode(.interactive, state: state)
                }
                Button("锁定展示") {
                    WindowManager.shared.setFloatingInteractionMode(.locked, state: state)
                }
                Button("启用鼠标穿透") {
                    WindowManager.shared.setFloatingInteractionMode(.passThrough, state: state)
                }
                Divider()
                Button("解除鼠标穿透") {
                    WindowManager.shared.restoreFloatingInteractiveMode(state: state)
                }
            }
            Button("顶部胶囊", systemImage: "capsule") {
                WindowManager.shared.toggleCapsule(state: state)
            }
            Button("全屏歌词", systemImage: "arrow.up.left.and.arrow.down.right") {
                WindowManager.shared.toggleFullScreen(state: state)
            }
        } label: {
            iconLabel("rectangle.on.rectangle", description: "窗口模式")
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .accessibilityLabel("窗口模式")
    }

    private var providerStatusMenu: some View {
        Menu {
            Text(state.providerStatusMessage)
            if state.canOpenLyricsEditor {
                Button("编辑当前歌词", systemImage: "pencil.and.list.clipboard") {
                    state.prepareLyricsEditor()
                    openWindow(id: "lyrics-editor")
                }
            }
            lyricsVersionMenuContent
            translationMenuContent
            alignmentMenuContent

            if state.isUsingMockPreview {
                Button("退出 Mock Preview") { state.exitMockPreview() }
            } else if !state.canControlSpotify {
                Button("进入 Mock Preview") { state.enterMockPreview() }
                Button("重试 Spotify") { state.reconnectSpotify() }
            } else {
                Button("自动补全歌词") { state.autoCompleteLyrics() }
            }
        } label: {
            Circle()
                .fill(state.canControlSpotify ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
                .frame(width: 32, height: 32)
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .help("播放来源与歌词工具")
        .accessibilityLabel("播放来源：\(state.providerStatusMessage)")
    }

    @ViewBuilder
    private var lyricsVersionMenuContent: some View {
        Divider()
        Menu("歌词版本") {
            Button("无歌词版本") { state.selectNoLyricsVersion() }
                .disabled(state.isLyricsSelectionEmpty)
            Text(state.isLyricsSelectionEmpty ? "当前会话未选择版本" : "当前会话使用已采用版本")
        }
    }

    @ViewBuilder
    private var translationMenuContent: some View {
        if !state.liveLyrics.isEmpty {
            Divider()
            switch state.translationState {
            case .loading:
                Text("翻译：正在翻译整首歌词…")
            case .unavailable:
                Text("翻译：未配置 AI 翻译")
                Button("翻译") { state.translateCurrentLyrics() }
            case .failed:
                Text("翻译：上次请求失败")
                Button("重试翻译") { state.translateCurrentLyrics() }
            case .idle:
                Text(state.isTranslationSelectionEmpty ? "翻译：未选择版本" : "翻译：暂无版本")
                Button("翻译") { state.translateCurrentLyrics() }
            case .loaded:
                Text(state.isTranslationSelectionEmpty ? "翻译：未选择版本" : "翻译：已加载")
                Button("重新翻译") { state.retranslateCurrentLyrics() }
            }
            Menu("翻译版本") {
                Button("无翻译版本") { state.selectNoTranslationVersion() }
                    .disabled(state.isTranslationSelectionEmpty)
                if !state.translationVersions.isEmpty { Divider() }
                ForEach(state.translationVersions, id: \.record.id) { version in
                    Button {
                        state.selectTranslation(versionID: version.record.id)
                    } label: {
                        Text("\(version.record.model.isEmpty ? version.record.sourceKind.rawValue : version.record.model) · \(version.record.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    }
                }
                if state.selectedTranslation?.record.isLocked == false {
                    Divider()
                    Button("锁定当前版本") { state.lockSelectedTranslation() }
                    Button("删除当前版本", role: .destructive) { state.deleteSelectedTranslation() }
                }
            }
        }
    }

    @ViewBuilder
    private var alignmentMenuContent: some View {
        switch state.liveLyricsState {
        case .alignmentQueued:
            Divider()
            Text("歌词：待对齐时间轴")
            Button("自动排轴") { state.alignCurrentLyricsWithLocalAudio() }
        case .alignmentRunning:
            Divider()
            Text("歌词：正在排轴")
            Button("取消排轴") { state.cancelAlignmentPreview() }
        case .alignmentPreview:
            Divider()
            Text("歌词：排轴预览")
            Button("查看逐行证据") { isAlignmentDetailsPresented = true }
            Button("确认并保存") { state.confirmAlignmentPreview(saveLocal: true) }
            Button("放弃排轴") { state.cancelAlignmentPreview() }
        case .loaded, .mockPreview:
            EmptyView()
        default:
            Divider()
            Text("歌词：\(state.liveLyricsStatusMessage)")
        }
    }

    private var searchButton: some View {
        Button {
            isSearchPresented.toggle()
        } label: {
            iconLabel("magnifyingglass", description: "搜索歌曲")
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isSearchPresented, arrowEdge: .top) {
            SongSearchPopover(
                manager: state.songSearchManager,
                playbackState: state
            )
        }
        .accessibilityLabel("搜索歌曲")
    }

    private var layoutMenu: some View {
        Menu {
            Section("主窗口布局") {
                ForEach(MainWindowLayoutStyle.allCases) { style in
                    Button {
                        layoutStyleRawValue = style.rawValue
                    } label: {
                        Label(style.title, systemImage: style.systemImage)
                    }
                }
            }
        } label: {
            iconLabel("rectangle.split.2x1", description: "主窗口布局")
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .accessibilityLabel("主窗口布局：Apple Music 沉浸 V3")
    }

    private var preferencesButton: some View {
        SettingsLink {
            iconLabel("slider.horizontal.3", description: "显示设置")
        }
        .accessibilityLabel("显示设置")
    }

    private func iconLabel(_ systemImage: String, description: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.white.opacity(0.82))
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
            .help(description)
    }

    private func revealTools() {
        if !toolsVisible {
            withAnimation(LyricsDesignTokens.Motion.animation(reduceMotion: reduceMotion)) {
                toolsVisible = true
            }
        }
        interactionToken &+= 1
    }
}

private enum AppleMusicImmersiveV3ProgressDensity: Equatable {
    case wide
    case medium
    case small
    case focus

    var containerHeight: CGFloat {
        switch self {
        case .wide: return 12
        case .medium: return 11
        case .small: return 9
        case .focus: return 8
        }
    }

    var trackHeight: CGFloat {
        switch self {
        case .wide, .medium: return LyricsDesignTokens.Progress.trackHeight
        case .small, .focus: return LyricsDesignTokens.Progress.compactTrackHeight
        }
    }

    var isFocus: Bool { self == .focus }
}

/// A restrained playback rail shared by every V3 size projection. It owns no
/// clock and only sends an explicit seek after the user finishes editing.
private struct AppleMusicImmersiveV3PlaybackProgress: View {
    @ObservedObject var state: PlaybackState
    let density: AppleMusicImmersiveV3ProgressDensity
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isHovered = false
    @State private var isEditing = false
    @State private var draftPosition: Double = 0

    private var duration: Double {
        max(0.1, state.currentTrack.duration)
    }

    private var visiblePosition: Double {
        let rawValue = isEditing ? draftPosition : state.currentTime
        return min(max(rawValue, 0), duration)
    }

    private var progressFraction: Double {
        min(max(visiblePosition / duration, 0), 1)
    }

    private var isEmphasized: Bool { isHovered || isEditing }

    var body: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width)
            let trackHeight = isEmphasized
                ? LyricsDesignTokens.Progress.hoverTrackHeight
                : density.trackHeight
            let activeWidth = max(trackHeight, width * progressFraction)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(
                        isEmphasized
                            ? LyricsDesignTokens.Progress.hoverInactiveOpacity
                            : LyricsDesignTokens.Progress.inactiveOpacity
                    ))
                    .frame(height: trackHeight)

                Capsule()
                    .fill(Color.white.opacity(
                        isEmphasized
                            ? LyricsDesignTokens.Progress.hoverActiveOpacity
                            : LyricsDesignTokens.Progress.activeOpacity
                    ))
                    .frame(width: activeWidth, height: trackHeight)

                if isEmphasized {
                    Circle()
                        .fill(.white)
                        .frame(
                            width: LyricsDesignTokens.Progress.hoverThumbSize,
                            height: LyricsDesignTokens.Progress.hoverThumbSize
                        )
                        .offset(x: min(max(activeWidth - LyricsDesignTokens.Progress.hoverThumbSize / 2, 0), width - LyricsDesignTokens.Progress.hoverThumbSize / 2))
                }

                // The native control remains the accessibility and input
                // surface; the custom rail above keeps the resting visual
                // quiet without introducing a second seek implementation.
                Slider(
                    value: Binding(
                        get: { visiblePosition },
                        set: { draftPosition = min(max($0, 0), duration) }
                    ),
                    in: 0...duration,
                    onEditingChanged: handleEditingChanged
                )
                .labelsHidden()
                .tint(.clear)
                .opacity(0.01)
                .accessibilityLabel("播放进度")
            }
            .contentShape(Rectangle())
            .onHover { hovering in
                withAnimation(LyricsDesignTokens.Motion.animation(reduceMotion: reduceMotion, duration: 0.14)) {
                    isHovered = hovering
                }
            }
        }
        .frame(
            width: density.isFocus ? LyricsDesignTokens.Progress.focusWidth : nil,
            height: density.containerHeight
        )
        .frame(maxWidth: density.isFocus ? nil : .infinity)
        .animation(
            LyricsDesignTokens.Motion.animation(reduceMotion: reduceMotion, duration: 0.14),
            value: isEmphasized
        )
    }

    private func handleEditingChanged(_ editing: Bool) {
        if editing {
            draftPosition = min(max(state.currentTime, 0), duration)
            isEditing = true
            return
        }

        guard isEditing else { return }
        isEditing = false
        state.seek(to: min(max(draftPosition, 0), duration), source: "v3-progress-slider")
    }
}

private struct AppleMusicImmersiveV3TransportControls: View {
    @ObservedObject var state: PlaybackState
    let alignment: HorizontalAlignment
    let progressDensity: AppleMusicImmersiveV3ProgressDensity

    var body: some View {
        VStack(alignment: alignment, spacing: LyricsDesignTokens.Spacing.sm + 1) {
            AppleMusicImmersiveV3PlaybackProgress(
                state: state,
                density: progressDensity
            )

            HStack(spacing: LyricsDesignTokens.Spacing.md + 2) {
                v3TransportButton("backward.fill", label: "上一首", enabled: state.canControlSpotify) {
                    state.previousTrack()
                }

                Button {
                    state.togglePlayPause()
                } label: {
                    Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .disabled(!state.canInteractWithPlayback)
                .opacity(state.canInteractWithPlayback ? 1 : 0.42)
                .accessibilityLabel(state.isPlaying ? "暂停" : "播放")

                v3TransportButton("forward.fill", label: "下一首", enabled: state.canControlSpotify) {
                    state.nextTrack()
                }

                Text("\(formatTime(state.currentTime)) / \(formatTime(state.currentTrack.duration))")
                    .font(.system(size: 12, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(LyricsDesignTokens.Material.secondaryTextOpacity))
                    .padding(.leading, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)
    }

    private func v3TransportButton(
        _ systemImage: String,
        label: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityLabel(label)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let remainder = Int(seconds) % 60
        return String(format: "%02d:%02d", minutes, remainder)
    }
}

private struct AppleMusicImmersiveV3FocusTransportControls: View {
    @ObservedObject var state: PlaybackState
    let reduceMotion: Bool

    var body: some View {
        HStack(spacing: LyricsDesignTokens.Spacing.sm) {
            Button {
                state.togglePlayPause()
            } label: {
                Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.white.opacity(0.10)))
            }
            .buttonStyle(.plain)
            .disabled(!state.canInteractWithPlayback)
            .opacity(state.canInteractWithPlayback ? 1 : 0.42)
            .accessibilityLabel(state.isPlaying ? "暂停" : "播放")

            Text(state.isPlaying ? "正在播放" : "已暂停")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.62))

            AppleMusicImmersiveV3PlaybackProgress(
                state: state,
                density: .focus
            )

            Text("\(formatTime(state.currentTime)) / \(formatTime(state.currentTrack.duration))")
                .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(.white.opacity(0.46))
        }
        .padding(.horizontal, LyricsDesignTokens.Spacing.sm)
        .padding(.vertical, LyricsDesignTokens.Spacing.xs)
        .background(Color.black.opacity(0.16), in: Capsule())
        .animation(
            LyricsDesignTokens.Motion.animation(reduceMotion: reduceMotion, duration: 0.16),
            value: state.isPlaying
        )
        .accessibilityElement(children: .contain)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let remainder = Int(seconds) % 60
        return String(format: "%02d:%02d", minutes, remainder)
    }
}

private struct AppleMusicImmersiveV3LyricProgressStatus: View {
    enum Mode: Equatable {
        case synchronized
        case plainText
    }

    let mode: Mode
    let currentIndex: Int?

    private var title: String {
        switch mode {
        case .synchronized:
            return currentIndex == nil ? "同步歌词 · 前奏" : "同步歌词"
        case .plainText:
            return "纯文本 · 未排轴"
        }
    }

    private var icon: String {
        switch mode {
        case .synchronized: return "waveform"
        case .plainText: return "text.alignleft"
        }
    }

    var body: some View {
        Label(title, systemImage: icon)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(
                mode == .synchronized
                    ? LyricsDesignTokens.Material.secondaryTextOpacity
                    : LyricsDesignTokens.Material.mutedTextOpacity
            ))
            .accessibilityLabel(title)
    }
}

private struct AppleMusicImmersiveV3LyricsViewport: View {
    @ObservedObject var state: PlaybackState
    let availableWidth: CGFloat
    let compact: Bool
    let lyricsFocus: Bool
    let onSearch: (() -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: LyricsDesignTokens.Spacing.xs) {
            if !state.liveLyrics.isEmpty {
                AppleMusicImmersiveV3LyricProgressStatus(
                    mode: state.liveLyricsAreSynchronized ? .synchronized : .plainText,
                    currentIndex: state.liveLyricsAreSynchronized ? state.liveCurrentLineIndex : nil
                )
                .padding(.leading, 2)
            }

            if state.liveLyrics.isEmpty {
                if lyricsFocus {
                    focusEmptyState
                } else {
                    emptyState
                }
            } else {
                lyricsScroll
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var focusEmptyState: some View {
        VStack(spacing: LyricsDesignTokens.Spacing.md) {
            Spacer(minLength: 0)

            Image(systemName: "text.quote")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.white.opacity(0.48))

            Text(emptyTitle)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))

            if let onSearch {
                HStack(spacing: LyricsDesignTokens.Spacing.sm) {
                    Button(action: onSearch) {
                        Label("搜索歌词", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(LyricsDesignTokens.accent)

                    if state.canCreateManualLyrics {
                        ManualLyricsActionsView(state: state, compact: true, compactLabel: "导入")
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Spacer()
            Text(emptyTitle)
                .font(.system(size: compact ? 24 : 30, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.88))
            Text(emptyDetail)
                .font(.system(size: compact ? 13 : 15, design: .rounded))
                .foregroundStyle(.white.opacity(0.58))
            if state.canCreateManualLyrics {
                ManualLyricsActionsView(state: state)
                    .padding(.top, 8)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var emptyTitle: String {
        switch state.liveLyricsState {
        case .loading: return "正在获取歌词…"
        case .failed: return "歌词暂不可用"
        case .noLyrics, .noSelection, .noMatch: return "暂无歌词"
        case .candidates: return "请选择歌词候选"
        case .idle: return "等待正在播放的歌曲"
        default: return "歌词"
        }
    }

    private var emptyDetail: String {
        switch state.liveLyricsState {
        case .failed(_, let failure): return failure.userFacingMessage
        case .noLyrics, .noMatch: return "可从右上角工具菜单重试自动补全"
        case .noSelection: return "当前会话未选择歌词版本；可从右上角重新搜索"
        default: return ""
        }
    }

    private var lyricsScroll: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                let synchronized = state.liveLyricsAreSynchronized
                let verticalPadding = synchronized
                    ? max(120, geometry.size.height * 0.47)
                    : 28.0
                let scroll = ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: rowSpacing) {
                        ForEach(Array(state.liveLyrics.enumerated()), id: \.element.id) { index, line in
                            row(for: line, index: index)
                                .id(line.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, verticalPadding)
                    .padding(.bottom, verticalPadding)
                    .padding(.trailing, compact ? 10 : 18)
                }
                .scrollIndicators(.hidden)

                Group {
                    if synchronized {
                        scroll.mask(
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0),
                                    .init(color: .black, location: 0.12),
                                    .init(color: .black, location: 0.88),
                                    .init(color: .clear, location: 1)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    } else {
                        // Plain lyrics are a reading surface: no fake current
                        // line, no distance hierarchy, no clipped first/last row.
                        scroll
                    }
                }
                .onAppear {
                    scrollToCurrentLine(using: proxy, animated: false)
                }
                .onChange(of: state.liveCurrentLineIndex) { _, _ in
                    scrollToCurrentLine(using: proxy, animated: true)
                }
                .onChange(of: state.liveLyricsSessionRevision) { _, _ in
                    scrollToCurrentLine(using: proxy, animated: false)
                }
            }
        }
    }

    private var rowSpacing: CGFloat {
        let layerCount = (state.preferences.showRomaji ? 1 : 0)
            + (state.preferences.showTranslation ? 1 : 0)
        if !state.liveLyricsAreSynchronized {
            return max(18, (compact ? 21 : 24) - CGFloat(max(0, layerCount - 1)))
        }
        return max(20, (compact ? 24 : 28) - CGFloat(max(0, layerCount - 1)) * 2)
    }

    @ViewBuilder
    private func row(for line: LyricLine, index: Int) -> some View {
        let currentIndex = state.liveCurrentLineIndex
        let synchronized = state.liveLyricsAreSynchronized
        let isActive = synchronized && currentIndex == index
        let distance = synchronized && currentIndex != nil
            ? abs(index - (currentIndex ?? index))
            : 0
        let content = AppleMusicImmersiveV3LyricRow(
            line: line,
            isActive: isActive,
            distance: distance,
            isSynchronized: synchronized,
            availableWidth: availableWidth,
            compact: compact,
            preferences: state.preferences,
            language: state.liveLyricsLanguage
        )
        if let timestamp = LyricsTimeline.validSeekTimestamp(
            for: line,
            isSynchronized: synchronized,
            duration: state.currentTrack.duration
        ) {
            Button {
                state.seek(to: timestamp, source: "v3-lyric-line")
            } label: {
                content
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(line.originalText)
            .accessibilityHint("跳转到歌词时间")
        } else {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func scrollToCurrentLine(using proxy: ScrollViewProxy, animated: Bool) {
        guard state.liveLyricsAreSynchronized,
              let currentIndex = state.liveCurrentLineIndex,
              state.liveLyrics.indices.contains(currentIndex) else {
            return
        }
        let id = state.liveLyrics[currentIndex].id
        let action = { proxy.scrollTo(id, anchor: UnitPoint(x: 0.5, y: 0.47)) }
        if animated {
            withAnimation(LyricsDesignTokens.Motion.lyricAnimation(reduceMotion: reduceMotion), action)
        } else {
            action()
        }
    }
}

private struct AppleMusicImmersiveV3LyricRow: View {
    let line: LyricLine
    let isActive: Bool
    let distance: Int
    let isSynchronized: Bool
    let availableWidth: CGFloat
    let compact: Bool
    let preferences: DisplayPreferences
    let language: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var layerCount: Int {
        1 + (preferences.showRomaji ? 1 : 0) + (preferences.showTranslation && line.translationText != nil ? 1 : 0)
    }

    private var activeBaseSize: CGFloat {
        let sizeScale = max(0.7, preferences.fontSize / 18)
        let upperBound = (compact ? 34 : 42) * sizeScale
        let lowerBound: CGFloat = compact ? 22 : 28
        let characterCount = max(1, line.originalText.count)
        let fitWidth = max(220, availableWidth - 24)
        let estimatedWidth = CGFloat(characterCount) * CGFloat(upperBound) * 0.82
        // Prefer a large display face and allow a long lyric to wrap rather
        // than collapsing every active line into a small subtitle size.
        let fitScale = min(1, max(0.72, fitWidth / max(1, estimatedWidth)))
        let layerPenalty = CGFloat(max(0, layerCount - 2)) * 1.7
        return max(lowerBound, min(CGFloat(upperBound), CGFloat(upperBound) * fitScale - layerPenalty))
    }

    private var baseSize: CGFloat {
        guard isSynchronized else {
            return min(compact ? 30 : 36, activeBaseSize)
        }
        return isActive ? activeBaseSize : max(compact ? 20 : 24, activeBaseSize * (distance == 1 ? 0.93 : 0.88))
    }

    private var rubySize: CGFloat {
        max(compact ? 10 : 12, min(18, baseSize * 0.34 * preferences.rubyFontSize / 10))
    }
    private var auxiliarySize: CGFloat {
        min(compact ? 16 : 18, max(12, baseSize * 0.44 * preferences.assistantFontSize / 14))
    }

    private var shouldShowRuby: Bool {
        guard preferences.kanaDisplayMode == .inlineRuby else { return false }
        guard isSynchronized else { return true }
        return !preferences.hideDistantAuxiliary || distance <= 1
    }

    private var shouldShowKana: Bool {
        guard preferences.kanaDisplayMode != .hidden,
              line.kanaText?.isEmpty == false else { return false }
        guard isSynchronized else { return true }
        return distance <= 1
    }

    private var displayKanaText: String? {
        guard LyricsLanguageGate.allowsJapaneseReadings(language: language, text: line.originalText) else {
            return nil
        }
        return line.kanaText.map(JapaneseRomanizer.displayKana)
    }

    /// Keep a confirmed token mapping when one exists. For older lyric data
    /// without token-level readings, `RubyLineView` receives nil and safely
    /// falls back to a word-level annotation instead of dropping kana.
    private var inlineRubyTokens: [LyricRubyToken]? {
        guard let tokens = line.rubyTokens,
              tokens.contains(where: { $0.hasDisplayRuby }) else {
            return nil
        }
        return tokens
    }

    private var shouldRenderInlineRuby: Bool {
        guard preferences.showOriginal,
              shouldShowRuby,
              let kana = displayKanaText,
              !kana.isEmpty else {
            return false
        }

        // Do not create a redundant ruby block for an already-hiragana line.
        // Kanji and katakana surfaces both benefit from a confirmed reading.
        return line.originalText.unicodeScalars.contains { scalar in
            (0x3400...0x4DBF).contains(scalar.value)
                || (0x4E00...0x9FFF).contains(scalar.value)
                || (0xF900...0xFAFF).contains(scalar.value)
                || (0x30A1...0x30FA).contains(scalar.value)
        }
    }

    private var distinctRomaji: String? {
        guard preferences.showRomaji,
              LyricsLanguageGate.allowsJapaneseReadings(language: language, text: line.originalText),
              let romaji = line.romajiText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !romaji.isEmpty else { return nil }
        // A malformed provider payload sometimes repeats the kana layer in
        // `romajiText`. Do not show the same reading twice in independent-line
        // mode; legitimate Latin Hepburn remains unchanged.
        if let kana = displayKanaText,
           normalizedDisplayText(romaji) == normalizedDisplayText(kana) {
            return nil
        }
        return romaji
    }

    private func normalizedDisplayText(_ text: String) -> String {
        JapaneseRomanizer.displayKana(text)
            .split(whereSeparator: { $0.isWhitespace })
            .joined()
    }

    private var shouldShowRomaji: Bool {
        guard preferences.showRomaji else { return false }
        guard isSynchronized else { return true }
        return !preferences.hideDistantAuxiliary || distance <= 1
    }

    private var rubyOpacity: Double {
        let factor = max(0.15, min(1, preferences.opacity / 0.85))
        guard isSynchronized, distance == 1 else { return 0.62 * factor }
        return 0.46 * factor
    }

    private var romajiOpacity: Double {
        let factor = max(0.15, min(1, preferences.opacity / 0.85))
        guard isSynchronized, distance == 1 else { return 0.65 * factor }
        return 0.48 * factor
    }

    private var rowOpacity: Double {
        guard isSynchronized else { return 1 }
        let factor = max(0.15, min(1, preferences.opacity / 0.85))
        if isActive { return 1 }
        if distance <= 0 { return 0.58 }
        switch distance {
        case 1: return 0.44 * factor
        case 2: return 0.24 * factor
        default: return max(0.14, (0.22 - Double(distance - 3) * 0.025) * factor)
        }
    }

    private var rowBlur: CGFloat {
        guard isSynchronized, distance > 1 else { return 0 }
        switch distance {
        case 2: return 1.1
        default: return min(2.0, 1.1 + CGFloat(distance - 2) * 0.25)
        }
    }

    private var rowWeight: Font.Weight {
        guard isSynchronized else { return .regular }
        if isActive { return .heavy }
        if distance == 1 { return .semibold }
        return .regular
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if shouldRenderInlineRuby,
               let kana = displayKanaText {
                RubyLineView(
                    originalText: line.originalText,
                    kanaText: kana,
                    tokens: inlineRubyTokens,
                    baseFont: .system(size: baseSize, weight: rowWeight, design: .rounded),
                    rubyFont: .system(size: rubySize, weight: .regular, design: .rounded),
                    baseColor: .white,
                    rubyColor: .white.opacity(rubyOpacity),
                    rubySpacing: 1,
                    tokenVerticalSpacing: 3
                )
            } else if preferences.showOriginal, preferences.kanaDisplayMode == .kanaReplacement, shouldShowKana,
                      let kana = displayKanaText {
                KanaReplacementLineView(
                    originalText: line.originalText,
                    kanaText: kana,
                    tokens: line.rubyTokens,
                    showsOriginalAnnotation: true,
                    baseFont: .system(size: baseSize, weight: rowWeight, design: .rounded),
                    annotationFont: .system(size: rubySize, weight: .regular, design: .rounded),
                    baseColor: .white,
                    annotationColor: .white.opacity(rubyOpacity)
                )
            } else if preferences.showOriginal {
                Text(line.originalText)
                    .font(.system(size: baseSize, weight: rowWeight, design: .rounded))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                if preferences.kanaDisplayMode == .independentLine, shouldShowKana,
                   let kana = displayKanaText {
                    Text(kana)
                        .font(.system(size: auxiliarySize, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(rubyOpacity))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if shouldShowKana, let kana = displayKanaText {
                Text(kana)
                    .font(.system(size: baseSize, weight: rowWeight, design: .rounded))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if shouldShowRomaji, let romaji = distinctRomaji {
                Text(romaji)
                    .font(.system(size: auxiliarySize, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(romajiOpacity))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if preferences.showTranslation, let translation = line.translationText, !translation.isEmpty {
                Text(translation)
                    .font(.system(size: max(12, auxiliarySize * 0.82), weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .opacity(rowOpacity)
        .blur(radius: rowBlur)
        .animation(
            LyricsDesignTokens.Motion.lyricAnimation(reduceMotion: reduceMotion),
            value: isActive
        )
        .animation(
            LyricsDesignTokens.Motion.lyricAnimation(reduceMotion: reduceMotion),
            value: isSynchronized
        )
    }
}

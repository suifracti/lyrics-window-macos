import SwiftUI

/// Compact, hover and expanded presentations for the top capsule.  The view
/// observes the same PlaybackState as every other window and never owns a
/// timer, provider, lyric session or translation session.
struct CapsuleLyricsView: View {
    @ObservedObject var state: PlaybackState
    @ObservedObject var windowController: CapsuleLyricsWindowController
    @Environment(\.openWindow) private var openWindow
    @State private var draftPosition: Double?

    private var selection: CapsuleLyricsSelection {
        CapsuleLyricsPresentation.selection(
            lines: state.liveLyrics,
            currentIndex: state.liveCurrentLineIndex,
            isSynchronized: state.liveLyricsAreSynchronized,
            state: state.liveLyricsState
        )
    }

    private var visibleLayerCount: Int {
        let preferences = state.preferences
        return [
            preferences.showOriginal,
            preferences.showTranslation,
            preferences.showRomaji,
            preferences.showKana
        ].filter { $0 }.count
    }

    private var duration: Double {
        max(1, state.currentTrack.duration.isFinite ? state.currentTrack.duration : 1)
    }

    private var activePresentation: CapsuleLyricsPresentationVersion {
        CapsuleLyricsPresentationVersion.current
    }

    private var progressBinding: Binding<Double> {
        Binding(
            get: { draftPosition ?? min(max(0, state.currentTime), duration) },
            set: { draftPosition = min(max(0, $0), duration) }
        )
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                }

            content
                .padding(.horizontal, 14)
                .padding(.vertical, windowController.presentationState == .expanded ? 14 : 8)
        }
        .contentShape(Rectangle())
        .onHover { inside in
            inside ? windowController.pointerEntered() : windowController.pointerExited()
        }
        .onTapGesture {
            if windowController.presentationState == .hover {
                windowController.expand()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: windowController.presentationState)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("顶部胶囊")
    }

    @ViewBuilder
    private var content: some View {
        switch activePresentation {
        case .legacyV1:
            legacyContent
        case .controlFocusedV2:
            controlFocusedContent
        case .dynamicIslandDarkV4:
            // The v4 ID is registered in phase 1 only. Until its renderer is
            // implemented, keep the existing control-focused renderer as a
            // compatibility fallback; v4 is not selected as current.
            controlFocusedContent
        }
    }

    @ViewBuilder
    private var controlFocusedContent: some View {
        switch windowController.presentationState {
        case .collapsed:
            collapsedContent
        case .hover:
            hoverContent
        case .expanded:
            expandedContent
        }
    }

    @ViewBuilder
    private var legacyContent: some View {
        switch windowController.presentationState {
        case .collapsed:
            collapsedContent
        case .hover:
            hoverContent
        case .expanded:
            legacyExpandedContent
        }
    }

    private var collapsedContent: some View {
        HStack(spacing: 10) {
            ArtworkView(track: state.currentTrack, size: 28, showsAlbumLabel: false, cornerRadiusRatio: 0.12)

            VStack(alignment: .leading, spacing: 1) {
                Text(state.currentTrack.title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Text(state.currentTrack.artist)
                    .font(.system(size: 10, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            if let current = selection.current {
                Text(current.originalText)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else if let status = selection.status {
                CapsuleLyricsStatusView(status: status, compact: true)
            }

            Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var hoverContent: some View {
        HStack(spacing: 10) {
            transportButton("backward.end.fill", help: "上一首") { state.previousTrack() }
            transportButton(state.isPlaying ? "pause.fill" : "play.fill", help: "播放/暂停") {
                state.togglePlayPause()
            }
            transportButton("forward.end.fill", help: "下一首") { state.nextTrack() }

            Divider().frame(height: 32)

            ArtworkView(track: state.currentTrack, size: 38, showsAlbumLabel: false, cornerRadiusRatio: 0.12)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(state.currentTrack.title)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Text(state.currentTrack.artist)
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let current = selection.current {
                    Text(current.originalText)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .lineLimit(1)
                } else if let status = selection.status {
                    CapsuleLyricsStatusView(status: status, compact: true)
                }
                if let following = selection.following {
                    Text(following.originalText)
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ArtworkView(track: state.currentTrack, size: 46, showsAlbumLabel: false, cornerRadiusRatio: 0.1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.currentTrack.title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Text(state.currentTrack.artist)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(state.currentTrack.album)
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer()
                transportButton("backward.end.fill", help: "上一首") { state.previousTrack() }
                transportButton(state.isPlaying ? "pause.fill" : "play.fill", help: "播放/暂停") {
                    state.togglePlayPause()
                }
                transportButton("forward.end.fill", help: "下一首") { state.nextTrack() }
            }

            if let current = selection.current {
                CapsuleLyricsRowView(
                    line: current,
                    preferences: state.preferences,
                    availableWidth: 580,
                    visibleLayerCount: visibleLayerCount,
                    language: state.liveLyricsLanguage
                )
            } else if let status = selection.status {
                CapsuleLyricsStatusView(status: status, compact: false)
            }

            HStack(spacing: 8) {
                Slider(value: progressBinding, in: 0...duration, onEditingChanged: { editing in
                    if !editing, let draftPosition {
                        state.seek(to: draftPosition, source: "capsule-slider")
                        self.draftPosition = nil
                    }
                })
                .controlSize(.small)

                Text("\(formatTime(draftPosition ?? state.currentTime)) / \(formatTime(duration))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            HStack(spacing: 8) {
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Label("主窗口", systemImage: "macwindow")
                }
                Button {
                    WindowManager.shared.toggleFloatingLyrics(state: state)
                } label: {
                    Label("悬浮歌词", systemImage: "text.bubble")
                }
                if state.canOpenLyricsEditor {
                    Button {
                        state.prepareLyricsEditor()
                        openWindow(id: "lyrics-editor")
                    } label: {
                        Label("编辑歌词", systemImage: "square.and.pencil")
                    }
                }
                Spacer()
                Button {
                    windowController.collapse()
                } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.plain)
                .help("收起顶部胶囊")
            }
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .buttonStyle(.borderless)
        }
    }

    private func transportButton(
        _ systemName: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .disabled(!state.canInteractWithPlayback)
        .help(help)
    }

    /// Archived V1 renderer kept intact for an internal presentation
    /// rollback. It is not selected by `CapsuleLyricsPresentationVersion.current`.
    private var legacyExpandedContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ArtworkView(track: state.currentTrack, size: 46, showsAlbumLabel: false, cornerRadiusRatio: 0.1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.currentTrack.title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Text(state.currentTrack.artist)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(state.currentTrack.album)
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer()
                transportButton("backward.end.fill", help: "上一首") { state.previousTrack() }
                transportButton(state.isPlaying ? "pause.fill" : "play.fill", help: "播放/暂停") {
                    state.togglePlayPause()
                }
                transportButton("forward.end.fill", help: "下一首") { state.nextTrack() }
            }

            if let current = selection.current {
                LyricLineView(
                    line: current,
                    isActive: true,
                    distance: 0,
                    isSynchronized: true,
                    preferences: state.preferences,
                    availableWidth: 580,
                    visibleLayerCount: visibleLayerCount,
                    language: state.liveLyricsLanguage
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                if let following = selection.following {
                    LyricLineView(
                        line: following,
                        isActive: false,
                        distance: 1,
                        isSynchronized: true,
                        preferences: state.preferences,
                        availableWidth: 580,
                        visibleLayerCount: visibleLayerCount,
                        language: state.liveLyricsLanguage
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if let status = selection.status {
                CapsuleLyricsStatusView(status: status, compact: false)
            }

            HStack(spacing: 8) {
                Slider(value: progressBinding, in: 0...duration, onEditingChanged: { editing in
                    if !editing, let draftPosition {
                        state.seek(to: draftPosition, source: "capsule-slider")
                        self.draftPosition = nil
                    }
                })
                .controlSize(.small)

                Text("\(formatTime(draftPosition ?? state.currentTime)) / \(formatTime(duration))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            HStack(spacing: 8) {
                Button("主窗口") { NSApp.activate(ignoringOtherApps: true) }
                Button("悬浮歌词") { WindowManager.shared.toggleFloatingLyrics(state: state) }
                if state.canOpenLyricsEditor {
                    Button("编辑歌词") {
                        state.prepareLyricsEditor()
                        openWindow(id: "lyrics-editor")
                    }
                }
                Spacer()
                Button {
                    windowController.collapse()
                } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.plain)
                .help("收起顶部胶囊")
            }
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .buttonStyle(.borderless)
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let value = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}

/// Capsule-only adapter for a single live lyric row. `LyricLineView` keeps
/// its global multi-layer semantics; this wrapper gives the expanded capsule
/// a hard vertical budget so ruby flow and auxiliary layers cannot resize the
/// panel. Text still receives the normal single-line truncation request, and
/// overflow is clipped inside this one-row viewport without changing the
/// stored lyric or the shared display/language gates.
private struct CapsuleLyricsRowView: View {
    static let rowHeight: CGFloat = 52

    let line: LyricLine
    let preferences: DisplayPreferences
    let availableWidth: CGFloat
    let visibleLayerCount: Int
    let language: String?

    var body: some View {
        LyricLineView(
            line: line,
            isActive: true,
            distance: 0,
            isSynchronized: true,
            preferences: preferences,
            availableWidth: availableWidth,
            visibleLayerCount: visibleLayerCount,
            language: language
        )
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .lineLimit(1)
        .truncationMode(.tail)
        // RubyTokenFlowLayout and LyricLineView's vertical fixed sizing can
        // exceed the parent proposal. The fixed frame is the capsule-local
        // single-row boundary; clipping prevents the panel from growing.
        .frame(height: Self.rowHeight, alignment: .topLeading)
        .clipped()
    }
}

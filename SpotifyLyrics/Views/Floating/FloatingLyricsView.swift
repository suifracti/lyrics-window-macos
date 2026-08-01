import SwiftUI

/// The production floating renderer. It observes the existing PlaybackState
/// and WindowController only; it owns no provider, session, translation state
/// or playback timer. All lyric rows come from the shared live session.
struct FloatingLyricsView: View {
    @ObservedObject var state: PlaybackState
    @ObservedObject var windowController: FloatingLyricsWindowController

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.14), lineWidth: 1)
                    }

                content(in: geometry)

                if windowController.interactionMode == .interactive {
                    HStack(spacing: 5) {
                        Text("悬浮歌词")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                        Button {
                            windowController.close()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .frame(width: 22, height: 22)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("隐藏悬浮歌词")
                    }
                    .padding(.top, 9)
                    .padding(.trailing, 10)
                    .transition(.opacity)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("悬浮歌词")
    }

    @ViewBuilder
    private func content(in geometry: GeometryProxy) -> some View {
        let documentState = state.liveLyricsState
        let rows = state.liveLyrics
        let width = max(160, geometry.size.width - 32)

        switch documentState {
        case .loaded, .alignmentPreview:
            if state.liveLyricsAreSynchronized, !rows.isEmpty {
                synchronizedRows(rows, width: width)
            } else if !rows.isEmpty {
                plainRows(rows, width: width, status: "纯文本 / 未排轴")
            } else {
                statusView(documentState)
            }
        case .alignmentQueued, .alignmentRunning:
            if !rows.isEmpty {
                plainRows(rows, width: width, status: "纯文本 / 未排轴")
            } else {
                statusView(documentState)
            }
        case .mockPreview, .loading, .idle, .noLyrics, .noMatch, .candidates, .failed:
            if !rows.isEmpty, documentState.isShowingRows {
                plainRows(rows, width: width, status: "纯文本")
            } else {
                statusView(documentState)
            }
        }
    }

    @ViewBuilder
    private func synchronizedRows(_ rows: [LyricLine], width: CGFloat) -> some View {
        let selection = FloatingLyricsPresentationHelper.selection(
            lines: rows,
            currentIndex: state.liveCurrentLineIndex,
            isSynchronized: state.liveLyricsAreSynchronized,
            isPlaying: state.isPlaying
        )
        let visibleLayerCount = visibleLayerCount

        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(selection.visibleIndices, id: \.self) { index in
                        let distance = selection.currentIndex.map { abs(index - $0) } ?? 0
                        LyricLineView(
                            line: rows[index],
                            isActive: index == selection.currentIndex,
                            distance: distance,
                            isSynchronized: true,
                            preferences: state.preferences,
                            availableWidth: width,
                            visibleLayerCount: visibleLayerCount
                        )
                        .id(rows[index].id)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 24)
            }
            .scrollIndicators(.hidden)
            .onChange(of: selection.currentIndex) { _, index in
                guard let index, selection.autoScroll else { return }
                withAnimation(.easeInOut(duration: 0.22)) {
                    proxy.scrollTo(rows[index].id, anchor: .center)
                }
            }
            .task {
                guard let index = selection.currentIndex else { return }
                proxy.scrollTo(rows[index].id, anchor: .center)
            }
        }
    }

    @ViewBuilder
    private func plainRows(_ rows: [LyricLine], width: CGFloat, status: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(status)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 10)

            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 7) {
                    ForEach(rows) { line in
                        LyricLineView(
                            line: line,
                            isActive: false,
                            distance: 0,
                            isSynchronized: false,
                            preferences: state.preferences,
                            availableWidth: width,
                            visibleLayerCount: visibleLayerCount
                        )
                        .id(line.id)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder
    private func statusView(_ state: LyricsLoadState) -> some View {
        FloatingLyricsStatusView(
            state: state,
            message: self.state.liveLyricsStatusMessage,
            title: self.state.currentTrack.title
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var visibleLayerCount: Int {
        let prefs = state.preferences
        var count = prefs.showOriginal ? 1 : 0
        count += prefs.showTranslation ? 1 : 0
        count += prefs.showRomaji ? 1 : 0
        count += prefs.showKana ? 1 : 0
        return max(1, count)
    }
}

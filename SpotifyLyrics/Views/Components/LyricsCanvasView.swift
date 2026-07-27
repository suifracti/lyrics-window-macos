import SwiftUI

struct LyricsCanvasView: View {
    @ObservedObject var state: PlaybackState

    var body: some View {
        Group {
            switch state.lyricsState {
            case .loaded(_), .mockPreview:
                lyricsScroll
            case .loading:
                statusView(icon: "magnifyingglass", message: "正在搜索歌词…", detail: "已清空上一首歌曲的歌词")
            case .noLyrics:
                statusView(icon: "text.magnifyingglass", message: "暂未找到歌词", detail: "当前歌曲没有可用的同步歌词")
            case .noMatch:
                statusView(icon: "magnifyingglass", message: "未找到匹配歌词", detail: "可以重新搜索当前歌曲") {
                    retryButton
                }
            case .failed(_, let failure):
                statusView(icon: "exclamationmark.triangle", message: "歌词搜索失败", detail: failure.userFacingMessage) {
                    retryButton
                }
            case .candidates(_, let candidates):
                candidateList(candidates)
            case .idle:
                statusView(icon: "music.note", message: "等待 Spotify 歌曲", detail: "连接 Spotify 后将搜索当前歌曲歌词")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .id(state.lyricsSessionRevision)
    }

    private var retryButton: some View {
        Button("重新搜索") {
            state.retryLyrics()
        }
        .buttonStyle(.bordered)
        .tint(LyricsDesignTokens.accent)
    }

    private var lyricsScroll: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)

                        LazyVStack(alignment: .leading, spacing: LyricsDesignTokens.lyricRowSpacing) {
                            ForEach(Array(state.lyrics.enumerated()), id: \.element.id) { index, line in
                                LyricLineView(
                                    line: line,
                                    isActive: state.currentLineIndex == index,
                                    distance: distance(from: index),
                                    isSynchronized: state.lyricsAreSynchronized,
                                    preferences: state.preferences
                                )
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .id(line.id)
                                .onTapGesture {
                                    state.seek(to: line.timestamp)
                                }
                            }
                        }
                        .frame(
                            width: min(
                                720,
                                max(520, geometry.size.width - (LyricsDesignTokens.canvasHorizontalPadding * 2 + 16))
                            ),
                            alignment: .leading
                        )

                        Spacer(minLength: 0)
                    }
                    .frame(
                        minWidth: max(0, geometry.size.width - LyricsDesignTokens.canvasHorizontalPadding * 2),
                        minHeight: 320,
                        alignment: .center
                    )
                    .padding(.horizontal, LyricsDesignTokens.canvasHorizontalPadding)
                    .padding(.vertical, LyricsDesignTokens.canvasVerticalPadding)
                }
                .scrollIndicators(.hidden)
                .onAppear {
                    scrollToCurrentLine(using: proxy, animated: false)
                }
                .onChange(of: state.currentLineIndex) { _, _ in
                    scrollToCurrentLine(using: proxy, animated: true)
                }
            }
        }
    }

    private func statusView<Accessory: View>(
        icon: String,
        message: String,
        detail: String,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }
    ) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(LyricsDesignTokens.mutedText)

            Text(message)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(LyricsDesignTokens.primaryText)

            Text(detail)
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(LyricsDesignTokens.mutedText)
                .multilineTextAlignment(.center)

            accessory()
        }
        .padding(30)
        .frame(maxWidth: 440)
        .accessibilityElement(children: .combine)
    }

    private func candidateList(_ candidates: [LyricsCandidate]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("歌词候选")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(LyricsDesignTokens.primaryText)

                Text("匹配置信度不足，选择正确版本后才会显示")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(LyricsDesignTokens.mutedText)

                ForEach(candidates) { candidate in
                    Button {
                        state.adoptLyricsCandidate(candidate)
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(candidate.title)
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                Text("\(candidate.artist) · \(candidate.album)")
                                    .font(.system(size: 12, design: .rounded))
                                    .foregroundStyle(LyricsDesignTokens.mutedText)
                            }
                            Spacer()
                            Text("\(Int(candidate.confidence * 100))%")
                                .font(.system(size: 12, design: .rounded).monospacedDigit())
                                .foregroundStyle(LyricsDesignTokens.accent)
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(LyricsDesignTokens.controlBackground)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, LyricsDesignTokens.canvasHorizontalPadding)
            .padding(.vertical, LyricsDesignTokens.canvasVerticalPadding)
        }
        .scrollIndicators(.hidden)
    }

    private func distance(from index: Int) -> Int {
        LyricsTimeline.presentationDistance(
            index: index,
            currentIndex: state.currentLineIndex,
            isSynchronized: state.lyricsAreSynchronized
        )
    }

    private func scrollToCurrentLine(using proxy: ScrollViewProxy, animated: Bool) {
        guard let currentIndex = state.currentLineIndex,
              state.lyrics.indices.contains(currentIndex) else { return }

        let action = {
            proxy.scrollTo(state.lyrics[currentIndex].id, anchor: .center)
        }

        if animated {
            withAnimation(.easeInOut(duration: 0.28), action)
        } else {
            action()
        }
    }
}

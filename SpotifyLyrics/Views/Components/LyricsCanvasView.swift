import SwiftUI

struct LyricsCanvasView: View {
    @ObservedObject var state: PlaybackState

    var body: some View {
        Group {
            switch state.lyricsState {
            case .loaded(_), .mockPreview:
                lyricsScroll
            case .alignmentQueued:
                VStack(spacing: 10) {
                    lyricsScroll
                    statusView(
                        icon: "timeline.selection",
                        message: "待对齐时间轴",
                        detail: state.songSearchSelectionMessage.isEmpty
                            ? "已获取歌词正文；原文/假名/罗马音独立保存。当前无可靠时间轴，不会伪造同步高亮。"
                            : state.songSearchSelectionMessage
                    ) {
                        VStack(spacing: 8) {
                            Button("自动排轴") {
                                state.alignCurrentLyricsWithLocalAudio()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(LyricsDesignTokens.accent)
                            retryButton
                        }
                    }
                    .frame(maxHeight: 160)
                }
            case .alignmentRunning(_, _, let progress):
                VStack(spacing: 10) {
                    lyricsScroll
                    statusView(
                        icon: "waveform",
                        message: "正在自动排轴… \(Int(progress * 100))%",
                        detail: state.songSearchSelectionMessage.isEmpty ? "识别音频并与已知歌词逐行对齐" : state.songSearchSelectionMessage
                    ) {
                        Button("取消") { state.cancelAlignmentPreview() }
                            .buttonStyle(.bordered)
                    }
                    .frame(maxHeight: 140)
                }
            case .alignmentPreview(_, _, _, let report):
                VStack(spacing: 10) {
                    lyricsScroll
                    statusView(
                        icon: "checkmark.circle",
                        message: String(format: "排轴预览 · 置信度 %.0f%%", report.overallConfidence * 100),
                        detail: "低置信/未匹配 \(report.lowConfidenceCount) 行已标出。确认前不会覆盖保存；可试听 seek。"
                    ) {
                        HStack(spacing: 8) {
                            Button("确认并保存") { state.confirmAlignmentPreview(saveLocal: true) }
                                .buttonStyle(.borderedProminent)
                                .tint(LyricsDesignTokens.accent)
                            Button("放弃") { state.cancelAlignmentPreview() }
                                .buttonStyle(.bordered)
                        }
                    }
                    .frame(maxHeight: 160)
                }
            case .loading:
                statusView(icon: "magnifyingglass", message: "正在自动补全歌词…", detail: "Local → LRCLIB → 网易云/QQ（实验）多别名查询中")
            case .noLyrics:
                statusView(icon: "text.magnifyingglass", message: "暂未找到歌词", detail: "来源返回无词（例如纯音乐）。可导入本地音频做 ASR 草稿。") {
                    VStack(spacing: 8) {
                        retryButton
                        Button("导入本地音频 · ASR 草稿") {
                            state.importLocalAudioForASR()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            case .noMatch:
                statusView(
                    icon: "magnifyingglass",
                    message: "自动补全未找到歌词",
                    detail: "多别名与在线源均无正文（noTextSource）。可选：重试自动补全，或导入本地音频生成 ASR 草稿。"
                ) {
                    VStack(spacing: 8) {
                        retryButton
                        Button("导入本地音频 · ASR 草稿") {
                            state.importLocalAudioForASR()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            case .failed(_, let failure):
                statusView(icon: "exclamationmark.triangle", message: "自动补全失败", detail: failure.userFacingMessage) {
                    retryButton
                }
            case .candidates(_, let candidates):
                candidateList(candidates)
            case .idle:
                statusView(icon: "music.note", message: "等待 Spotify 歌曲", detail: "连接后将自动补全当前歌曲歌词")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .id(state.lyricsSessionRevision)
    }

    private var retryButton: some View {
        Button("自动补全歌词") {
            state.autoCompleteLyrics()
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

                        LazyVStack(
                            alignment: .leading,
                            spacing: LyricsDesignTokens.lyricRowSpacing(
                                for: geometry.size.width,
                                visibleLayerCount: visibleLayerCount
                            )
                        ) {
                            ForEach(Array(state.lyrics.enumerated()), id: \.element.id) { index, line in
                                if let seekTimestamp = LyricsTimeline.validSeekTimestamp(
                                    for: line,
                                    isSynchronized: state.lyricsAreSynchronized,
                                    duration: state.currentTrack.duration
                                ) {
                                    Button {
                                        state.seek(to: seekTimestamp, source: "lyric-line")
                                    } label: {
                                        lyricLineView(
                                            line: line,
                                            index: index,
                                            availableWidth: geometry.size.width
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                    .accessibilityLabel(line.originalText)
                                    .accessibilityHint("跳转到歌词时间")
                                    .accessibilityIdentifier("lyrics-line-\(line.id.uuidString)")
                                } else {
                                    lyricLineView(
                                        line: line,
                                        index: index,
                                        availableWidth: geometry.size.width
                                    )
                                }
                            }
                        }
                        .accessibilityElement(children: .contain)
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
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.13),
                            .init(color: .black, location: 0.87),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .accessibilityElement(children: .contain)
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

    @ViewBuilder
    private func lyricLineView(
        line: LyricLine,
        index: Int,
        availableWidth: CGFloat
    ) -> some View {
        LyricLineView(
            line: line,
            isActive: state.currentLineIndex == index,
            distance: distance(from: index),
            isSynchronized: state.lyricsAreSynchronized,
            preferences: state.preferences,
            availableWidth: availableWidth,
            visibleLayerCount: visibleLayerCount
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .id(line.id)
    }

    private func scrollToCurrentLine(using proxy: ScrollViewProxy, animated: Bool) {
        guard let currentIndex = state.currentLineIndex,
              state.lyrics.indices.contains(currentIndex) else { return }

        let action = {
            proxy.scrollTo(state.lyrics[currentIndex].id, anchor: .center)
        }

        if animated {
            withAnimation(.easeInOut(duration: 0.24), action)
        } else {
            action()
        }
    }

    private var visibleLayerCount: Int {
        [
            state.preferences.showOriginal,
            state.preferences.kanaDisplayMode != .hidden,
            state.preferences.showRomaji,
            state.preferences.showTranslation
        ]
        .filter { $0 }
        .count
    }
}

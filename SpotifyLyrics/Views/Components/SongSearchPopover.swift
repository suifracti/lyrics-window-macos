import SwiftUI

struct SongSearchPopover: View {
    @ObservedObject var manager: SongSearchManager
    @ObservedObject var playbackState: PlaybackState
    @State private var query = ""
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(LyricsDesignTokens.mutedText)

                TextField("搜索歌曲、艺人或专辑", text: $query)
                    .textFieldStyle(.plain)
                    .focused($isSearchFieldFocused)
                    .onSubmit {
                        search()
                    }

                Button("搜索", action: search)
                    .buttonStyle(.borderedProminent)
                    .tint(LyricsDesignTokens.accent)
                    .controlSize(.small)
                    .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LyricsDesignTokens.controlBackground)
            )

            Text("搜索仅通过 Spotify 当前歌曲、本地歌词目录和 LRCLIB 返回统一结果")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(LyricsDesignTokens.mutedText)

            content
        }
        .padding(16)
        .frame(width: 440, height: 470, alignment: .top)
        .preferredColorScheme(.dark)
        .onAppear {
            if let existing = manager.state.query?.text, !existing.isEmpty {
                query = existing
            }
            isSearchFieldFocused = true
        }
    }

    @ViewBuilder
    private var content: some View {
        switch manager.state {
        case .idle:
            emptyState(icon: "music.note", title: "搜索歌曲或歌词", detail: "输入标题、艺人或专辑后开始")
        case .searching:
            emptyState(icon: "hourglass", title: "正在搜索…", detail: "正在调度本地、Spotify 和 LRCLIB Provider")
        case .noResults:
            emptyState(icon: "questionmark.folder", title: "没有匹配结果", detail: "可换一个标题或艺人关键词")
        case .failed(_, let message):
            VStack(alignment: .leading, spacing: 10) {
                emptyState(icon: "exclamationmark.triangle", title: "搜索失败", detail: message)
                Button("重新搜索", action: search)
                    .buttonStyle(.bordered)
                    .tint(LyricsDesignTokens.accent)
            }
        case .results(_, let results):
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(results) { result in
                        resultRow(result)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }

        if !playbackState.songSearchSelectionMessage.isEmpty {
            Text(playbackState.songSearchSelectionMessage)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(LyricsDesignTokens.accent)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func resultRow(_ result: SongSearchResult) -> some View {
        Button {
            playbackState.loadSearchResult(result)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: result.lyrics == nil ? "music.note" : "text.quote")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(LyricsDesignTokens.accent)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(LyricsDesignTokens.controlBackground))

                VStack(alignment: .leading, spacing: 3) {
                    Text(result.track.title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(LyricsDesignTokens.primaryText)
                        .lineLimit(1)
                    Text("\(result.track.artist) · \(result.track.album.isEmpty ? "未知专辑" : result.track.album)")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(LyricsDesignTokens.mutedText)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(result.source.displayName)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(LyricsDesignTokens.mutedText)
                    Text(result.lyrics == nil ? "加载当前歌词" : "加载歌词")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(LyricsDesignTokens.accent)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LyricsDesignTokens.controlBackground.opacity(0.72))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("歌曲结果：\(result.track.title)，\(result.track.artist)")
        .accessibilityHint(result.lyrics == nil ? "重新搜索当前歌曲歌词" : "加载这首歌的歌词")
    }

    private func emptyState(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(LyricsDesignTokens.mutedText)
            Text(title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(LyricsDesignTokens.primaryText)
            Text(detail)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(LyricsDesignTokens.mutedText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 140)
    }

    private func search() {
        manager.search(query: SongSearchQuery(text: query))
    }
}

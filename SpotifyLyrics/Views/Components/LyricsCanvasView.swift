import SwiftUI

struct LyricsCanvasView: View {
    @ObservedObject var state: PlaybackState

    var body: some View {
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

    private func distance(from index: Int) -> Int {
        guard let currentIndex = state.currentLineIndex else { return index }
        return abs(index - currentIndex)
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

import SwiftUI

/// Shared lyric viewport used by both main-window arrangements.
struct LyricsViewport: View {
    @ObservedObject var state: PlaybackState
    var onSearch: (() -> Void)? = nil

    var body: some View {
        LyricsCanvasView(state: state, onSearch: onSearch)
    }
}

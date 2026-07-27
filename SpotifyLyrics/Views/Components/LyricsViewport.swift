import SwiftUI

/// Shared lyric viewport used by both main-window arrangements.
struct LyricsViewport: View {
    @ObservedObject var state: PlaybackState

    var body: some View {
        LyricsCanvasView(state: state)
    }
}

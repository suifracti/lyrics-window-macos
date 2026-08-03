import Foundation

/// Converts the existing live projection into a value snapshot.  The factory
/// does not retain PlaybackState and does not start any observers or timers.
@MainActor
public enum PresentationPreviewContextFactory {
    public static func live(
        from state: PlaybackState,
        surface: PresentationSurface = .preview,
        windowSize: PresentationPreviewSize = PresentationPreviewSize(width: 960, height: 640)
    ) -> PresentationPreviewContext {
        let lines = state.liveLyrics
        let currentIndex = state.liveCurrentLineIndex
        let contextIndices: [Int]
        if let currentIndex, lines.indices.contains(currentIndex) {
            let lower = max(0, currentIndex - 2)
            let upper = min(lines.count, currentIndex + 3)
            contextIndices = Array(lower..<upper)
        } else {
            contextIndices = []
        }

        return PresentationPreviewContext(
            source: .live,
            trackIdentity: state.currentTrackIdentity,
            track: state.currentTrack,
            currentTime: state.currentTime,
            duration: state.currentTrack.duration,
            isPlaying: state.isPlaying,
            lyricsState: PresentationPreviewLyricsState(loadState: state.liveLyricsState),
            lyricsAreSynchronized: state.liveLyricsAreSynchronized,
            lyrics: lines,
            contextLineIndices: contextIndices,
            currentLineIndex: currentIndex,
            showOriginal: state.preferences.showOriginal,
            showTranslation: state.preferences.showTranslation,
            showRomaji: state.preferences.showRomaji,
            kanaDisplayMode: state.preferences.kanaDisplayMode,
            hasTranslationSelection: state.selectedTranslation != nil,
            reduceMotion: false,
            reduceTransparency: false,
            increaseContrast: false,
            windowSize: windowSize,
            surface: surface
        )
    }
}

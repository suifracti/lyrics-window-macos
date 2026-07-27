import SwiftUI

struct LineDisplayView: View {
    let line: LyricLine
    let isActive: Bool
    let prefs: DisplayPreferences

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if prefs.showKana, let kana = line.kanaText, !kana.isEmpty {
                Text(kana)
                    .font(.system(size: prefs.fontSize * 0.65, weight: .light, design: .rounded))
                    .foregroundColor(isActive ? .accentColor.opacity(0.8) : .secondary)
            }
            if prefs.showOriginal {
                Text(line.originalText)
                    .font(.system(size: prefs.fontSize, weight: isActive ? .bold : .medium, design: .rounded))
                    .foregroundColor(isActive ? .primary : .secondary.opacity(0.8))
                    .scaleEffect(isActive ? 1.03 : 1.0, anchor: .leading)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isActive)
            }
            if prefs.showRomaji, let romaji = line.romajiText, !romaji.isEmpty {
                Text(romaji)
                    .font(.system(size: prefs.fontSize * 0.75, weight: .regular, design: .monospaced))
                    .foregroundColor(isActive ? .accentColor : .secondary.opacity(0.7))
            }
            if prefs.showTranslation, let trans = line.translationText, !trans.isEmpty {
                Text(trans)
                    .font(.system(size: prefs.fontSize * 0.85, weight: .medium, design: .rounded))
                    .foregroundColor(isActive ? .primary.opacity(0.9) : .secondary.opacity(0.6))
            }
        }
        .padding(.vertical, 4)
    }
}

// Floating Lyrics View
struct FloatingLyricsView: View {
    @EnvironmentObject var state: PlaybackState

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 6) {
                if let index = state.currentLineIndex, index < state.lyrics.count {
                    let line = state.lyrics[index]
                    LineDisplayView(line: line, isActive: true, prefs: state.preferences)
                } else {
                    Text("Spotify 歌词准备就绪")
                        .foregroundColor(.secondary)
                }
            }
            .padding()
        }
    }
}

// Top Capsule Player View
struct CapsulePlayerView: View {
    @EnvironmentObject var state: PlaybackState

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: state.currentTrack.artworkName)
                .font(.title3)
                .foregroundColor(.accentColor)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.accentColor.opacity(0.2)))

            VStack(alignment: .leading, spacing: 2) {
                Text(state.currentTrack.title)
                    .font(.caption)
                    .bold()
                    .lineLimit(1)
                if let index = state.currentLineIndex, index < state.lyrics.count {
                    Text(state.lyrics[index].originalText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button(action: { state.togglePlayPause() }) {
                Image(systemName: state.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(.thinMaterial)
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        )
    }
}

// Full Screen Lyrics View
struct FullScreenLyricsView: View {
    @EnvironmentObject var state: PlaybackState

    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)

            VStack {
                HStack {
                    Spacer()
                    Button(action: { WindowManager.shared.toggleFullScreen(state: state) }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.largeTitle)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .padding()
                }

                Spacer()

                VStack(spacing: 24) {
                    if let index = state.currentLineIndex, index < state.lyrics.count {
                        let line = state.lyrics[index]
                        LineDisplayView(
                            line: line,
                            isActive: true,
                            prefs: DisplayPreferences(
                                showOriginal: state.preferences.showOriginal,
                                showTranslation: state.preferences.showTranslation,
                                showRomaji: state.preferences.showRomaji,
                                showKana: state.preferences.showKana,
                                fontSize: 32,
                                opacity: 1.0,
                                alwaysOnTop: false
                            )
                        )
                    } else {
                        Text(state.currentTrack.title)
                            .font(.largeTitle)
                            .foregroundColor(.white)
                    }
                }

                Spacer()
            }
        }
    }
}

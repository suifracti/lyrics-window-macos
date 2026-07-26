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

struct MainWindowView: View {
    @EnvironmentObject var state: PlaybackState

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 16) {
                // Track Info Header
                HStack(spacing: 14) {
                    Image(systemName: state.currentTrack.artworkName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 54, height: 54)
                        .background(Color.accentColor.opacity(0.15))
                        .cornerRadius(8)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(state.currentTrack.title)
                            .font(.headline)
                            .bold()
                        Text(state.currentTrack.artist)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text(state.currentTrack.album)
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                }
                .padding(.horizontal)
                .padding(.top)

                Divider()

                // Display Mode Toggles
                VStack(alignment: .leading, spacing: 8) {
                    Text("显示视图")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)

                    Button(action: { WindowManager.shared.toggleFloatingWindow(state: state) }) {
                        Label("悬浮歌词窗口", systemImage: state.showFloatingWindow ? "checkmark.square" : "square")
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)

                    Button(action: { WindowManager.shared.toggleCapsulePlayer(state: state) }) {
                        Label("顶部胶囊播放器", systemImage: state.showCapsulePlayer ? "checkmark.square" : "square")
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)

                    Button(action: { WindowManager.shared.toggleFullScreen(state: state) }) {
                        Label("全屏歌词模式", systemImage: state.showFullScreen ? "checkmark.square" : "square")
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                }

                Divider()

                // Multi-line Toggle Preferences
                VStack(alignment: .leading, spacing: 8) {
                    Text("多行显示开关")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)

                    Toggle("原文", isOn: $state.preferences.showOriginal)
                        .padding(.horizontal)
                    Toggle("翻译", isOn: $state.preferences.showTranslation)
                        .padding(.horizontal)
                    Toggle("罗马音", isOn: $state.preferences.showRomaji)
                        .padding(.horizontal)
                    Toggle("假名", isOn: $state.preferences.showKana)
                        .padding(.horizontal)
                }

                Spacer()

                // Controls
                VStack(spacing: 8) {
                    Slider(value: Binding(
                        get: { state.currentTime },
                        set: { state.seek(to: $0) }
                    ), in: 0...state.currentTrack.duration)
                    .padding(.horizontal)

                    HStack {
                        Button(action: { state.togglePlayPause() }) {
                            Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                                .font(.title2)
                        }
                        .buttonStyle(.borderless)

                        Text("\(formatTime(state.currentTime)) / \(formatTime(state.currentTrack.duration))")
                            .font(.caption)
                            .monospacedDigit()
                    }
                }
                .padding(.bottom)
            }
            .frame(minWidth: 240)
        } detail: {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(Array(state.lyrics.enumerated()), id: \.element.id) { index, line in
                            let isActive = (state.currentLineIndex == index)
                            LineDisplayView(line: line, isActive: isActive, prefs: state.preferences)
                                .id(index)
                                .onTapGesture {
                                    state.seek(to: line.timestamp)
                                }
                        }
                    }
                    .padding(32)
                }
                .onChange(of: state.currentLineIndex) { _, newIndex in
                    if let index = newIndex {
                        withAnimation {
                            proxy.scrollTo(index, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private func formatTime(_ sec: TimeInterval) -> String {
        let m = Int(sec) / 60
        let s = Int(sec) % 60
        return String(format: "%02d:%02d", m, s)
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

import SwiftUI

struct PlaybackControlsView: View {
    @ObservedObject var state: PlaybackState
    var vertical: Bool = false

    var body: some View {
        VStack(spacing: vertical ? 14 : 10) {
            Slider(
                value: Binding(
                    get: { state.currentTime },
                    set: { state.seek(to: $0, source: "progress-slider") }
                ),
                in: 0...max(0.1, state.currentTrack.duration)
            )
            .tint(LyricsDesignTokens.accent)

            if vertical {
                controlRow
            } else {
                HStack(spacing: 14) {
                    controlRow
                    Spacer(minLength: 12)
                    Text(state.isPlaying ? "正在播放" : "已暂停")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(LyricsDesignTokens.mutedText)
                }
            }
        }
        .padding(.horizontal, vertical ? 14 : 16)
        .padding(.vertical, vertical ? 12 : 10)
        .background {
            Capsule(style: .continuous)
                .fill(.regularMaterial)
        }
        .overlay {
            Capsule(style: .continuous)
                .stroke(LyricsDesignTokens.controlBorder.opacity(0.9), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
        .accessibilityElement(children: .contain)
    }

    private var controlRow: some View {
        HStack(spacing: 14) {
            transportButton(
                systemImage: "backward.fill",
                label: "上一首",
                help: state.canControlSpotify ? "上一首" : "Spotify 未连接",
                isEnabled: state.canControlSpotify
            ) {
                state.previousTrack()
            }

            Button {
                state.togglePlayPause()
            } label: {
                Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(LyricsDesignTokens.primaryText)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(LyricsDesignTokens.controlBackground))
            }
            .buttonStyle(.plain)
            .disabled(!state.canInteractWithPlayback)
            .opacity(state.canInteractWithPlayback ? 1 : 0.42)
            .accessibilityLabel(state.isPlaying ? "暂停" : "播放")

            transportButton(
                systemImage: "forward.fill",
                label: "下一首",
                help: state.canControlSpotify ? "下一首" : "Spotify 未连接",
                isEnabled: state.canControlSpotify
            ) {
                state.nextTrack()
            }

            Text("\(formatTime(state.currentTime)) / \(formatTime(state.currentTrack.duration))")
                .font(.system(size: 12, design: .rounded).monospacedDigit())
                .foregroundStyle(LyricsDesignTokens.mutedText)
        }
    }

    private func transportButton(
        systemImage: String,
        label: String,
        help: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(LyricsDesignTokens.primaryText)
                .frame(width: 30, height: 30)
                .background(Circle().fill(LyricsDesignTokens.controlBackground))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.42)
        .accessibilityLabel(label)
        .help(help)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let remainder = Int(seconds) % 60
        return String(format: "%02d:%02d", minutes, remainder)
    }
}

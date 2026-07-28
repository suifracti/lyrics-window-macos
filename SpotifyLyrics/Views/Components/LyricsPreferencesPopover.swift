import SwiftUI

struct LyricsPreferencesPopover: View {
    @Binding var preferences: DisplayPreferences
    @ObservedObject var playbackState: PlaybackState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("歌词显示")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(LyricsDesignTokens.primaryText)
                Text("只显示需要的语言层级")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(LyricsDesignTokens.mutedText)
            }

            VStack(spacing: 10) {
                preferenceToggle("原文", systemImage: "textformat", isOn: $preferences.showOriginal)
                preferenceToggle("翻译", systemImage: "character.bubble", isOn: $preferences.showTranslation)
                preferenceToggle("罗马音", systemImage: "textformat.abc", isOn: $preferences.showRomaji)
                kanaDisplayControls
            }

            Divider().overlay(LyricsDesignTokens.controlBorder)

            VStack(alignment: .leading, spacing: 10) {
                Text("显示窗口")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(LyricsDesignTokens.mutedText)

                modeButton("悬浮歌词", systemImage: "rectangle.on.rectangle", isActive: playbackState.showFloatingWindow) {
                    WindowManager.shared.toggleFloatingWindow(state: playbackState)
                }
                modeButton("顶部胶囊", systemImage: "capsule", isActive: playbackState.showCapsulePlayer) {
                    WindowManager.shared.toggleCapsulePlayer(state: playbackState)
                }
                modeButton("全屏歌词", systemImage: "arrow.up.left.and.arrow.down.right", isActive: playbackState.showFullScreen) {
                    WindowManager.shared.toggleFullScreen(state: playbackState)
                }
            }
        }
        .padding(22)
        .frame(width: 344)
        .background(.ultraThinMaterial)
        .preferredColorScheme(.dark)
    }

    private var kanaDisplayControls: some View {
        VStack(alignment: .leading, spacing: 7) {
            preferenceToggle("假名", systemImage: "character.book.closed", isOn: $preferences.showKana)

            Picker("假名显示方式", selection: kanaDisplayModeBinding) {
                Text("独立行").tag(KanaDisplayMode.independentLine)
                Text("汉字上方").tag(KanaDisplayMode.inlineRuby)
                Text("假名替换").tag(KanaDisplayMode.kanaReplacement)
            }
            .pickerStyle(.radioGroup)
            .font(.system(size: 12, design: .rounded))
            .accessibilityLabel("假名显示方式")

            Text(preferences.kanaDisplayMode.detail)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(LyricsDesignTokens.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var kanaDisplayModeBinding: Binding<KanaDisplayMode> {
        Binding(
            get: {
                preferences.kanaDisplayMode == .hidden
                    ? .independentLine
                    : preferences.kanaDisplayMode
            },
            set: { mode in
                // Choosing any of the three presentations is sufficient to
                // enable that presentation; none is gated by the old Boolean.
                preferences.kanaDisplayMode = mode
            }
        )
    }

    private func preferenceToggle(_ title: String, systemImage: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(LyricsDesignTokens.secondaryText)
        }
        .toggleStyle(.switch)
        .tint(LyricsDesignTokens.accent)
    }

    private func modeButton(_ title: String, systemImage: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .frame(width: 18)
                Text(title)
                Spacer()
                if isActive {
                    Image(systemName: "checkmark")
                        .foregroundStyle(LyricsDesignTokens.accent)
                }
            }
            .font(.system(size: 13, design: .rounded))
            .foregroundStyle(LyricsDesignTokens.secondaryText)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

import SwiftUI

/// Recovery actions deliberately live beside no-lyrics/no-match states rather
/// than in Settings.  They only prepare the shared editor session; SQLite is
/// written after the user confirms the preview and saves.
struct ManualLyricsActionsView: View {
    @ObservedObject var state: PlaybackState
    @Environment(\.openWindow) private var openWindow
    var compact = false

    var body: some View {
        Group {
            if compact {
                Menu {
                    actions
                } label: {
                    Label("创建或导入歌词", systemImage: "square.and.pencil")
                }
            } else {
                VStack(spacing: 8) {
                    Text("没有可信歌词时，可以创建本地人工版本")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        actions
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        Button("粘贴歌词", systemImage: "doc.on.clipboard") {
            if state.prepareManualLyricsFromClipboard() {
                openWindow(id: "lyrics-editor")
            }
        }
        Button("导入 TXT", systemImage: "doc.text") {
            if state.prepareManualLyricsFromTXT() {
                openWindow(id: "lyrics-editor")
            }
        }
        Button("创建空白歌词", systemImage: "plus.square") {
            if state.prepareBlankLyricsEditor() {
                openWindow(id: "lyrics-editor")
            }
        }
        Button("导入 LRC", systemImage: "waveform.badge.plus") {
            if state.prepareManualLyricsFromLRC() {
                openWindow(id: "lyrics-editor")
            }
        }
    }
}

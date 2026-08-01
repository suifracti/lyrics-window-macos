import SwiftUI

struct CapsuleLyricsStatusView: View {
    let status: String
    let compact: Bool

    var body: some View {
        Label {
            Text(status)
                .lineLimit(1)
        } icon: {
            Image(systemName: compact ? "music.note" : "text.quote")
        }
        .font(.system(size: compact ? 11 : 13, weight: .medium, design: .rounded))
        .foregroundStyle(.secondary)
        .help(status)
    }
}

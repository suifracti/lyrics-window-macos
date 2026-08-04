import SwiftUI

struct ReadingVersionEditorView: View {
    @ObservedObject var state: PlaybackState
    let version: StoredReadingVersion
    @Environment(\.dismiss) private var dismiss
    @State private var drafts: [String]

    init(state: PlaybackState, version: StoredReadingVersion) {
        self.state = state
        self.version = version
        _drafts = State(initialValue: version.lines.map { $0.readingText ?? "" })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("编辑读音")
                .font(.title3.weight(.semibold))
            Text("保存会创建新的人工读音版本，不覆盖 \(version.record.engineID)。")
                .font(.caption)
                .foregroundStyle(.secondary)
            List {
                ForEach(Array(version.lines.enumerated()), id: \.element.lineIndex) { index, line in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(line.originalText.isEmpty ? "（空行）" : line.originalText)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                        TextField("读音", text: Binding(
                            get: { drafts.indices.contains(index) ? drafts[index] : "" },
                            set: { if drafts.indices.contains(index) { drafts[index] = $0 } }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }
                    .padding(.vertical, 4)
                }
            }
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("另存为人工版本") {
                    let edited = version.lines.map { line in
                        ReadingLineResult(
                            lineIndex: line.lineIndex,
                            originalText: line.originalText,
                            readingText: line.originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : (drafts.indices.contains(line.lineIndex) ? drafts[line.lineIndex] : line.readingText),
                            language: line.language,
                            tokens: line.tokens,
                            warnings: [],
                            confidence: 1
                        )
                    }
                    state.readingSession.saveManualEdit(version, readingLines: edited)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 460)
        .preferredColorScheme(.dark)
    }
}

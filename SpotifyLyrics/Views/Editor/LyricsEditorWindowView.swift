import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct LyricsEditorWindowView: View {
    @EnvironmentObject private var state: PlaybackState
    @Environment(\.dismiss) private var dismiss
    @State private var focusedLineID: UUID?

    private var editor: LyricsEditorSessionController { state.lyricsEditor }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let preview = editor.pendingImport {
                importPreview(preview)
            } else if let draft = editor.draft {
                editorBody(draft)
            } else {
                ContentUnavailableView("没有可编辑的歌词版本", systemImage: "music.note.list", description: Text("请先在主窗口加载一首歌曲的歌词。"))
            }
            Divider()
            footer
        }
        .frame(minWidth: 980, minHeight: 620)
        .preferredColorScheme(.dark)
        .onAppear {
            if editor.draft == nil { state.prepareLyricsEditor() }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(editor.draft?.title ?? state.currentTrack.title)
                    .font(.title3.weight(.semibold))
                Text(editor.draft?.artist ?? state.currentTrack.artist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            versionPicker
            translationPicker
            Button("导入 LRC", systemImage: "square.and.arrow.down") { importLRC() }
            Button("导出原文", systemImage: "square.and.arrow.up") { exportOriginal() }
            Button("导出翻译", systemImage: "text.badge.plus") { exportTranslation() }
            Button("关闭") { dismiss() }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var versionPicker: some View {
        Menu {
            ForEach(editor.availableVersions, id: \.record.id) { version in
                Button {
                    editor.selectLyricsVersion(versionID: version.record.id)
                } label: {
                    HStack {
                        Text("\(version.record.source) · \(version.record.id.uuidString.prefix(8))")
                        if version.record.isLocked { Image(systemName: "lock.fill") }
                    }
                }
            }
        } label: {
            Label("歌词版本", systemImage: "doc.text")
        }
        .menuStyle(.borderlessButton)
    }

    private var translationPicker: some View {
        Menu {
            if editor.availableTranslations.isEmpty {
                Text("暂无翻译版本")
            }
            ForEach(editor.availableTranslations, id: \.record.id) { version in
                Button {
                    editor.selectTranslation(versionID: version.record.id)
                } label: {
                    HStack {
                        Text("\(version.record.targetLanguage) · \(version.record.sourceKind.rawValue)")
                        if version.record.isLocked { Image(systemName: "lock.fill") }
                    }
                }
            }
        } label: {
            Label("翻译版本", systemImage: "character.bubble")
        }
        .menuStyle(.borderlessButton)
    }

    private func editorBody(_ draft: LyricsEditorDraft) -> some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HStack(spacing: 0) {
                Text("行 / 时间 / 原文")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("翻译 / 读音")
                    .frame(width: 360, alignment: .leading)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.quaternary.opacity(0.35))
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(Array(draft.lines.enumerated()), id: \.element.id) { index, line in
                        lineRow(index: index, line: line, total: draft.lines.count)
                    }
                }
                .padding(12)
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button("撤销", systemImage: "arrow.uturn.backward") { editor.undo() }
            Button("重做", systemImage: "arrow.uturn.forward") { editor.redo() }
            Divider().frame(height: 18)
            Button("插入空行", systemImage: "plus") { editor.insertBlank(after: nil) }
            Button("重新生成整首读音", systemImage: "textformat.abc") { editor.regenerateAllReadings() }
            Divider().frame(height: 18)
            Button("后退 2 秒", systemImage: "gobackward.2") {
                state.seek(to: max(0, state.currentTime - 2), source: "lyrics-editor")
            }
            Button(state.isPlaying ? "暂停" : "播放", systemImage: state.isPlaying ? "pause.fill" : "play.fill") {
                state.togglePlayPause()
            }
            Button("前进 2 秒", systemImage: "goforward.2") {
                state.seek(to: min(state.currentTrack.duration, state.currentTime + 2), source: "lyrics-editor")
            }
            Text(Self.formatTime(state.currentTime) + " / " + Self.formatTime(state.currentTrack.duration))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Button("记当前行", systemImage: "scope") {
                markFocusedLineAtCurrentTime(advance: false)
            }
            Button("记当前并下一行", systemImage: "arrow.down.to.line") {
                markFocusedLineAtCurrentTime(advance: true)
            }
            Spacer()
            Button("保存人工版本") { editor.save() }
            Button("保存并锁定", systemImage: "lock.fill") { editor.save(lockLyrics: true, lockTranslation: true) }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func lineRow(index: Int, line: LyricsEditorLineDraft, total: Int) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(index + 1)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 28, alignment: .trailing)
                HStack(spacing: 4) {
                    timeField(lineID: line.id, placeholder: "开始")
                    Text("→").foregroundStyle(.secondary)
                    timeField(lineID: line.id, placeholder: "结束", isEnd: true)
                }
                .frame(width: 150)
            }
            TextField("原文", text: textBinding(lineID: line.id, key: .original))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 4) {
                TextField("翻译", text: textBinding(lineID: line.id, key: .translation))
                    .textFieldStyle(.roundedBorder)
                HStack(spacing: 8) {
                    Text(line.kanaText ?? "—")
                    Text(line.romajiText ?? "—")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Button("试听") {
                        focusedLineID = line.id
                        if let startTime = line.startTime {
                            state.seek(to: startTime, source: "lyrics-editor-row")
                        }
                    }
                    Button("读音") { editor.regenerateReading(for: line.id) }
                    Button(editor.isReadingLocked(lineID: line.id) ? "已锁" : "锁读音") {
                        editor.toggleReadingLock(lineID: line.id)
                    }
                }
                .font(.caption)
            }
            .frame(width: 360, alignment: .leading)
            VStack(spacing: 3) {
                Button("↑") { editor.move(lineID: line.id, offset: -1) }
                    .disabled(index == 0)
                Button("↓") { editor.move(lineID: line.id, offset: 1) }
                    .disabled(index == total - 1)
                Menu {
                    Button("在中间拆分") {
                        editor.split(lineID: line.id, at: max(1, line.originalText.count / 2))
                    }
                    if index + 1 < total {
                        Button("与下一行合并") {
                            editor.merge(lineID: line.id, with: editor.draft?.lines[index + 1].id ?? line.id)
                        }
                    }
                    Button("删除") { editor.delete(lineID: line.id) }
                } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton)
            }
            .frame(width: 44)
        }
        .padding(8)
        .background(index.isMultiple(of: 2) ? Color.white.opacity(0.035) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture { focusedLineID = line.id }
    }

    private enum TextFieldKey { case original, translation }

    private func textBinding(lineID: UUID, key: TextFieldKey) -> Binding<String> {
        Binding(
            get: {
                guard let line = editor.draft?.lines.first(where: { $0.id == lineID }) else { return "" }
                return key == .original ? line.originalText : (line.translationText ?? "")
            },
            set: { value in
                editor.updateLine(lineID) { line in
                    if key == .original { line.originalText = value } else { line.translationText = value }
                }
            }
        )
    }

    private func timeField(lineID: UUID, placeholder: String, isEnd: Bool = false) -> some View {
        TextField(placeholder, text: Binding(
            get: {
                guard let line = editor.draft?.lines.first(where: { $0.id == lineID }) else { return "" }
                let value = isEnd ? line.endTime : line.startTime
                return value.map { String(format: "%.3f", $0) } ?? ""
            },
            set: { text in
                let parsed = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : Double(text)
                editor.updateLine(lineID) { line in
                    if isEnd { line.endTime = parsed } else { line.startTime = parsed }
                }
            }
        ))
        .textFieldStyle(.roundedBorder)
        .frame(width: 68)
    }

    private func markFocusedLineAtCurrentTime(advance: Bool) {
        guard let focusedLineID else { return }
        let now = min(max(0, state.currentTime), max(0, state.currentTrack.duration))
        editor.updateLine(focusedLineID) { line in
            line.startTime = now
            if let end = line.endTime, end < now { line.endTime = nil }
        }
        guard advance, let lines = editor.draft?.lines,
              let index = lines.firstIndex(where: { $0.id == focusedLineID }),
              index + 1 < lines.count else { return }
        self.focusedLineID = lines[index + 1].id
    }

    private static func formatTime(_ value: TimeInterval) -> String {
        guard value.isFinite, value >= 0 else { return "00:00" }
        let seconds = Int(value.rounded(.down))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private var footer: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: editor.validation.isSaveAllowed ? "checkmark.circle" : "exclamationmark.triangle")
                .foregroundStyle(editor.validation.isSaveAllowed ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(editor.validation.isSynchronized ? "同步歌词时间轴有效" : "纯文本或部分时间轴：不会自动平均铺开")
                    .font(.caption.weight(.medium))
                if !editor.validation.issues.isEmpty {
                    Text(editor.validation.issues.map(\.message).joined(separator: "；"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else if let message = editor.message {
                    Text(message).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(editor.state.userFacingMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private func importPreview(_ preview: LyricsEditorImportPreview) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("LRC 导入预览").font(.title2.weight(.semibold))
            Text("行数：\(preview.result.lines.count) · \(preview.result.isSynchronized ? "包含逐行时间轴" : "纯文本 / 部分时间轴")")
            if let title = preview.result.metadata.title { Text("标题：\(title)") }
            if let artist = preview.result.metadata.artist { Text("艺人：\(artist)") }
            if preview.match.isMismatchWarning {
                Label("元数据或时长与当前歌曲不完全匹配，请确认是否继续。", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            } else {
                Label("与当前歌曲匹配。原始 LRC 文件不会被修改。", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            }
            if !preview.result.warnings.isEmpty {
                Text(preview.result.warnings.joined(separator: "；"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack {
                Button("取消") { editor.cancelImportPreview() }
                Spacer()
                Button("确认导入并锁定") { editor.confirmImport(lock: true) }
                Button("确认导入") { editor.confirmImport() }
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func importLRC() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "lrc") ?? .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            editor.prepareImport(try String(contentsOf: url, encoding: .utf8))
        } catch {
            editor.prepareImport("")
        }
    }

    private func exportOriginal() {
        guard let draft = editor.draft else { return }
        saveFile(contents: LRCExporter.original(
            document: draft.document(source: draft.source),
            source: draft.source.rawValue,
            locked: false
        ), suggestedName: "\(draft.title ?? "lyrics").lrc")
    }

    private func exportTranslation() {
        guard let draft = editor.draft else { return }
        let selected = editor.selectedTranslation
        let translations = selected?.lines
            .sorted { $0.lineIndex < $1.lineIndex }
            .map(\.translatedText)
            ?? draft.lines.map { $0.translationText ?? "" }
        guard translations.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { return }
        saveFile(contents: LRCExporter.translation(
            document: draft.document(source: draft.source),
            translations: translations,
            targetLanguage: selected?.record.targetLanguage ?? "und",
            source: selected?.record.sourceKind.rawValue ?? "legacyEmbedded",
            locked: selected?.record.isLocked ?? false
        ), suggestedName: "\(draft.title ?? "lyrics").\(selected?.record.targetLanguage ?? "und").lrc")
    }

    private func saveFile(contents: String, suggestedName: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        // `.plainText` makes NSSavePanel append `.txt` to an otherwise valid
        // LRC filename. Use the dynamic LRC UTI so exports remain reparsable
        // as `song.lrc` / `song.zh-Hans.lrc`.
        panel.allowedContentTypes = [UTType(filenameExtension: "lrc") ?? .data]
        panel.allowsOtherFileTypes = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try contents.write(to: url, atomically: true, encoding: .utf8)
            editor.reportExportResult("已导出 LRC：\(url.lastPathComponent)")
        } catch {
            editor.reportExportResult("导出失败：\(error.localizedDescription)")
        }
    }
}

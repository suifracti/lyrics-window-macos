import SwiftUI

/// Compact, in-place operations for the currently playing TrackIdentity.
/// Every command is forwarded to the existing PlaybackState/session methods;
/// this view owns no repository, search task, timer, or playback command.
struct CurrentSongOperationsView: View {
    @ObservedObject var state: PlaybackState
    @EnvironmentObject private var settings: AppSettingsStore
    @Environment(\.openWindow) private var openWindow

    @State private var notice = ""
    @State private var showDeleteTranslationConfirmation = false
    @State private var showCandidatePreview = false

    private var snapshot: CurrentSongOperationSnapshot {
        CurrentSongOperationSnapshot(
            title: state.currentTrack.title,
            artist: state.currentTrack.artist,
            lyricsState: CurrentSongLyricsState(loadState: state.liveLyricsState),
            lyricsSource: state.liveLyricsSource,
            lyricsVersionID: state.liveLyricsVersionID,
            isSynchronized: state.liveLyricsAreSynchronized,
            isLyricsNoSelection: state.isLyricsSelectionEmpty,
            hasTranslationSelection: !state.isTranslationSelectionEmpty,
            translationVersionCount: state.translationVersions.count
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            lyricsSection
            versionStatusSection
            Divider()
            languageSection
            if !state.liveLyrics.isEmpty {
                Divider()
                translationSection
            }
            if hasAlignmentAction {
                Divider()
                alignmentSection
            }
            if !notice.isEmpty {
                Text(notice)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .frame(width: 360, alignment: .leading)
        .preferredColorScheme(.dark)
        .confirmationDialog(
            "删除当前翻译版本？",
            isPresented: $showDeleteTranslationConfirmation,
            titleVisibility: .visible
        ) {
            Button("删除翻译", role: .destructive) { state.deleteSelectedTranslation() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("不会删除原文、读音或歌词版本。")
        }
        .sheet(isPresented: $showCandidatePreview) {
            if let candidate = state.translationSessionPendingCandidate {
                TranslationCandidatePreviewView(candidate: candidate)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("当前歌曲")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            Text(snapshot.title)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .lineLimit(1)
            Text(snapshot.artist)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var lyricsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("歌词版本", systemImage: "text.quote")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                Spacer()
                Text(snapshot.lyricsStatusLabel)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(snapshot.isLyricsNoSelection ? .orange : .secondary)
            }
            if let source = state.liveLyricsSource {
                Text("来源：\(source.displayName)")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                primaryLyricsButton
                Menu {
                    Button("重新搜索歌词", systemImage: "arrow.clockwise") {
                        state.retryLyrics()
                    }
                    if state.canCreateManualLyrics {
                        Divider()
                        importCreateMenu
                    }
                    Divider()
                    Button("本次播放不使用", systemImage: "minus.circle") {
                        state.selectNoLyricsVersion()
                    }
                    .disabled(state.isLyricsSelectionEmpty)
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 28, height: 28)
                }
                .menuStyle(.borderlessButton)
                .help("歌词版本操作")
            }
            if state.canOpenLyricsEditor {
                Button("查看版本历史", systemImage: "clock.arrow.circlepath") {
                    openEditor()
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
        }
    }

    /// The current-song popover keeps the status vocabulary visible without
    /// pretending that every status is present on the current record. The
    /// detailed version list remains in the shared editor/history surface.
    private var versionStatusSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label("版本状态", systemImage: "tag")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                Spacer()
                Text(snapshot.isLyricsNoSelection ? "本次播放不使用" : "当前使用")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(snapshot.isLyricsNoSelection ? .orange : .secondary)
            }
            HStack(spacing: 6) {
                statusChip(snapshot.isLyricsNoSelection ? "本次播放不使用" : "当前使用")
                if let source = state.liveLyricsSource {
                    if source == .neteaseExperimental || source == .qqExperimental {
                        statusChip("实验")
                    }
                    if source == .manualImport || source == .manualCreate || source == .manualEdit || source == .automaticAlignment {
                        statusChip("非默认")
                    }
                }
                statusChip(state.liveLyricsAreSynchronized ? "已排轴" : "未排轴")
            }
            Menu("状态说明", systemImage: "info.circle") {
                Text("当前使用：本次 Session 正在显示的版本")
                Text("推荐：Provider 或本地仓库建议的版本")
                Text("非默认：用户导入、创建、编辑或排轴版本")
                Text("已归档：保留记录但不再作为默认候选")
                Text("实验：实验 Provider 或实验呈现")
                Text("锁定：不会被网络或 AI 自动覆盖")
            }
            .menuStyle(.borderlessButton)
            .font(.system(size: 11, design: .rounded))
            .foregroundStyle(.secondary)
        }
    }

    private func statusChip(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.quaternary.opacity(0.45), in: Capsule())
    }

    @ViewBuilder
    private var primaryLyricsButton: some View {
        switch snapshot.primaryLyricsAction {
        case .edit:
            Button("编辑当前版本", systemImage: "pencil") { openEditor() }
                .buttonStyle(.borderedProminent)
        case .chooseVersion:
            Button("选择歌词版本", systemImage: "checklist") { state.retryLyrics() }
                .buttonStyle(.bordered)
        case .importOrCreate:
            Menu("导入或创建", systemImage: "square.and.arrow.down") {
                importCreateMenu
            }
            .menuStyle(.borderedButton)
        case .none:
            Button("重新搜索歌词", systemImage: "magnifyingglass") { state.retryLyrics() }
                .buttonStyle(.bordered)
                .disabled(!state.hasLiveTrack)
        }
    }

    @ViewBuilder
    private var importCreateMenu: some View {
        Button("粘贴歌词", systemImage: "doc.on.clipboard") {
            if state.prepareManualLyricsFromClipboard() { openWindow(id: "lyrics-editor") }
        }
        Button("导入 TXT", systemImage: "doc.text") {
            if state.prepareManualLyricsFromTXT() { openWindow(id: "lyrics-editor") }
        }
        Button("导入 LRC", systemImage: "clock") {
            if state.prepareManualLyricsFromLRC() { openWindow(id: "lyrics-editor") }
        }
        Button("创建空白歌词", systemImage: "plus.square") {
            if state.prepareBlankLyricsEditor() { openWindow(id: "lyrics-editor") }
        }
    }

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("显示层")
                .font(.system(size: 12, weight: .medium, design: .rounded))
            Toggle("显示翻译", isOn: displayBinding(\.showTranslation))
            Toggle("显示假名", isOn: kanaBinding)
            Toggle("显示罗马音", isOn: displayBinding(\.showRomaji))
            if settings.displayPreferences.showKana {
                Picker("假名模式", selection: displayBinding(\.kanaDisplayMode)) {
                    Text("汉字上方注音").tag(KanaDisplayMode.inlineRuby)
                    Text("独立假名行").tag(KanaDisplayMode.independentLine)
                    Text("假名替换").tag(KanaDisplayMode.kanaReplacement)
                }
                .pickerStyle(.menu)
            }
            Text("隐藏翻译只改变显示层；无翻译版本会改变当前选择。")
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private var translationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("翻译版本", systemImage: "character.book.closed")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                Spacer()
                Text(snapshot.translationStatusLabel)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(state.isTranslationSelectionEmpty ? .orange : .secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                Picker("引擎", selection: configurationStringBinding(\.engineID)) {
                    ForEach(TranslationEngineCatalog.all, id: \.stableID) { engine in
                        Text(engine.displayName).tag(engine.stableID)
                    }
                }
                Picker("提示词", selection: configurationStringBinding(\.promptPresetID)) {
                    ForEach(TranslationPromptPresetCatalog.all, id: \.id) { preset in
                        Text(preset.displayName).tag(preset.id.rawValue)
                    }
                }
                Text("模型：\(settings.aiTranslationConfiguration.model.isEmpty ? "手动输入" : settings.aiTranslationConfiguration.model)")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            if let candidate = state.translationSessionPendingCandidate {
                HStack(spacing: 8) {
                    Label("新候选待采用", systemImage: "sparkles")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                    Spacer()
                    Button("预览") { showCandidatePreview = true }
                    Button("采用") { state.adoptTranslation(versionID: candidate.record.id) }
                }
                .padding(8)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
            }
            Menu {
                Button("无翻译版本") { state.selectNoTranslationVersion() }
                    .disabled(state.isTranslationSelectionEmpty)
                if !state.translationVersions.isEmpty { Divider() }
                ForEach(state.translationVersions, id: \.record.id) { version in
                    Button {
                        state.selectTranslation(versionID: version.record.id)
                    } label: {
                        Text(versionTitle(version))
                    }
                }
                Divider()
                Button("翻译整首歌词") { state.translateCurrentLyrics() }
                Button("重新翻译") { state.retranslateCurrentLyrics() }
                if case .loading = state.translationState {
                    Button("取消翻译") { state.cancelTranslation() }
                }
                Button("恢复推荐") { state.restoreRecommendedTranslation() }
                if let candidate = state.translationSessionPendingCandidate {
                    Button("预览候选") { showCandidatePreview = true }
                    Button("采用候选") { state.adoptTranslation(versionID: candidate.record.id) }
                    Button("归档候选") { state.archiveTranslation(versionID: candidate.record.id) }
                }
                if state.selectedTranslation?.record.isLocked == false {
                    Divider()
                    Button("锁定当前翻译") { state.lockSelectedTranslation() }
                    Button("删除当前翻译", role: .destructive) {
                        showDeleteTranslationConfirmation = true
                    }
                    Button("归档当前翻译") {
                        if let id = state.selectedTranslation?.record.id { state.archiveTranslation(versionID: id) }
                    }
                }
            } label: {
                Label("选择翻译版本", systemImage: "chevron.up.chevron.down")
            }
            .menuStyle(.borderedButton)
        }
    }

    private var hasAlignmentAction: Bool {
        switch state.liveLyricsState {
        case .alignmentQueued, .alignmentRunning, .alignmentPreview:
            return true
        default:
            return false
        }
    }

    @ViewBuilder
    private var alignmentSection: some View {
        switch state.liveLyricsState {
        case .alignmentQueued:
            HStack {
                Label("待排轴", systemImage: "waveform")
                Spacer()
                Button("选择本地音频") { state.alignCurrentLyricsWithLocalAudio() }
            }
        case .alignmentRunning:
            HStack {
                Label("正在排轴", systemImage: "waveform")
                Spacer()
                Button("取消") { state.cancelAlignmentPreview() }
            }
        case .alignmentPreview:
            HStack {
                Label("排轴预览", systemImage: "waveform.path.ecg")
                Spacer()
                Button("确认") { state.confirmAlignmentPreview(saveLocal: true) }
                Button("放弃") { state.cancelAlignmentPreview() }
            }
        default:
            EmptyView()
        }
    }

    private func openEditor() {
        state.prepareLyricsEditor()
        openWindow(id: "lyrics-editor")
    }

    private func versionTitle(_ version: StoredTranslationVersion) -> String {
        let model = version.record.model.isEmpty ? version.record.sourceKind.rawValue : version.record.model
        if version.record.isDraft { return "候选 · \(model)" }
        if version.record.isArchived { return "已归档 · \(model)" }
        return version.record.isLocked ? "🔒 \(model)" : model
    }

    private func configurationStringBinding(_ keyPath: WritableKeyPath<AITranslationConfiguration, String>) -> Binding<String> {
        Binding(
            get: { settings.aiTranslationConfiguration[keyPath: keyPath] },
            set: { value in
                var next = settings.aiTranslationConfiguration
                next[keyPath: keyPath] = value
                settings.aiTranslationConfiguration = next
            }
        )
    }

    private func displayBinding<Value>(_ keyPath: WritableKeyPath<DisplayPreferences, Value>) -> Binding<Value> {
        Binding(
            get: { settings.displayPreferences[keyPath: keyPath] },
            set: { value in
                var next = settings.displayPreferences
                next[keyPath: keyPath] = value
                settings.displayPreferences = next
            }
        )
    }

    private var kanaBinding: Binding<Bool> {
        Binding(
            get: { settings.displayPreferences.showKana },
            set: { value in
                var next = settings.displayPreferences
                next.showKana = value
                settings.displayPreferences = next
            }
        )
    }
}

private struct TranslationCandidatePreviewView: View {
    let candidate: StoredTranslationVersion
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("翻译候选预览").font(.title3.weight(.semibold))
                Spacer()
                Button("关闭") { dismiss() }
            }
            Text("候选不会覆盖当前翻译，确认后再采用。")
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(candidate.lines, id: \.lineIndex) { line in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(line.lineIndex + 1)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 28, alignment: .trailing)
                            Text(line.translatedText.isEmpty ? "（空白行）" : line.translatedText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 520, height: 520)
    }
}

import SwiftUI

/// Compact, in-place operations for the currently playing TrackIdentity.
/// Every command is forwarded to the existing PlaybackState/session methods;
/// this view owns no repository, search task, timer, or playback command.
struct CurrentSongOperationsView: View {
    @ObservedObject var state: PlaybackState
    @ObservedObject private var autoAlign = AutomaticAlignmentJobController.shared
    @EnvironmentObject private var settings: AppSettingsStore
    @Environment(\.openWindow) private var openWindow

    @State private var notice = ""
    @State private var showDeleteTranslationConfirmation = false
    @State private var showDeleteReadingConfirmation = false
    @State private var pendingReadingDeletionID: UUID?
    @State private var showCandidatePreview = false
    @State private var showReadingEditor = false

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
            Divider()
            readingSection
            if !state.liveLyrics.isEmpty {
                Divider()
                translationSection
            }
            if showsAutomaticAlignmentSection {
                Divider()
                automaticAlignmentSection
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
        .confirmationDialog(
            "删除当前读音版本？",
            isPresented: $showDeleteReadingConfirmation,
            titleVisibility: .visible
        ) {
            Button("删除读音版本", role: .destructive) {
                if let versionID = pendingReadingDeletionID {
                    state.deleteReading(versionID: versionID)
                }
                pendingReadingDeletionID = nil
            }
            Button("取消", role: .cancel) {
                pendingReadingDeletionID = nil
            }
        } message: {
            Text("不会删除原文、歌词版本、翻译或时间轴。锁定版本仍不可删除。")
        }
        .sheet(isPresented: $showCandidatePreview) {
            if let candidate = state.translationSessionPendingCandidate {
                TranslationCandidatePreviewView(candidate: candidate)
            }
        }
        .sheet(isPresented: $showReadingEditor) {
            if let version = state.selectedReadingVersion {
                ReadingVersionEditorView(state: state, version: version)
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
            // Read-only status only — settings owns the single mode control.
            HStack(spacing: 6) {
                Text("歌词来源：\(settings.lyricsSourceMode.shortTitle)")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
                if settings.lyricsSourceMode.isExperimental {
                    Text("实验")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.orange)
                }
            }
            .accessibilityIdentifier("currentSong.lyricsSourceMode.readonly")
            .accessibilityElement(children: .combine)
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

    private var readingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("读音版本", systemImage: "character.book.closed")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                Spacer()
                if state.selectedReadingVersion?.record.isLocked == true {
                    Text("锁定")
                        .foregroundStyle(.green)
                } else if state.selectedReadingVersion != nil {
                    Text("当前使用")
                        .foregroundStyle(.secondary)
                } else {
                    Text("无")
                        .foregroundStyle(.orange)
                }
            }
            if let version = state.selectedReadingVersion {
                Text("\(version.record.representationID) · \(version.record.engineID)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Menu("选择版本", systemImage: "chevron.up.chevron.down") {
                        Button("无读音版本") { state.selectNoReadingVersion() }
                        Divider()
                        ForEach(state.readingVersions, id: \.record.id) { candidate in
                            Button(readingVersionTitle(candidate)) {
                                state.selectReadingVersion(versionID: candidate.record.id)
                            }
                        }
                    }
                    .menuStyle(.borderlessButton)
                    Button("编辑") { showReadingEditor = true }
                        .buttonStyle(.borderless)
                    if !version.record.isLocked {
                        Button("锁定") { state.lockSelectedReading() }
                            .buttonStyle(.borderless)
                    }
                    Menu {
                        Button("无读音版本") { state.selectNoReadingVersion() }
                            .disabled(state.selectedReadingVersion == nil)
                        Button("恢复推荐") { state.restoreRecommendedReading() }
                        Divider()
                        Button("重新生成假名") { state.generateCurrentReading(representationID: .kana) }
                        Button("重新生成罗马音") { state.generateCurrentReading(representationID: .romaji) }
                        Button("生成拼音") { state.generateCurrentReading(representationID: .pinyinToneMarks) }
                        if !version.record.isLocked {
                            Divider()
                            Button("归档") { state.archiveReading(versionID: version.record.id) }
                            Button("删除", role: .destructive) {
                                pendingReadingDeletionID = version.record.id
                                showDeleteReadingConfirmation = true
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .menuStyle(.borderlessButton)
                }
            } else {
                HStack(spacing: 8) {
                    Button("选择无") { state.selectNoReadingVersion() }
                        .buttonStyle(.borderless)
                    if !state.readingVersions.isEmpty {
                        Menu("选择版本") {
                            ForEach(state.readingVersions, id: \.record.id) { candidate in
                                Button(readingVersionTitle(candidate)) {
                                    state.selectReadingVersion(versionID: candidate.record.id)
                                }
                            }
                        }
                        .menuStyle(.borderlessButton)
                    }
                    Button("生成假名") { state.generateCurrentReading(representationID: .kana) }
                        .buttonStyle(.borderless)
                    Button("生成拼音") { state.generateCurrentReading(representationID: .pinyinToneMarks) }
                        .buttonStyle(.borderless)
                }
            }
            if state.isReadingGenerating {
                ProgressView("生成读音…")
                    .controlSize(.small)
            } else if !state.readingMessage.isEmpty {
                Text(state.readingMessage)
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Text("读音版本独立保存；不修改原文、时间轴或翻译。")
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    /// Product zero-operation status — visible when switch on or a job is active.
    private var showsAutomaticAlignmentSection: Bool {
        if settings.automaticAlignmentEnabled { return true }
        switch autoAlign.state {
        case .idle, .canceled:
            return false
        default:
            return !autoAlign.statusMessage.isEmpty
        }
    }

    private var hasAlignmentAction: Bool {
        switch state.liveLyricsState {
        case .alignmentQueued, .alignmentRunning, .alignmentPreview:
            return true
        default:
            break
        }
#if DEBUG
        if state.showsListeningAssistControls { return true }
#endif
        return false
    }

    @ViewBuilder
    private var automaticAlignmentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("自动时间轴", systemImage: "timeline.selection")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                Spacer()
                Text(autoAlignStatusLabel)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(autoAlignStatusColor)
                    .accessibilityIdentifier("autoAlign.status")
            }
            if !autoAlign.statusMessage.isEmpty {
                Text(autoAlign.statusMessage)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if settings.automaticAlignmentEnabled {
                Text("播放未排轴歌曲时会在后台尝试生成时间轴。")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                if autoAlignJobIsActive {
                    Button("停止本次") {
                        autoAlign.cancelCurrentJob(userInitiated: true)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("autoAlign.stop")
                }
                if settings.automaticAlignmentEnabled,
                   !state.liveLyricsAreSynchronized,
                   state.hasLiveTrack {
                    Button("重新尝试") {
                        autoAlign.retry()
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("autoAlign.retry")
                }
#if DEBUG
                if state.showsListeningAssistControls || state.canStartListeningAssist {
                    Button("打开排轴工作台") {
                        state.presentListeningAssistExplanation()
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("autoAlign.openWorkbench")
                }
#endif
            }
        }
    }

    private var autoAlignJobIsActive: Bool {
        switch autoAlign.state {
        case .capturing, .paused, .aligning, .evaluating, .waitingForPlayback, .accumulating, .deferred:
            return true
        default:
            return false
        }
    }

    private var autoAlignStatusLabel: String {
        switch autoAlign.state {
        case .idle: return settings.automaticAlignmentEnabled ? "就绪" : "关闭"
        case .waitingForPlayback: return "等待播放"
        case .capturing, .aligning, .evaluating: return "正在生成时间轴"
        case .paused: return "已暂停"
        case .accumulating: return "已保存部分进度"
        case .completed: return "已完成"
        case .failed: return "本次无法可靠完成"
        case .canceled: return "已停止"
        case .deferred:
            if autoAlign.statusMessage.contains("引擎") {
                return "引擎尚未准备好"
            }
            return "等待继续播放"
        }
    }

    private var autoAlignStatusColor: Color {
        switch autoAlign.state {
        case .completed: return .green
        case .failed, .canceled: return .orange
        case .capturing, .aligning, .evaluating: return .primary
        default: return .secondary
        }
    }

    private func readingVersionTitle(_ version: StoredReadingVersion) -> String {
        var labels: [String] = []
        if version.record.isLocked { labels.append("锁定") }
        if version.record.isCurrent { labels.append("当前") }
        if version.record.isArchived { labels.append("已归档") }
        if version.record.isManuallyEdited { labels.append("人工") }
        let suffix = labels.isEmpty ? "" : " · " + labels.joined(separator: "/")
        return "\(version.record.representationID)\(suffix)"
    }

    @ViewBuilder
    private var alignmentSection: some View {
        switch state.liveLyricsState {
        case .alignmentQueued:
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("待排轴", systemImage: "waveform")
                    Spacer()
                    Button("选择本地音频") { state.alignCurrentLyricsWithLocalAudio() }
                }
#if DEBUG
                listeningAssistControls
#endif
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
#if DEBUG
            if state.showsListeningAssistControls {
                VStack(alignment: .leading, spacing: 8) {
                    Label("边听边排轴", systemImage: "ear")
                    listeningAssistControls
                }
            } else {
                EmptyView()
            }
#else
            EmptyView()
#endif
        }
    }

#if DEBUG
    /// Product-facing Assist controls (no S1/S2/S3A / DP / confidence jargon).
    @ViewBuilder
    private var listeningAssistControls: some View {
        switch state.assistPhase {
        case .idle, .cancelled:
            if state.canStartListeningAssist {
                Button("边听边排轴") {
                    state.presentListeningAssistExplanation()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("assist.listening.start")
            }
        case .explaining:
            Text(state.assistStatusMessage.isEmpty
                 ? "请在说明中选择开始或取消"
                 : state.assistStatusMessage)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button("打开说明") {
                    state.isAssistExplainSheetPresented = true
                }
                .buttonStyle(.bordered)
                Button("取消") {
                    state.cancelListeningAssist()
                }
                .buttonStyle(.bordered)
            }
            .accessibilityIdentifier("assist.listening.explaining")
        case .capturing, .merging:
            Text(state.assistStatusMessage.isEmpty
                 ? "正在分析当前歌曲…"
                 : state.assistStatusMessage)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("取消边听边排") {
                state.cancelListeningAssist()
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("assist.listening.cancel")
        case .ready:
            Text(state.assistStatusMessage.isEmpty
                 ? "已生成时间建议（尚未保存）"
                 : state.assistStatusMessage)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("打开编辑草稿") {
                    state.openListeningAssistEditorWithDraft()
                    openEditor()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("assist.listening.openEditor")
                if state.canStartListeningAssist {
                    Button("重新开始") {
                        state.presentListeningAssistExplanation()
                    }
                    .buttonStyle(.bordered)
                }
            }
        case .failed:
            Text(state.assistStatusMessage.isEmpty
                 ? "未能完成边听边排轴"
                 : state.assistStatusMessage)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            if state.canStartListeningAssist {
                Button("重试边听边排轴") {
                    state.presentListeningAssistExplanation()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("assist.listening.retry")
            }
        }
    }
#endif

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

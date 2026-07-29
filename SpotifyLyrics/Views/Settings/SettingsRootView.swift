import SwiftUI
import AppKit

private enum SettingsCategory: String, CaseIterable, Identifiable {
    case general = "通用"
    case display = "歌词显示"
    case spotify = "Spotify"
    case lyricsSources = "歌词来源"
    case data = "数据与存储"
    case advanced = "高级"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .display: return "text.quote"
        case .spotify: return "waveform.circle"
        case .lyricsSources: return "books.vertical"
        case .data: return "externaldrive"
        case .advanced: return "wrench.and.screwdriver"
        }
    }
}

struct SettingsRootView: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @State private var selection: SettingsCategory = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsCategory.allCases, selection: $selection) { category in
                Label(category.rawValue, systemImage: category.systemImage)
                    .tag(category)
            }
            .listStyle(.sidebar)
            .navigationTitle("设置")
            .frame(minWidth: 180)
        } detail: {
            SettingsDetailView(category: selection)
                .environmentObject(settings)
        }
        .frame(minWidth: 780, idealWidth: 860, minHeight: 500, idealHeight: 580)
        .preferredColorScheme(.dark)
    }
}

private struct SettingsDetailView: View {
    let category: SettingsCategory

    var body: some View {
        Group {
            switch category {
            case .general: GeneralSettingsView()
            case .display: DisplaySettingsView()
            case .spotify: SpotifySettingsView()
            case .lyricsSources: LyricsSourcesSettingsView()
            case .data: DataSettingsView()
            case .advanced: AdvancedSettingsView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(28)
    }
}

private struct SettingsPageHeader: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 25, weight: .semibold, design: .rounded))
            Text(detail)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 10)
    }
}

private struct GeneralSettingsView: View {
    @EnvironmentObject private var settings: AppSettingsStore

    var body: some View {
        Form {
            SettingsPageHeader(title: "通用", detail: "控制启动、切歌和主窗口的默认行为。")

            Section("主窗口") {
                Picker("默认主窗口布局", selection: $settings.mainWindowLayoutStyleRawValue) {
                    ForEach(MainWindowLayoutStyle.allCases) { layout in
                        Text(layout == .immersiveSplit ? "\(layout.title)（deprecated candidate）" : layout.title)
                            .tag(layout.rawValue)
                    }
                }
                Text("沉浸分栏仅保留兼容入口，不作为推荐默认布局。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("启动时恢复上次窗口状态", isOn: $settings.restoreWindowState)
                Toggle("主窗口保持置顶", isOn: $settings.keepMainWindowOnTop)
            }

            Section("启动与切歌") {
                Toggle("启动时自动连接 Spotify Desktop", isOn: $settings.connectSpotifyOnLaunch)
                Toggle("切歌后自动搜索歌词", isOn: $settings.autoSearchLyricsOnTrackChange)
            }
        }
        .formStyle(.grouped)
    }
}

private struct DisplaySettingsView: View {
    @EnvironmentObject private var settings: AppSettingsStore

    var body: some View {
        Form {
            SettingsPageHeader(title: "歌词显示", detail: "V3 和歌词专注模式共用这些显示层设置，修改后立即生效。")

            Section("语言层") {
                Toggle("显示原文", isOn: preferenceBinding(\.showOriginal))
                Toggle("显示翻译", isOn: preferenceBinding(\.showTranslation))
                Toggle("显示罗马音", isOn: preferenceBinding(\.showRomaji))
                Picker("假名显示模式", selection: preferenceBinding(\.kanaDisplayMode)) {
                    Text("汉字上方注音").tag(KanaDisplayMode.inlineRuby)
                    Text("独立假名行").tag(KanaDisplayMode.independentLine)
                    Text("假名替换").tag(KanaDisplayMode.kanaReplacement)
                    Text("隐藏").tag(KanaDisplayMode.hidden)
                }
                Text(settings.displayPreferences.kanaDisplayMode.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("字号与层级") {
                numericSlider("当前歌词字号", value: doubleBinding(\.fontSize), range: 14...42, format: "%.0f pt")
                numericSlider("辅助文本字号", value: doubleBinding(\.assistantFontSize), range: 10...24, format: "%.0f pt")
                numericSlider("Ruby 假名大小", value: doubleBinding(\.rubyFontSize), range: 8...18, format: "%.0f pt")
                numericSlider("非当前歌词透明度", value: preferenceBinding(\.opacity), range: 0.15...1, format: "%.0f%%", scale: 100)
                Toggle("远处歌词隐藏 Ruby 和罗马音", isOn: preferenceBinding(\.hideDistantAuxiliary))
            }
        }
        .formStyle(.grouped)
    }

    private func preferenceBinding<Value>(_ keyPath: WritableKeyPath<DisplayPreferences, Value>) -> Binding<Value> {
        Binding(
            get: { settings.displayPreferences[keyPath: keyPath] },
            set: { value in
                var next = settings.displayPreferences
                next[keyPath: keyPath] = value
                settings.displayPreferences = next
            }
        )
    }

    private func doubleBinding(_ keyPath: WritableKeyPath<DisplayPreferences, CGFloat>) -> Binding<Double> {
        Binding(
            get: { Double(settings.displayPreferences[keyPath: keyPath]) },
            set: { value in
                var next = settings.displayPreferences
                next[keyPath: keyPath] = CGFloat(value)
                settings.displayPreferences = next
            }
        )
    }

    private func numericSlider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        format: String,
        scale: Double = 1
    ) -> some View {
        HStack {
            Text(title)
            Slider(value: value, in: range)
            Text(String(format: format, value.wrappedValue * scale))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .trailing)
        }
    }
}

private struct SpotifySettingsView: View {
    @EnvironmentObject private var playbackState: PlaybackState
    @State private var clientIDDraft = ""

    private var authorization: SpotifyAuthorizationManager {
        playbackState.spotifyAuthorizationManager
    }

    var body: some View {
        Form {
            SettingsPageHeader(title: "Spotify", detail: "Desktop 控制和 Web 在线目录授权彼此独立。Access Token 与 Refresh Token 永远不在此页面显示。")

            Section("Spotify Desktop") {
                LabeledContent("连接状态", value: playbackState.providerStatus.userFacingMessage)
                Text("桌面播放控制不依赖 Spotify Web OAuth。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Spotify Web 在线曲库") {
                LabeledContent("授权状态", value: authorization.state.userFacingMessage)
                HStack {
                    TextField("Client ID", text: $clientIDDraft)
                        .textFieldStyle(.roundedBorder)
                    Button("保存") { authorization.updateClientID(clientIDDraft) }
                        .buttonStyle(.bordered)
                }
                Text("只填写 Spotify Developer Dashboard 中的 Client ID，不需要 Client Secret。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("授权 Spotify") { authorize() }
                        .buttonStyle(.borderedProminent)
                    Button("刷新授权状态") { authorization.refreshAuthorizationState() }
                    Button("断开授权") { authorization.disconnect() }
                        .disabled(!authorization.state.isAuthorized)
                    Button("清除 Keychain Token") { authorization.disconnect() }
                        .disabled(!authorization.state.isAuthorized)
                }
                LabeledContent("Dashboard 注册地址") {
                    Text(authorization.dashboardRedirectURI)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
                LabeledContent("当前本地监听地址") {
                    Text(authorization.localRedirectURI ?? "未启动（授权时动态分配端口）")
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
                Text("Dashboard 只需注册不带端口的回环地址；授权时应用会临时监听一个动态端口，并在请求和换取 Token 时使用同一个完整地址。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("授权失败不会影响 Spotify Desktop 当前播放和本地歌词链路。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { clientIDDraft = authorization.clientID ?? "" }
    }

    private func authorize() {
        authorization.updateClientID(clientIDDraft)
        authorization.authorize()
    }
}

private struct LyricsSourcesSettingsView: View {
    @EnvironmentObject private var settings: AppSettingsStore

    var body: some View {
        Form {
            SettingsPageHeader(title: "歌词来源", detail: "SQLite 和本地文件始终保留；在线 Provider 可单独关闭并调整顺序。")

            Section("Provider 顺序") {
                ForEach(Array(settings.lyricsProviderConfiguration.order.enumerated()), id: \.element) { index, id in
                    providerRow(id: id, index: index)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func providerRow(id: LyricsProviderID, index: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: id.systemImage)
                .frame(width: 22)
                .foregroundStyle(id.isExperimental ? .orange : .accentColor)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(id.title)
                        .fontWeight(.medium)
                    Text(id.stabilityLabel)
                        .font(.caption2)
                        .foregroundStyle(id.isExperimental ? .orange : .secondary)
                }
                Text(id.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("启用", isOn: Binding(
                get: { settings.isProviderEnabled(id) },
                set: { settings.setProviderEnabled(id, enabled: $0) }
            ))
            .labelsHidden()
            .disabled(id.isLocal)
            Button { settings.moveProvider(id, offset: -1) } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(index == 0)
            Button { settings.moveProvider(id, offset: 1) } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(index == settings.lyricsProviderConfiguration.order.count - 1)
        }
        .help(id.detail)
    }
}

private struct DataSettingsView: View {
    @EnvironmentObject private var data: SettingsDataController
    @State private var showClearConfirmation = false

    var body: some View {
        Form {
            SettingsPageHeader(title: "数据与存储", detail: "数据库操作在后台执行；本地歌词目录仍保持只读。")

            Section("SQLite 数据库") {
                LabeledContent("路径", value: data.statistics?.databaseURL.path ?? SQLiteLyricsRepository.defaultDatabaseURL.path)
                    .textSelection(.enabled)
                LabeledContent("Migration", value: "v\(data.statistics?.schemaVersion ?? DatabaseMigrator.currentVersion)")
                LabeledContent("Track 数量", value: "\(data.statistics?.trackCount ?? 0)")
                LabeledContent("LyricsVersion 数量", value: "\(data.statistics?.lyricsVersionCount ?? 0)")
                LabeledContent("LyricLine 数量", value: "\(data.statistics?.lyricLineCount ?? 0)")
                LabeledContent("数据库大小", value: data.statistics.map { ByteCountFormatter.string(fromByteCount: $0.fileSize, countStyle: .file) } ?? "未知")
                HStack {
                    Button("刷新统计") { data.refreshStatistics() }
                    Button("在 Finder 中显示") { data.revealDatabase() }
                    Button("创建备份") { data.createBackup() }
                }
            }

            Section("本地歌词") {
                Button("重建本地歌词索引") { data.rebuildLocalIndex() }
                Text("只扫描 ~/Music/SpotifyLyrics/Lyrics、应用支持目录和 Debug 兼容目录，不写入或修改用户文件。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("危险操作") {
                Button("清除所有歌词缓存", role: .destructive) { showClearConfirmation = true }
                Text("只删除 SQLite 中的歌词版本和行，保留歌曲元数据；操作前应先创建备份。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !data.statusMessage.isEmpty {
                Text(data.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { data.refreshStatistics() }
        .confirmationDialog("清除所有歌词缓存？", isPresented: $showClearConfirmation, titleVisibility: .visible) {
            Button("创建备份并清除", role: .destructive) {
                data.backupAndClearLyricsCache()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这会删除 SQLite 中的 LyricsVersion 和 LyricLine，不会修改本地 LRC 文件。")
        }
    }
}

private struct AdvancedSettingsView: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var data: SettingsDataController

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发构建"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "未指定"
        return "\(version) (\(build))"
    }

    var body: some View {
        Form {
            SettingsPageHeader(title: "高级", detail: "仅放置诊断和开发相关入口，不显示原始日志或授权敏感数据。")

            Section("诊断") {
                LabeledContent("App Build", value: appVersion)
                LabeledContent("数据库 Schema", value: "v\(DatabaseMigrator.currentVersion)")
                Button("打开日志目录") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/tmp"))
                }
                Button("导出脱敏诊断摘要") { data.exportDiagnostics() }
            }

            Section("窗口状态") {
                Button("重置窗口状态") { settings.resetWindowState() }
                Text("会删除保存的窗口位置，下次打开使用系统默认位置。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Migration v2 规划") {
                Text("当前数据库为 v1。历史 URI/ID stableKey 重复需要先备份，再按 Spotify ID 选择 canonical Track，重定向 aliases、lyrics_versions 和 lyric_lines，并保留 locked/manuallyEdited 版本。本阶段不执行合并。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}

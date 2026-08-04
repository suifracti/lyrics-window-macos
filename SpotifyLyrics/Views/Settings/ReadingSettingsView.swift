import SwiftUI

struct ReadingSettingsView: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @State private var dictionaryEntries: [ReadingDictionaryEntry] = []
    @State private var newSurface = ""
    @State private var newReading = ""
    @State private var newLanguage: ReadingLanguage = .japanese
    @State private var newTrackScope = ""
    @State private var newArtistScope = ""
    @State private var newPriority = "0"
    @State private var newNotes = ""

    var body: some View {
        Form {
            VStack(alignment: .leading, spacing: 5) {
                Text("读音与文字")
                    .font(.system(size: 25, weight: .semibold, design: .rounded))
                Text("日语上下文读音、中文拼音和繁简显示使用同一份共享设置。")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 10)

            Section("日语") {
                Picker("读音引擎", selection: readingBinding(\.japaneseEngineID)) {
                    Text("上下文读音 v2").tag(ReadingEngineID.japaneseContextual.rawValue)
                    Text("词典读音 v1").tag(ReadingEngineID.japaneseDictionary.rawValue)
                }
                Picker("默认读音层", selection: readingBinding(\.japaneseRepresentationID)) {
                    Text("假名").tag(ReadingRepresentationID.kana.rawValue)
                    Text("罗马音").tag(ReadingRepresentationID.romaji.rawValue)
                }
            }

            Section("中文") {
                Toggle("显示拼音", isOn: displayBinding(\.showPinyin))
                Picker("拼音格式", selection: readingBinding(\.pinyinRepresentationID)) {
                    Text("声调符号").tag(ReadingRepresentationID.pinyinToneMarks.rawValue)
                    Text("声调数字").tag(ReadingRepresentationID.pinyinToneNumbers.rawValue)
                    Text("无声调").tag(ReadingRepresentationID.pinyinPlain.rawValue)
                }
            }

            Section("繁简转换") {
                Picker("脚本显示", selection: readingBinding(\.scriptConversionID)) {
                    Text("不转换").tag(ScriptConversionID.none.rawValue)
                    Text("繁体转简体").tag(ScriptConversionID.traditionalToSimplified.rawValue)
                    Text("简体转繁体").tag(ScriptConversionID.simplifiedToTraditional.rawValue)
                }
                Text("转换只影响显示层，不修改原文、歌词版本或翻译。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("生成策略") {
                Toggle("自动生成新歌词读音", isOn: readingBinding(\.automaticGeneration))
                Toggle("允许 AI 辅助候选（仅明确调用）", isOn: readingBinding(\.aiAssistedCandidate))
                Picker("不确定读音", selection: readingBinding(\.uncertaintyPolicy)) {
                    ForEach(ReadingUncertaintyPolicy.allCases, id: \.self) { policy in
                        Text(policy.displayName).tag(policy)
                    }
                }
                Text("当前版本只使用本地引擎生成；不会因浏览设置而发送 AI 请求。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("用户词典") {
                if dictionaryEntries.isEmpty {
                    Text("暂无人工词条")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(dictionaryEntries) { entry in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(entry.surface)
                                Image(systemName: "arrow.right")
                                    .foregroundStyle(.secondary)
                                Text(entry.reading)
                                Spacer()
                                Text(entry.language.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            HStack(spacing: 8) {
                                if let artistScope = entry.artistScope, !artistScope.isEmpty {
                                    Text("歌手：\(artistScope)")
                                }
                                if let trackStableKey = entry.trackStableKey, !trackStableKey.isEmpty {
                                    Text("单曲范围")
                                }
                                Text("优先级 \(entry.priority)")
                                if !entry.notes.isEmpty {
                                    Text(entry.notes)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Button(entry.isArchived ? "恢复" : "归档") {
                                    settings.readingUserDictionary.upsert(
                                        ReadingDictionaryEntry(
                                            id: entry.id,
                                            surface: entry.surface,
                                            reading: entry.reading,
                                            language: entry.language,
                                            trackStableKey: entry.trackStableKey,
                                            artistScope: entry.artistScope,
                                            priority: entry.priority,
                                            isEnabled: entry.isEnabled,
                                            isArchived: !entry.isArchived,
                                            notes: entry.notes
                                        )
                                    )
                                    reloadDictionary()
                                }
                                .buttonStyle(.borderless)
                                Button("删除", role: .destructive) {
                                    settings.readingUserDictionary.remove(id: entry.id)
                                    reloadDictionary()
                                }
                                .buttonStyle(.borderless)
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 3)
                    }
                }
                HStack {
                    TextField("原词", text: $newSurface)
                    TextField("读音", text: $newReading)
                    Picker("语言", selection: $newLanguage) {
                        Text("日语").tag(ReadingLanguage.japanese)
                        Text("简中").tag(ReadingLanguage.simplifiedChinese)
                        Text("繁中").tag(ReadingLanguage.traditionalChinese)
                    }
                    .labelsHidden()
                    TextField("优先级", text: $newPriority)
                        .frame(width: 52)
                    Button("添加") {
                        let surface = newSurface.trimmingCharacters(in: .whitespacesAndNewlines)
                        let reading = newReading.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !surface.isEmpty, !reading.isEmpty else { return }
                        settings.readingUserDictionary.upsert(
                            ReadingDictionaryEntry(
                                surface: surface,
                                reading: reading,
                                language: newLanguage,
                                trackStableKey: newTrackScope.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : newTrackScope,
                                artistScope: newArtistScope.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : newArtistScope,
                                priority: Int(newPriority) ?? 0,
                                notes: newNotes
                            )
                        )
                        newSurface = ""
                        newReading = ""
                        newTrackScope = ""
                        newArtistScope = ""
                        newPriority = "0"
                        newNotes = ""
                        reloadDictionary()
                    }
                    .disabled(newSurface.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || newReading.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                HStack {
                    TextField("可选 Spotify stableKey", text: $newTrackScope)
                    TextField("可选歌手范围", text: $newArtistScope)
                    TextField("备注", text: $newNotes)
                }
                .font(.caption)
            }
        }
        .formStyle(.grouped)
        .onAppear { reloadDictionary() }
    }

    private func readingBinding<Value>(_ keyPath: WritableKeyPath<ReadingPreferences, Value>) -> Binding<Value> {
        Binding(
            get: { settings.readingPreferences[keyPath: keyPath] },
            set: { value in
                var next = settings.readingPreferences
                next[keyPath: keyPath] = value
                settings.readingPreferences = next
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

    private func reloadDictionary() {
        dictionaryEntries = settings.readingUserDictionary.load()
    }
}

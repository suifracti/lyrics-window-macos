# AI 整首歌词翻译 V1 实现计划

## 检查点

- [ ] 先添加合同测试并确认红色。
- [ ] 实现 migration v2、legacy translation_text 导入和幂等测试。
- [ ] 实现翻译模型、端点规范化、Prompt、严格响应解析和 Keychain。
- [ ] 实现 SQLite 翻译仓储：源指纹、事务写入、版本选择、锁定和删除。
- [ ] 实现共享 TranslationSessionController，接入 PlaybackState 和现有展示层。
- [ ] 将 AI 设置接入现有 Sidebar Settings，复用现有设置存储边界。
- [ ] 运行全量合同测试、正常签名构建和 codesign。
- [ ] 在用户设置页输入 Key 后完成真实翻译、重启恢复、锁定、切歌防串歌验收。
- [ ] 只在闭环通过后提交独立 commit。

## 预计修改文件

新增：

- `SpotifyLyrics/AI/AITranslationModels.swift`
- `SpotifyLyrics/AI/AITranslationConfiguration.swift`
- `SpotifyLyrics/AI/AITranslationKeychain.swift`
- `SpotifyLyrics/AI/OpenAICompatibleClient.swift`
- `SpotifyLyrics/AI/AITranslationPromptBuilder.swift`
- `SpotifyLyrics/AI/AITranslationResponseParser.swift`
- `SpotifyLyrics/AI/AITranslationService.swift`
- `SpotifyLyrics/Persistence/TranslationRepository.swift`
- `SpotifyLyrics/Services/TranslationSessionController.swift`
- `Tests/ai_translation_contract.swift`
- `Tests/ai_translation_contract.sh`

修改：

- `Persistence/DatabaseMigrator.swift`
- `Persistence/DatabaseModels.swift`
- `Persistence/LyricsPersistenceMapper.swift`
- `Persistence/LyricsRepository.swift`
- `Persistence/SQLiteLyricsRepository.swift`
- `Services/LyricsSessionController.swift`
- `Services/PlaybackState.swift`
- `Settings/AppSettingsStore.swift`
- `Views/Settings/SettingsRootView.swift`
- `project.pbxproj`

## 约束

不修改 Provider、排轴算法、主窗口视觉、编辑器、导入导出和 Spotify Desktop 播放控制。`DerivedData.bak.20260727220515/` 及已有审计报告保持未跟踪，不进入提交。

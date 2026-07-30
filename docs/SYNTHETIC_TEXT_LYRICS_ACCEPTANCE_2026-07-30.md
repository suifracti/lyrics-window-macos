# Synthetic Text Lyrics Acceptance — 2026-07-30

## 结论边界

本次验收**只验证导入和版本链路**，没有验证两首歌曲的真实歌词内容：

- 使用了用户提供的 **synthetic test lyrics** A/B。
- A 仅作为 TEST 文本关联 `Forever / VILLSHANA` 的 Spotify TrackIdentity。
- B 仅作为 TEST 文本关联 `あやふや / みさき` 的 Spotify TrackIdentity。
- 这些文本不是两首歌曲的真实歌词，也没有被描述为真实歌词。
- 用户未来需要自行导入 Forever 和「あやふや」的真实 TXT、剪贴板内容或其他合法来源。

本阶段没有从网页、Provider 或外部歌词站获取或复制真实歌词。

## 验收环境

- 工作目录：`/Users/apple/backup/sptifylyrics`
- 验收基线：`63b555d841fd7f4fe2c6d680d7e30a94d410d519`
- 运行 App：`/Users/apple/backup/sptifylyrics/DerivedData/Build/Products/Debug/SpotifyLyrics.app`
- 实际可执行文件：`/Users/apple/backup/sptifylyrics/DerivedData/Build/Products/Debug/SpotifyLyrics.app/Contents/MacOS/SpotifyLyrics`
- TEST fixture 目录：`/tmp/spotifylyrics-synthetic-e2e-20260730`

为避免污染正式数据库，真实 UI 验收期间先备份了正式 SQLite，然后让 App 使用临时的默认数据库文件；App 退出后恢复正式数据库并再次执行完整性检查。临时数据库和测试文件在验收结束后删除，正式数据库中没有 synthetic 行。

## 流程结果

### A：TXT / `manualImport`

1. 创建临时 TXT：UTF-8 BOM、CRLF 换行。
2. 关联 Spotify TrackIdentity：`spotify:track:2cLlZmf690vuBEyA4EMm3g`（Forever / VILLSHANA）。
3. 通过真实 App 的“导入 TXT”打开文件选择器。
4. 预览显示 `4` 行、编码 `utf8BOM`，没有静默删除或改写文本。
5. 确认后进入现有 LyricsEditor。
6. 编辑器显示独立 kana 和 romaji 层；原文保持独立。
7. 点击“保存并锁定”后创建新的 `manualImport` 版本。
8. SQLite 验证：4 行、4 行 kana、4 行 romaji、0 行时间戳、`is_synced=0`、`is_manually_edited=1`、`is_locked=1`。

### B：剪贴板 / `manualCreate`

1. 将 synthetic B 写入 macOS 剪贴板，不创建真实歌词文件。
2. 播放并识别 Spotify TrackIdentity：`spotify:track:4l6XKftR34zrUw0bTnwoVv`（あやふや / みさき）。
3. 在“暂无歌词”状态点击“粘贴歌词”。
4. 预览显示 `4` 行、编码 `plainText`。
5. 确认后进入现有 LyricsEditor，显示独立 kana 和 romaji。
6. 点击“保存并锁定”后创建新的 `manualCreate` 版本。
7. SQLite 验证：4 行、4 行 kana、4 行 romaji、0 行时间戳、`is_synced=0`、`is_manually_edited=1`、`is_locked=1`。

## 读音结果

两份 TEST 文本均通过现有 JapaneseReadingPipeline / JapaneseRomanizer：

- 原文未被改写。
- kana 和 romaji 分列保存。
- 4/4 行均生成读音层。
- 没有把读音或罗马音写回原文。
- 没有为纯文本伪造时间轴。

## AI 翻译链路

`Tests/synthetic_text_lyrics_e2e_contract.sh` 使用生产实现的以下链路和内存 HTTP 客户端完成了 TEST 验证：

`OpenAICompatibleTranslationService → OpenAICompatibleClient → AITranslationResponseParser → TranslationSessionController → SQLite translation repository`

验证内容：

- 整首上下文只发送一次请求。
- 输入/输出均为 4 个稳定 index。
- 空行规则、行数、index 集合和 source content hash 校验通过。
- 翻译版本可保存并锁定。
- 时间轴未被 AI 链路修改。
- 失败响应不会创建半成品版本。

这是**合成 HTTP 测试**，没有把 TEST 文本发送到真实外部 AI 服务，也没有使用用户 API Key。因此本报告不声称完成了真实外部 API 的网络验收；生产 AI 链路的合同和持久化行为已验证。

## 重启恢复

终止并重新启动同一 Debug App 后：

- 切回 Forever：主窗口从 SQLite 恢复 4 行 synthetic A，kana/romaji 一并显示，仍为纯文本无时间轴。
- 切回「あやふや」：主窗口从 SQLite 恢复 4 行 synthetic B，kana/romaji 一并显示，仍为纯文本无时间轴。
- 恢复过程没有改变 Spotify 播放位置。

## 切歌防串歌

在临时数据库中先移除 A 的 TEST 版本，重新打开 A 的 TXT 预览，然后将 Spotify 切到「あやふや」。预览状态变为：

> 当前 Spotify 已切歌，编辑会话仍绑定原歌曲

此时确认旧预览没有进入新的编辑会话，数据库中 Forever 版本数量保持为 `0`。随后恢复临时数据库快照，再完成 A/B 的最终保存验收。没有出现把 A 写入 B 的情况。

## 空白文件与编码合同

合同测试覆盖并通过：

- UTF-8
- UTF-8 BOM
- UTF-16（可识别 BOM）
- CRLF / LF / CR
- 纯文本剪贴板
- 空文件和全空白文件拒绝
- 空白行保留规则
- 原文件不被修改
- 空歌词不会创建 `LyricsVersion`

## SQLite 内容核验

临时 TEST 数据库在验收期间通过 `sqlite3` 核验：

- `PRAGMA integrity_check`：`ok`
- A：`manualImport` / 4 行 / 无时间戳 / locked
- B：`manualCreate` / 4 行 / 无时间戳 / locked
- 所有写入使用现有事务路径。

验收结束后：

- 正式数据库恢复自验收前备份。
- 正式数据库 `PRAGMA integrity_check`：`ok`
- 正式数据库中的 synthetic 原文行数：`0`
- 正式歌词版本数量恢复为验收前的 `59`。

## 构建与测试

本阶段已运行并通过：

- `Tests/text_lyrics_import_contract.sh`
- `Tests/manual_lyrics_creation_contract.sh`
- `Tests/synthetic_text_lyrics_e2e_contract.sh`
- `Tests/japanese_reading_contract.sh`
- `Tests/lrc_roundtrip_contract.sh`
- `Tests/sqlite_persistence_contract.sh`
- `Tests/sqlite_editing_contract.sh`
- `Tests/sqlite_session_contract.sh`
- `Tests/kana_display_mode_contract.sh`
- `Tests/lyrics_display_regression_contract.sh`
- `Tests/lyrics_editor_contract.sh`
- `git diff --check`

`synthetic_text_lyrics_e2e_contract.sh` 的输出明确为：`TEST fixtures only; no real song lyrics asserted`。

## 最终声明

本阶段可以认定为：

> **“synthetic TXT/剪贴板导入 → 预览 → manualImport/manualCreate → 读音 →（合成 HTTP）翻译链路 → 锁定 → SQLite → 重启恢复 → 切歌防串歌”验收通过。**

本阶段不能认定为：

> **Forever 或「あやふや」真实歌词内容已验证正确。**

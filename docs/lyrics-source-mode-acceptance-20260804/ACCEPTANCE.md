# 歌词来源双模式验收报告

**日期：** 2026-08-04  
**执行：** Grok（非 Codex）  
**状态：** PASS — 本轮关闭，不进入下一 Phase

## 工作目录 / 分支 / 基线

| 项 | 值 |
|---|---|
| 工作目录 | `/Users/apple/backup/sptifylyrics` |
| 分支 | `codex/phase-2-11a-lyrics-retrieval` |
| 基线 HEAD | `35d2b83cc4927f36bf683a1b0897bc6f52a9f1ad` |
| 稳定 ID A | `lyricsSourceMode.standardFree.v1`（默认） |
| 稳定 ID B | `lyricsSourceMode.experimentalFree.v1`（实验） |

## 产物路径

| 项 | 路径 |
|---|---|
| App（Debug） | `/Users/apple/backup/sptifylyrics/DerivedData/Build/Products/Debug/SpotifyLyrics.app` |
| 临时库（live） | 见 `temp-db-path-live.txt` |
| 正式库 | `~/Library/Application Support/SpotifyLyrics/SpotifyLyrics.sqlite3` |
| 正式库 SHA | `73a260676cc61dd8aa70b4afe6eab6be1dbcf83c3c7541138f0b10a300055a64`（前后一致） |
| E2E 日志 | `/tmp/spotifylyrics-e2e.log` → 本目录副本 |

## 实现摘要

1. **单一设置键** `lyrics.sourceMode`（UserDefaults），默认 `standardFree.v1`。
2. **Provider 能力分类**（local / openFree / experimentalFree / discoveryOnly / userContent）与模式门控，复用既有 `LyricsSearchManager` 链。
3. **设置 → 歌词来源**：单一切换（radio）+ 实验说明 + 稳定 ID + 恢复默认。
4. **当前歌曲面板**只读显示模式，无第二套开关。
5. **酷狗**：审计后不实现（`KUGOU_AUDIT.md`）。
6. **DEBUG 验收通道**（可选）：`SPOTIFYLYRICS_ACCEPTANCE_CONTROL_PATH` 文件驱动会话内 mode/retry；生产不设 env 则惰性。

## 验收矩阵

| # | 要求 | 结果 | 证据 |
|---|---|---|---|
| 1 | 新装/恢复默认 → 方案 A | PASS | `e2e-mode-a-default.log` / defaults 缺 key 回落；截图 `settings-lyrics-source-page-mode-a.png` |
| 2 | 方案 A 不调网易/QQ | PASS | `e2e-mode-a-default.log`、`e2e-live-mode-switch.log` P1：providers 仅 Local LRC,LRCLIB |
| 3 | 方案 B 允许网易/QQ | PASS | `e2e-mode-b-experimental-probe.log`、live P2：`DIAG NetEase/QQ` |
| 4 | 切回 A 实验源立即退出 | PASS | live P3：`MANAGER start ... ["Local LRC","LRCLIB"]` 且无 experimental DIAG |
| 5 | 已存歌词 A/B 可显示 | PASS | `e2e-saved-lyrics-mode-a.log` / `e2e-saved-lyrics-mode-b.log` persistence hit |
| 6 | 切换不改播放位置/歌曲 | PASS | live `posBefore==posAfter`；identity 不变 |
| 7 | 重启保留选择 | PASS | `e2e-mode-b-restart.log` |
| 8 | 无付费来源入口 | PASS | 合同测试拒绝 musixmatch/付费套餐；设置页仅免费/实验 |

## 会话内热切换（本轮补齐）

同一进程 PID，控制文件顺序：`B+RETRY` → `A+RETRY`：

1. 启动：`PlaybackState init providers=Local LRC,LRCLIB`
2. → B：`Lyrics providers for mode=...experimentalFree.v1: ...NetEase Experimental,QQ Music Experimental` + DIAG 探测
3. → A：`MANAGER start ... providers=["Local LRC", "LRCLIB"]`，后续 DIAG 无实验源
4. 位置：`posBefore` 与 `posAfter` 相同

完整日志：`e2e-live-mode-switch.log`

## 设置页截图

- 方案 A：`settings-lyrics-source-page-mode-a.png`  
  （标准免费选中，稳定 ID `standardFree.v1`）
- 方案 B：`settings-lyrics-source-page-mode-b.png`  
  （扩展实验选中，橙色实验条，稳定 ID `experimentalFree.v1`）

## 合同测试

```
bash Tests/lyrics_source_mode_contract.sh  → PASS
bash Tests/settings_contract.sh            → PASS
```

## Debug 构建

```
xcodebuild -project SpotifyLyrics.xcodeproj -scheme SpotifyLyrics \
  -configuration Debug -derivedDataPath DerivedData build
→ ** BUILD SUCCEEDED **
```

日志：`xcodebuild-debug-closeout.log` / `xcodebuild-debug.log`

## 修改文件（产品）

- `SpotifyLyrics/Settings/LyricsProviderConfiguration.swift` — 模式枚举、能力分类、门控
- `SpotifyLyrics/Settings/AppSettingsStore.swift` — 单一键持久化、恢复默认
- `SpotifyLyrics/Services/PlaybackState.swift` — 按模式重建 Provider；DEBUG 验收控制
- `SpotifyLyrics/Views/Settings/SettingsRootView.swift` — 设置页单一切换
- `SpotifyLyrics/Views/Components/CurrentSongOperationsView.swift` — 只读模式显示
- `Tests/lyrics_source_mode_contract.{sh,swift}` — 合同
- `Tests/settings_contract.sh` — 扩展断言
- `docs/lyrics-source-mode-acceptance-20260804/**` — 证据与本报告

## 明确不做

- 付费 API / Musixmatch / 酷狗实现  
- 抓取禁止网页  
- 第二套检索架构 / schema 变更  
- 主窗口视觉改动 / 自动排轴 / 下一 Phase  

## 收口状态

- 模式已恢复 **方案 A**（`lyricsSourceMode.standardFree.v1`）
- App 已退出
- 正式库 SHA 未变

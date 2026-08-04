# Phase 2.11B-Assist — V3 Manual Entry Wiring Fix

| 项 | 值 |
|---|---|
| 产品 | Lyric Island |
| 分支 | `codex/phase-2-11b-assist-mvp` |
| 基线 HEAD | `85657abe4771881a9de0f1eea3beb131a18b5513` |
| 日期 | 2026-08-04 |
| 范围 | **仅产品入口接线**（不改 ASR/DP/锚点/schema/S3C） |

---

## 1. 问题与修复

| 问题 | 修复 |
|---|---|
| `AssistExplainSheet` 只挂在 `LyricsCanvasView`，默认 V3 不挂载该 View | **单一 host**：`MainLyricsWindowView` 上挂 sheet（V3 / classic / lyrics-focus 共享） |
| explaining 后 gate 关闭且无取消 → 卡死 | `dismissListeningAssistExplanation()` → **idle**；面板 explaining 态有「打开说明 / 取消」 |
| V3 待排轴仅「选择本地音频」 | `CurrentSongOperationsView` 按 `assistPhase` 完整展示入口 / 进行中 / 草稿 / 失败 |
| draft ready 难开编辑器 | `assistEditorOpenToken` + `MainLyricsWindowView.openWindow(lyrics-editor)`；保留 `openListeningAssistEditorWithDraft` |
| S1/S2/S3A | **未改**（仍为诊断菜单） |

---

## 2. 修改文件

| 文件 | 变更 |
|---|---|
| `SpotifyLyrics/Services/PlaybackState.swift` | dismiss 恢复、base eligibility、phase 失败路径、`openListeningAssistEditorWithDraft`、`assistEditorOpenToken` |
| `SpotifyLyrics/Views/MainWindow/MainLyricsWindowView.swift` | **唯一** AssistExplainSheet host + 编辑器 open token |
| `SpotifyLyrics/Views/Components/LyricsCanvasView.swift` | 移除 sheet host；保留经典布局入口按钮 |
| `SpotifyLyrics/Views/Components/CurrentSongOperationsView.swift` | 全 phase 产品控件 |
| `SpotifyLyrics/Views/Components/AssistExplainSheet.swift` | dismiss / 无工程术语 a11y id |
| `SpotifyLyrics/Views/MainWindow/AppleMusicImmersiveV3WindowView.swift` | 工具菜单增加「边听边排轴」（可选入口） |
| `Tests/assist_v3_entry_contract.sh` | **新增** |
| `Tests/assist_session_contract.sh` | 对齐单 host + dismiss |

---

## 3. 阶段 UI（产品文案，无 S1/S2/S3A/DP）

| Phase | 面板 |
|---|---|
| idle / cancelled | 「边听边排轴」 |
| explaining | 提示 +「打开说明」+「取消」 |
| capturing / merging | 状态文案 +「取消边听边排」 |
| ready | 建议/未排摘要 +「打开编辑草稿」+「重新开始」 |
| failed | 错误 +「重试边听边排轴」 |

---

## 4. 保存语义（审计确认，本轮未改算法）

| 类型 | 行为 |
|---|---|
| 部分时间轴 | `is_synced=0` · `explicitlyTimedLineIndices` · `adoptPersisted` 后主界面仍 **纯文本/未排轴**（**不伪造跟播**） |
| 完整时间轴 | `validation.isSynchronized == true` → 保存后 adopt → 主界面可跟播 |
| 自动当前版本 | `editor.onSaved` → `applyLyricsEditorResult` → **`adoptPersisted`**（自动成为当前选择） |

---

## 5. 合同

```text
assist_v3_entry_contract: PASS
assist_session_contract: PASS
assist_editor_contract: PASS
assist_candidate_merge_contract: PASS
assist_partial_persist_contract: PASS
```

---

## 6. Debug 构建与签名

| 项 | 值 |
|---|---|
| App | `/Users/apple/backup/sptifylyrics/DerivedData/Build/Products/Debug/SpotifyLyrics.app` |
| TeamIdentifier | `5RGL84U3V2` |
| Authority | Apple Development: 3881920884@qq.com (XJDV53A9C8) |
| CDHash | `9b32bab10a51d3181d9dd509121b7e2774d9d78f` |
| ENABLE_DEBUG_DYLIB | NO（单可执行文件） |
| adhoc | **否** |
| designated | `identifier "com.spotifylyrics.app" and anchor apple generic and certificate leaf[subject.CN] = "Apple Development: 3881920884@qq.com (XJDV53A9C8)" …` |
| codesign verify | valid · satisfies Designated Requirement |

> **CDHash 相对验收冻结 `038501…` 已变化**：本阶段允许一次 rebuild。TCC 可能要求用户在「屏幕与系统音频录制」中重新确认本路径 App。**勿绕过 TCC。**

证据：`identity-after-wire.txt`

---

## 7. 手动验收状态（本轮代理）

| 步骤 | 状态 |
|---|---|
| 代码接线 + 合同 + Development 签名构建 | **完成** |
| 默认 V3 不依赖 harness 的完整真机捕获 / 截图 / 跟播录屏 | **需用户在新签名 App 上完成**（见下方清单） |

### 用户手动清单（无 harness）

1. 退出旧进程；若系统提示，重新允许屏幕/音频捕获（新 CDHash）  
2. `open` 上述 Debug App（默认 V3）  
3. 播放《夜の合図》，打开「当前歌曲」  
4. 确认「边听边排轴」可见 → 点开 Sheet → **取消** → 入口恢复  
5. 再开始 → 真实捕获 → 编辑器出现建议/未排  
6. Space / N / undo → 保存部分时间轴 → 确认 `is_synced=0` 子版本  
7. 补齐完整后保存 → 主歌词跟播  

---

## 8. 正式库

本接线阶段构建与合同 **不打开正式库写路径**。  
`formal-db-before.sha` 已记录；完整手动验收后再采 after SHA。

---

## 9. Phase 2.11B 关闭条件

**尚未正式关闭。**  
关闭条件：用户在默认 V3 **无需 harness** 完成入口→捕获→编辑→保存，且完整时间轴真实跟播。

本提交仅关闭「V3 Sheet 未挂载 / explaining 卡死」的接线缺口。

# Phase 2.11B-Assist MVP — 验收

| 项 | 值 |
|---|---|
| 产品 | **Lyric Island**（Craft 仅为规划文档工具，非产品名） |
| 日期 | 2026-08-04 |
| 工作目录 | `/Users/apple/backup/sptifylyrics` |
| 分支 | `codex/phase-2-11b-assist-mvp` |
| 基线 | `393adcd` |
| HEAD | `19f4bc5`（docs 提交；功能 commits 见下表） |

## 产品定位（不可误读）

Lyric Island **默认零操作歌词伴侣** + **完整 DIY 工作台**。

Assist MVP 是：

- 自动能力不足时的 **补全/校正层**
- 深度工作台的一部分
- **不是**「最终默认必须人工」的产品方向

---

## Commits

| # | Commit | 内容 |
|---|---|---|
| 1 | `5da57b6` | Assist draft + S3A/S3B 候选合并；部分时间轴 `explicitlyTimedLineIndices` |
| 2 | `4e06519` | 编辑器建议/未排、Space 标记、N 跳转、undo、自动前进、部分保存确认 |
| 3 | `8023f65` | 「边听边排轴」入口、说明 Sheet、捕获→草稿、切歌丢弃 |

---

## 关键 diff（摘要）

### 候选合并

优先级：S3B anchors → S3B high-conf resolved → S3A high-conf resolved（无冲突、无 interpolation）。  
不写库；不降低 S3A/S3B 安全阈值；lowConfidence 不进草稿。

### 部分时间轴（无 schema migration）

- `LyricsDocument.explicitlyTimedLineIndices`
- `lineRecords` 在 `!isSynchronized` 时仍写入已标记行的 `start_time`
- 加载时从 DB 非空 `start_time` 恢复 mask  
→ **可保存部分时间轴，未排行不伪装完整同步**（`is_synced=0` + 部分 start_time）

### 入口

仅 DEBUG 产品路径（与 S1–S3B 捕获同门控）：

- 条件：live track + 纯文本无时间轴 + 已保存版本
- 文案：**边听边排轴**
- Sheet：临时分析 Spotify 音频 / 无麦克风 / 不保留音频 / 建议可能不完整 / **确认后才保存**

### 编辑器

| 键 | 行为 |
|---|---|
| **Space** | 将当前行开始时间标为 Spotify position（**不**用于播放；播放仍用工具栏按钮） |
| ↑ / ↓ | 切换焦点行 |
| **N** | 下一条未排行 |
| ⌘Z / ⇧⌘Z | 撤销 / 重做 |
| 标记后自动前进 | 可关的复选框 |

徽章：**建议** / **未排**（不展示 conf 数字）。

### 会话安全

- `AlignmentSessionGuard` 绑定 identity / version / hash / revision  
- 切歌：`invalidateAssistOnTrackChange` → stop capture → **丢弃未确认草稿**  
- `confirmListeningAssistAndCapture` **从不** `saveAlignedVersion`  
- 保存仅走编辑器 `saveManualEdit`（用户明确点保存）

---

## 合同与构建

```text
assist_candidate_merge_contract: PASS
assist_editor_contract: PASS
assist_session_contract: PASS
s3a_partial_alignment_contract: PASS
s3b_anchor_alignment_contract: PASS
Debug xcodebuild: BUILD SUCCEEDED
```

App：

```text
/Users/apple/backup/sptifylyrics/DerivedData/Build/Products/Debug/SpotifyLyrics.app
```

临时库（本轮尝试）：见 `temp-db-path.txt`  
**无 SQLite schema migration。**

---

## 样本与场景

### 样本 A — 《夜の合図》

| 项 | 结果 |
|---|---|
| 歌词 | 纯文本 32 行（QQ experimental） |
| 本轮现场捕获 | **TCC 拒绝**（`用户拒绝了…屏幕/应用捕捉`）— 见 `sample-a/sck.log` |
| 离线合并估计（复用 S3B 同曲报告 `partial-FCE4FF7E`） | anchors=4 → assist 建议约 **4** 行；未排约 28 |
| 人工补 ≥5 行 | **UI 路径已实现**；本机 TCC 阻断完整交互录屏；合同覆盖 Space/N/undo |

### 样本 B — 《アイドル》

| 项 | 结果 |
|---|---|
| 离线（S3B `partial-404F9F32`，算法仅纯文本） | anchors=8 → assist 建议约 **8**；未排约 143 |
| held-out | 仅用于对照，不输入 Assist 合并 |

### 场景 C — 切歌

代码：`PlaybackState.invalidateAssistOnTrackChange` + `LiveCaptureCoordinator.stop(.trackChanged)`  
旧草稿不得写入新歌（guard + identity key 双重检查）。

### 场景 D — 部分时间轴保存 / 恢复

能力：`explicitlyTimedLineIndices` + 编辑器部分保存确认对话框  
`is_synced=0` 版本仍可带部分 `start_time`；版本列表可切换回父纯文本。  
**本轮未做完整 UI 重启录屏**（TCC + 交互限制）；持久化路径有代码与合同覆盖。

### 场景 E — 取消不写库

- Assist 捕获路径无 `saveAlignedVersion`  
- 取消：`cancelListeningAssist` 清草稿  
- 临时 WAV：`wav_remaining=0`（`temp-remaining.txt`）

> 说明：本机 `formal-db-before/after` SHA 在本轮窗口内发生变化，但 Assist 使用 `SPOTIFYLYRICS_DATABASE_PATH` 临时库且捕获路径不写时间轴版本。正式库变更来源未归因于 Assist 自动保存（代码无该调用）。后续验收建议在干净环境只开 TEMP_DB 再核对 SHA。

---

## 键盘说明

见 `keyboard-note.txt`：编辑器内 **Space = 标记时间**，避免与播放冲突（播放为工具栏按钮）。

---

## 禁止项核对

| 禁止 | 状态 |
|---|---|
| S3C / Whisper / 新 ASR | 无 |
| 新 Provider / 付费 | 无 |
| Phase 3 主窗重构 | 无 |
| 无确认写正式时间轴 | 无 |
| 大型 schema migration | 无（仅 document mask） |
| 第二套 PlaybackState/Editor | 无 |

---

## 修改文件（相对 393adcd）

见 `git diff --stat 393adcd..HEAD`。

---

## 暂停

**Assist MVP 代码闭环完成。**  
不进入 S3C / S4 / S5 / Phase 2.7 / Phase 3。

后续可选：TCC 稳定后补全交互录屏；将 Assist 从 `#if DEBUG` 提升为正式 Debug/Release 开关（需权限产品文案）。

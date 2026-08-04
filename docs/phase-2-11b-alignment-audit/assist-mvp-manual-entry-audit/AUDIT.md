# Phase 2.11B-Assist MVP — 手动产品入口审计（只读）

| 项 | 值 |
|---|---|
| 产品 | **Lyric Island** |
| 日期 | 2026-08-04 |
| 项目 | `/Users/apple/backup/sptifylyrics` |
| 分支 | `codex/phase-2-11b-assist-mvp` |
| App | `/Users/apple/backup/sptifylyrics/DerivedData/Build/Products/Debug/SpotifyLyrics.app` |
| CDHash（当前签名产物） | `0385018210a523b242e7d71c179113d91b5f0b9a` |
| 本轮约束 | **只读** · 不改代码 · 不 rebuild · 不重签 · 不改 bundle · 不写正式库 · 不进 S3C/S4/S5/2.7/3 |
| CDHash 8c1a… vs 038501… | **已关闭**（中间 partial 持久化修复曾重编重签；本审计不再调查） |

---

## 0. 用户现场事实（审计输入）

| 观察 | 含义 |
|---|---|
| 当前曲《夜の合図 / Kawasaki.Rio》· Spotify 播放中 | live track 存在 |
| 状态「纯文本 · 未排轴」 | `liveLyricsAreSynchronized == false` · 主视口 plain 模式 |
| 歌词版本已加载 | Session 已 apply 正文 |
| 右侧「待排轴」仅「选择本地音频」 | 本地音频排轴入口可见；**未见「边听边排轴」** |
| 顶部调试菜单 S1/S2/S3A 可点 | Debug CommandMenu 已编译进 Debug App |
| 点调试菜单后歌词不滚、不变时间轴版本 | **符合调试菜单设计**（见 §3） |

本机只读旁证（`/tmp/spotifylyrics-e2e.log`，进程运行中）：

```text
Playback trackChange … 夜の合図 …
SESSION persistence hit … source=qqExperimental … lines=32 sync=false
SESSION apply alignmentQueued source=qqExperimental lines=32 …
SESSION persistence save … disposition=duplicate …
```

UserDefaults：`mainWindowLayoutStyle = appleMusicImmersiveV3`（**默认主窗口**）。

---

## 1. 「边听边排轴」入口实现位置

### 1.1 代码地图

| # | 角色 | 文件 | 符号 |
|---|---|---|---|
| 1 | **右侧当前歌曲面板按钮** | `SpotifyLyrics/Views/Components/CurrentSongOperationsView.swift` | `alignmentSection` · `Button("边听边排轴")` |
| 2 | **主歌词画布状态区按钮**（仅走 `LyricsCanvasView` 时） | `SpotifyLyrics/Views/Components/LyricsCanvasView.swift` | `systemStateContent` · `.alignmentQueued` 分支 |
| 3 | 说明 Sheet UI | `SpotifyLyrics/Views/Components/AssistExplainSheet.swift` | `struct AssistExplainSheet` |
| 4 | Sheet 挂载点（**唯一**） | `LyricsCanvasView.swift` | `.sheet(isPresented: isAssistExplainSheetPresented)` |
| 5 | Gate + 动作 | `SpotifyLyrics/Services/PlaybackState.swift` | `canStartListeningAssist` · `presentListeningAssistExplanation()` · `confirmListeningAssistAndCapture(seconds:)` · `cancelListeningAssist()` |
| 6 | 捕获 → 部分对齐 | `LiveCaptureCoordinator.start(…, runPartialAlignment: true)` | S2 + S3A/S3B |
| 7 | 合并草稿 | `AssistedCandidateMerger.merge` | → `AssistedAlignmentDraft` |
| 8 | 编辑器应用建议 | `LyricsEditorSessionController.applyAssistedDraft` | DEBUG |
| 9 | 验收 harness（非产品 UI） | `PlaybackState.pollAcceptanceControlFile` | `assist_start` → **直接** `confirmListeningAssistAndCapture`（**跳过 Sheet**） |

冻结二进制中可检出：`边听边排轴`（count=6）、`AssistExplainSheet`、`canStartListeningAssist`、`confirmListeningAssistAndCapture` 等符号 → **Debug 产物已编译入口，非仅文档声明**。

### 1.2 View 名称与 Action

| 项 | 值 |
|---|---|
| View | `CurrentSongOperationsView`（用户截图右侧面板） |
| 次要 View | `LyricsCanvasView`（**V3 默认布局不挂载**） |
| Sheet View | `AssistExplainSheet` |
| 点击入口 | `state.presentListeningAssistExplanation()` |
| Sheet「开始」 | `state.confirmListeningAssistAndCapture(seconds: 55)` |
| Sheet「取消」 | `state.cancelListeningAssist()` |

### 1.3 完整显示条件（按钮）

按钮外包两层：

```text
#if DEBUG
  liveLyricsState == .alignmentQueued   // 待排轴区块才渲染
  && state.canStartListeningAssist
#endif
```

`canStartListeningAssist`（`PlaybackState`，**整块在 `#if DEBUG` 内**）逐项：

| # | 条件 | 依赖 |
|---|---|---|
| 1 | `hasLiveTrack` | Spotify 当前曲 |
| 2 | `!isMockPreviewMode` | 非 mock |
| 3 | `plainDocument ?? document` 非空 | Session 有歌词正文 |
| 4 | `!plain.isSynchronized` | **纯文本 / 未完整同步** |
| 5 | 至少一行非空原文 | |
| 6 | `activeLyricsVersionID != nil` | **已持久化版本 ID** |
| 7 | `currentTrackIdentity != nil` | |
| 8 | `assistPhase ∈ {idle, failed, cancelled, ready}` | **不含** `explaining` / `capturing` / `merging` |

### 1.4 是否 DEBUG / 环境 / harness

| 依赖 | 结论 |
|---|---|
| `#if DEBUG` | **是** — 按钮、Sheet、Assist API、`applyAssistedDraft` 均 DEBUG |
| 环境变量 | **产品入口不需要**；仅 S2/S3A **env 自动启动**（`SPOTIFYLYRICS_SCK_S2/S3A`）与 harness 文件路径 |
| launch argument | 否（与 Assist 无关） |
| Acceptance harness | **可选旁路**：`SPOTIFYLYRICS_ACCEPTANCE_CONTROL_PATH` + `assist_start` **直接** `confirmListeningAssistAndCapture`，**不经 Sheet、不经按钮** |
| UserDefaults | 入口本身不读；但 **`mainWindowLayoutStyle`** 决定默认是否挂 `LyricsCanvasView` |
| 数据库状态 | 需要 `activeLyricsVersionID`（已保存版本） |
| 歌词来源 | 任意纯文本源即可（现场为 `qqExperimental`） |
| 是否只存在于测试代码 | **否** — 在产品 View / PlaybackState 中；但是 **DEBUG 门控的产品路径**，不是 Release |

### 1.5 当前截图状态代入（夜の合図）

| 量 | 只读推断值 | 依据 |
|---|---|---|
| TrackIdentity | **有效** | e2e `spotify-id:0662h3g9…\|metadata:夜の合図\|…` |
| live track | **是** | Spotify 播放 + `hasLiveTrack` 路径日志 |
| 歌词版本已持久化 | **是** | `persistence hit` + `save … duplicate`；`activeLyricsVersionID` 在 hit 路径赋值 |
| 当前版本 ID | **有**（运行时 UUID；正式库 RO 可见 qqExperimental 版本如 `CE20040A` / `CCFCC425` 等，**未必等于当前进程 ID**） | e2e + formal DB RO |
| 来源 | **qqExperimental** | e2e |
| `isSynchronized` | **false** | `sync=false` · UI「纯文本 · 未排轴」 |
| `explicitlyTimedLineIndices` | 纯文本父版 **空/无**（timed=0） | formal RO timed=0/32 |
| 是否纯文本版本 | **是** · `alignmentQueued` | e2e `SESSION apply alignmentQueued` |
| 父/当前选择 | 当前为 **qqExperimental 纯文本**；无 Assist 子版（除非另存） | formal RO |
| ScreenCaptureKit | 本机此前 Development 签名下 STREAM 成功；**入口 gate 不检查 TCC** | 历史证据 |
| Assist session | 冷启动后默认 **`idle`** | 代码默认值；重启后重置 |
| **逻辑上 `canStartListeningAssist`** | 在 `assistPhase==idle` 时 **应为 true** | 上表 1–8 |

**为何用户仍可能看不到按钮 / 走不通？** 不只 gate 表达式，还有 **布局与 Sheet 挂载断点**（§1.6）。

### 1.6 默认布局下的真实断点（关键）

| 事实 | 证据 |
|---|---|
| 默认主窗口 | `MainWindowLayoutStyle.appleMusicImmersiveV3`（UserDefaults 与 AppSettings 默认一致） |
| V3 歌词列 | `AppleMusicImmersiveV3LyricsViewport` — **不**使用 `LyricsCanvasView` |
| V3 工具栏「当前歌曲」 | `CurrentSongOperationsView` — **有** DEBUG「边听边排轴」 |
| V3 工具栏 alignment 菜单 | `alignmentMenuContent` **仅**「自动排轴」（本地文件）— **无**「边听边排轴」 |
| **Explain Sheet 唯一挂载** | `LyricsCanvasView` 的 `.sheet` |
| V3 是否挂载 `LyricsCanvasView` | **否**（仅 legacy / `LyricsViewport` 路径） |

后果链：

1. 用户在 V3「当前歌曲」点「边听边排轴」（若可见）→ `presentListeningAssistExplanation()`  
2. `assistPhase = .explaining` · `isAssistExplainSheetPresented = true`  
3. **无宿主 View 展示 Sheet**（`LyricsCanvasView` 不在树中）  
4. 用户看不到说明 /「开始」  
5. `canStartListeningAssist` 因 **phase=explaining** 变为 **false** → 按钮消失  
6. 「取消」按钮只在 `capturing|merging` 显示 → **explaining 无取消 UI** → 易卡死到重启  
7. 验收 harness 直接 `confirmListeningAssistAndCapture` → **绕过 1–6** → 故 harness 真实验收能过，**不等于** V3 手动入口可达  

**入口 gate 最终为 false 的常见现场原因（按优先级）：**

| 优先级 | 原因 | 本现场 |
|---|---|---|
| A | **已进入 `explaining` 且 Sheet 未弹出** | 若曾点过入口 → **最可能** |
| B | `activeLyricsVersionID == nil`（未保存完） | 当前 e2e **否** |
| C | 已是同步歌词 | 当前 **否**（纯文本） |
| D | 非 DEBUG / 旧 ad-hoc 包 | 当前 Debug `038501…` **否** |
| E | 看错表面（主歌词区 / 调试菜单） | **是** — 主 V3 歌词区本无此按钮 |

---

## 2. 调试菜单实际作用

源：`SpotifyLyrics/Main.swift` · `CommandMenu("排轴捕获 Spike（调试）")` · **`#if DEBUG`**

### 2.1 S1「开始 Spotify 音频 Spike (S1)」

| 问题 | 答案 |
|---|---|
| 调用 | `SpotifyScreenCaptureAudioSpike.shared.start(autoStopAfter: 25)` |
| 只捕获 PCM？ | **是**（策略日志：`no-asr no-align`；不写 SQLite） |
| 只日志/诊断？ | **是**（`/tmp/spotifylyrics-sck-spike.log`） |
| 生成歌词时间建议？ | **否** |
| 创建 `AssistedAlignmentDraft`？ | **否** |
| 修改当前歌词版本？ | **否** |

### 2.2 S2「开始 Live Capture (S2)」

| 问题 | 答案 |
|---|---|
| 调用 | `LiveCaptureCoordinator.shared.start(autoStopAfter: 90, runPartialAlignment: **false**)` |
| 只建 Session/Segment？ | **是**（`CapturedAudioSession` / `CapturedAudioSegment`；可选临时 WAV） |
| 自动 Speech/DP？ | **否**（`runPartialAlignment: false`） |
| 修改当前歌词投影？ | **否** |

### 2.3 S3A「开始 Partial 对齐 (S3A)」

| 问题 | 答案 |
|---|---|
| 调用 | `LiveCaptureCoordinator.start(…, runPartialAlignment: **true**)` |
| 只生成 Partial 报告？ | **基本是** → `lastPartialReport` + s3a JSON/MD 报告文件 |
| 经过 `AssistedCandidateMerger`？ | **否**（菜单路径**不**调用 Merger） |
| 进入编辑器草稿？ | **否**（不 `applyAssistedDraft` / 不 `prepareLyricsEditor`） |
| 保存版本？ | **否** |
| 为何歌词不滚动？ | 未改 `isSynchronized`、未 adopt 时间轴版本；主视口仍 plain · **本来就不会同步滚动** |

### 2.4 调试菜单是否「应该」让歌词自动同步？

**不应该。**  
S1–S3A 菜单是 **捕获/算法探针**，有意与产品「边听边排轴 → 编辑器草稿 → 用户确认保存」解耦。  
用户点调试菜单后「歌词不滚、版本不变」**是预期行为**，不是 Assist 主路径故障。

完整 Assist 产品路径在 `confirmListeningAssistAndCapture` 内：

`LiveCapture(runPartial: true)` → `lastPartialReport` → **`AssistedCandidateMerger`** → **`assistDraft`** → **`applyAssistedDraft`** → 打开编辑器。

---

## 3. 普通手动流程逐步可达性

目标链：

纯文本未排轴 → 点「边听边排轴」 → 说明 Sheet → 捕获 → S3A/S3B → Merger → Draft → 编辑器「建议/未排」 → Space / N → 保存部分子版本 → 当前歌曲切到该版本 → 已排行随播放滚动

| 步骤 | 判定 | 说明 |
|---|---|---|
| 纯文本未排轴显示 | **已实现且普通 UI 可达** | `alignmentQueued` + V3「纯文本 · 未排轴」 |
| 点击「边听边排轴」 | **已实现但被错误/过窄接线** | 仅 DEBUG；V3 仅当前歌曲面板；主歌词区与 V3 菜单 **无** 入口 |
| 说明 Sheet | **已实现但默认布局下未接通** | Sheet **只**挂在 `LyricsCanvasView`；**V3 默认不挂该 View** |
| 开始捕获 | **已实现；普通 UI 依赖 Sheet「开始」**；**harness 可直达** | `confirmListeningAssistAndCapture` |
| S3A/S3B | **已实现** | `runPartialAlignment: true` |
| AssistedCandidateMerger | **已实现** | 仅 Assist 路径，非 S3A 菜单 |
| AssistedAlignmentDraft | **已实现** | `assistDraft` + 日志 `ASSIST draft ready` |
| 编辑器建议/未排 | **已实现（DEBUG）** | `applyAssistedDraft` + 徽章 |
| Space 标记 | **已实现** | `LyricsEditorWindowView` `.onKeyPress(.space)` |
| N 下一未排 | **已实现** | `.onKeyPress` `nN` |
| 保存部分时间轴子版本 | **已实现** | `saveManualEdit` + partial 确认；`is_synced=0` + 部分 `start_time` |
| 当前歌曲切换到该版本 | **已实现** | `editor.onSaved` → `applyLyricsEditorResult` → **`lyricsSession.adoptPersisted`** |
| 已排行随播放滚动 | **需全量同步才生效** | 主视口 `liveLyricsAreSynchronized` 才高亮/滚；**部分时间轴仍 `isSynchronized=false` → 保持 plain，不自动滚**（产品有意，非 harness 独有） |

补充：

| 问题 | 答案 |
|---|---|
| 部分时间轴是否只在已标记行有时间？ | **是** — `explicitlyTimedLineIndices` / 非空 `start_time` |
| 未排行是否自动滚？ | **否** — plain 模式不跟播 |
| 保存后要不要手动选子版本？ | **通常不用** — `adoptPersisted` 自动切当前 Session |
| 当前歌词是否自动切新版本？ | **会**（Session 投影更新）；但若仍部分排轴，**状态仍可能显示「纯文本 · 未排轴」** 且不跟播 |

---

## 4. 最终结论（四选一）

### **C. Assist 只在验收 harness 中可达，普通入口尚未真正接通**

（更精确表述：**普通入口代码存在于 DEBUG UI，但在默认 Apple Music Immersive V3 布局下端到端未接通；完整闭环当前实质依赖 harness 直调 `confirmListeningAssistAndCapture`。**）

### 直接原因

1. **默认布局 V3 不挂载 `LyricsCanvasView`，而 Explain Sheet 只挂在该 View 上** → 手动「边听边排轴」无法完成「说明 → 开始」。  
2. **整条 Assist 产品 UI/API 包在 `#if DEBUG`** → 非 Release 产品入口。  
3. **用户操作的 S1/S2/S3A 调试菜单本来就不进 Merger/编辑器/保存** → 无法替代产品入口。  
4. （次要）进入 `explaining` 后按钮 gate 关闭且缺少取消 UI，易加剧「入口消失」观感。

### 最小缺口

| 优先级 | 缺口 | 建议方向（**本轮不实施**） |
|---|---|---|
| P0 | Sheet 宿主缺失 | 在 `AppleMusicImmersiveV3WindowView` 或 `CurrentSongOperationsView` 挂载同一 `AssistExplainSheet` |
| P0 | V3 主路径入口过窄 | 在 V3 `alignmentMenuContent` / 待排轴区保证可见入口；explaining 提供取消 |
| P1 | 入口仅 DEBUG | 若要「正式产品入口」需非 DEBUG 暴露（产品决策，超出本审计） |
| P2 | 部分时间轴不跟播 | 文档化预期；若产品要「已排行跟播」需另定投影策略 |

### 是否功能 bug

| 项 | 判定 |
|---|---|
| 调试菜单不改歌词 | **不是 bug**（设计如此） |
| V3 下 Sheet 未挂载 / explaining 卡死 | **是接线缺陷（功能 bug）** |
| 仅 DEBUG | **阶段门控**（Assist MVP 文档亦写 DEBUG）；相对「普通产品入口」则是 **未接通** |

### 是否影响 Phase 2.11B「真实验收完成」表述

| 层面 | 影响 |
|---|---|
| **捕获 → Merger → 草稿 → 部分保存 → 重启 · 正式库 SHA · 切歌隔离**（harness 真机） | **仍成立**；不因本审计撤销 |
| **「用户可从普通 UI 完成边听边排轴」** | **应降级 / 加限定**：默认 V3 手动入口 **未真正接通**；验收走的是 **DEBUG harness 直调** |
| 建议表述修正 | 「Assist MVP **算法与持久化链路**真实验收完成；**默认主窗口手动产品入口**仍待接线审计修复后再宣称 UI 可达」 |

### 最小修复范围建议（不实施）

1. **仅 UI 接线（小）**：V3 挂 Sheet + explaining 可取消 + 待排轴区稳定显示按钮。  
2. **不改** 捕获/S3A/S3B/Merger/持久化契约。  
3. **不 rebuild 论证** 本审计结论；修复后再做 **手动 UI 冒烟**（可仍用同一 Development 签名策略）。

---

## 5. 结论对照表

| 选项 | 是否选取 | 理由 |
|---|---|---|
| A 普通 UI 可达，用户只点错调试菜单 | 否 | 调试菜单确实点错；但 **即便点对入口，V3 下 Sheet 仍断** |
| B 普通 UI 已实现但被错误门控 | 部分属实 | DEBUG + explaining gate 有问题，但 **根因是未接通** 更准确 |
| **C harness 可达、普通入口未真正接通** | **是** | 与默认布局 + Sheet 宿主 + harness 旁路事实一致 |
| D 入口在、保存后投影未接通 | 否作主结论 | `adoptPersisted` 已接；部分轴不跟播是 **同步门闩设计**，非「未 adopt」 |

---

## 6. 证据索引（只读）

| 证据 | 路径 / 命令 |
|---|---|
| 入口按钮 | `CurrentSongOperationsView.swift` ~478–484 |
| Canvas 入口 + Sheet | `LyricsCanvasView.swift` ~28–39, 51–77 |
| Sheet 本体 | `AssistExplainSheet.swift`（全文 `#if DEBUG`） |
| Gate / 捕获 / 合并 | `PlaybackState.swift` ~1045–1226 |
| V3 无 Assist 菜单 | `AppleMusicImmersiveV3WindowView.swift` `alignmentMenuContent` ~455–460 |
| V3 默认布局 | `AppSettingsStore` default `appleMusicImmersiveV3`；UserDefaults 现场值 |
| 调试菜单 | `Main.swift` ~148–167 |
| S1 无对齐 | `SpotifyScreenCaptureAudioSpike` policy `no-asr no-align` |
| S2/S3A 菜单 partial 开关 | `Main.swift` `runPartialAlignment: false/true` |
| 保存 adopt | `PlaybackState.applyLyricsEditorResult` → `adoptPersisted` |
| 跟播门闩 | V3 `liveLyricsAreSynchronized ? .synchronized : .plainText` |
| 冻结 CDHash | `0385018210a523b242e7d71c179113d91b5f0b9a`（本轮未改 App） |

---

**本轮暂停。不实施修复。**

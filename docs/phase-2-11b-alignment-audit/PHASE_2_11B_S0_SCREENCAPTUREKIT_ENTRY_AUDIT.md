# Phase 2.11B-S0 — ScreenCaptureKit 自动排轴入口审计

| 项 | 值 |
|---|---|
| 日期 | 2026-08-04 |
| 工作目录 | `/Users/apple/backup/sptifylyrics` |
| 基线 HEAD | `c8e4fce` |
| 范围 | **只读审计 + 分阶段计划**；不改 Swift、不构建、不 commit、不打开正式库 |
| 前序 | 2.11A 双模式完成 · 2.11B 行级排轴引擎审计完成 |
| 本轮主题 | 用 **ScreenCaptureKit 仅捕获 Spotify App 音频**，接入既有排轴链路 |

---

## 0. 执行摘要

| 判断 | 结论 |
|---|---|
| 排轴引擎是否够用 | **够**；缺的是「自动拿到可对齐音频」，不是算法 |
| ScreenCaptureKit 音频 API | **deployment target 14.0 可用**（音频捕获自 macOS 13） |
| 仅音频、不存画面 | **技术可行**（`capturesAudio` + 只注册 `.audio` output） |
| 接入现有 16 kHz mono 管线 | **可行**；需 **CMSampleBuffer → PCM 适配层** |
| 现有 Speech 路径 | **仅支持文件 URL**；最小适配 = 写临时 WAV **或** 扩展流式 `SFSpeechAudioBufferRecognitionRequest` |
| 能否做默认主入口 | **不适合默认自动开启**；适合作为 **用户主动「边听边排轴」实验入口** |
| 本地文件排轴 | **必须保留为稳定回退** |
| 数据库 migration | **S0–S4 不需要**；时间轴仍走子版本 + provenance |
| 进入 S1 Spike | **具备条件**（本地实验）；正式发布另需条款/审核核验 |
| 法律措辞 | **技术可行 · 本地实验可行 · 正式发布需进一步条款／审核核验**（不宣称完全合法） |

---

## 1. 现有代码基线（与本入口的关系）

### 1.1 可复用（不要重写）

| 组件 | 路径 | 对 SCK 入口的作用 |
|---|---|---|
| 本地文件 → 16k mono PCM | `AudioPCMConverter` | 捕获侧应对齐到 **同一 PCM 约定**；文件路径仍可复用 `prepare`/cleanup 模式 |
| Speech 带时间片段 | `SpeechTimedTranscriptProvider` | 今日只吃 `pcmURL`；SCK 最终产物需变成同类 transcript |
| 行级 DP | `LineForcedAligner` | 直接复用；**必须改调用方允许 partial** |
| 防串歌 | `AlignmentSessionGuard` + `alignmentTask?.cancel` on trackChange | 捕获会话、ASR、对齐结果全部绑定同一 guard |
| 会话状态 | `LyricsSessionController` alignmentRunning/Preview/confirm | 可扩展状态文案；不新建 Session |
| 持久化 | `saveAlignedVersion` + `AlignmentProvenanceStore` | 只存时间轴与 provenance；**不存音频** |
| 人工修正 | 编辑器时间字段 / 标到当前播放 | 补 unresolved 行 |
| 播放位置 | `PlaybackState.currentTime` / `isPlaying` / trackChange | 与 host 时间戳对齐的锚点 |

### 1.2 当前产品缺口（本入口要解决的体验问题）

- 用户必须 **手动选完整本地文件** 才能排轴。
- `SpeechForcedAlignmentService` 在 `!result.isComplete` 时 **整次失败**（`insufficientEvidence`）——与「边听边 partial」冲突，**必须改策略（S3）**。
- 默认 locale **硬编码 `ja-JP`**。
- Info.plist 仅有 Apple Events + Speech；**无屏幕录制相关说明**。
- Entitlements 仅 `com.apple.security.automation.apple-events`；**未启用 App Sandbox**（Debug 本地分发现状）。

### 1.3 已确认的工程约束

| 项 | 值 |
|---|---|
| `MACOSX_DEPLOYMENT_TARGET` | **14.0** |
| `LSMinimumSystemVersion` | **14.0** |
| Speech 用途文案 | 仍写「本地音频 / 不读 Spotify 受保护音频」——SCK 入口若上线需 **改写说明**（实现阶段） |
| 正式库 | 本轮与后续 Spike **只允许临时库** |

---

## 2. 技术问题逐条回答

### 2.1 Deployment target 是否支持所需 ScreenCaptureKit 音频 API

**是。**

| API | 可用性 | 与 14.0 |
|---|---|---|
| `SCStreamConfiguration.capturesAudio` | macOS 13.0+ | ✅ |
| `sampleRate` / `channelCount` | macOS 13.0+ | ✅ |
| `SCStreamOutputType.audio` | macOS 13.0+ | ✅ |
| `SCShareableContent` / `SCRunningApplication` | 更早 | ✅ |
| `SCStreamOutputType.microphone` | macOS 15.0+ | **不使用**（产品禁止麦克风） |
| `SCContentSharingPicker` 等 | 更高版本增强 | S1 实测是否必须走系统选择器 |

**结论：** 在 14.0 目标上 **可以编译并调用「仅音频」捕获 API**；是否在 **当前运行 macOS 版本** 上稳定、是否强制用户手选 Spotify，由 **S1 Spike** 验证。

### 2.2 如何从 `SCShareableContent` 识别 Spotify 主进程与辅助进程

**设计（S1 验证）：**

1. `SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true)`（或当前 SDK 推荐异步 API）。
2. 在 `applications` 中筛选：
   - **主目标：** `bundleIdentifier == "com.spotify.client"`
   - **辅助：** 同 bundle 前缀 / 名称含 `Spotify` 的其它 `SCRunningApplication`（Helper、Web Helper 等）——**S1 打印完整列表**，不要假设只有一个 PID。
3. 过滤器优先：
   - **应用级：** display + `includingApplications: [spotifyApps…]`（捕获该 App 窗口相关音频路径以系统实现为准）
   - 或 **窗口级：** 仅 Spotify 主窗口（若应用级漏音则对比）
4. **失败态：** Spotify 未运行 / 无权限 / 列表为空 → 明确 UI，不静默退化为全显示器捕获。

**禁止：** 默认捕获「整个显示器」或「所有 App」作为产品行为。

### 2.3 是否可以仅添加 `.audio` 输出，不处理/不保存画面

**可以，且必须如此设计：**

| 配置 | 建议 |
|---|---|
| `capturesAudio` | `true` |
| `captureMicrophone` | `false` / 不启用 |
| `addStreamOutput(..., type: .audio)` | **唯一业务 output** |
| `.screen` output | **不注册**；若系统仍生成内部帧，**丢弃且永不写盘** |
| `width` / `height` | 保持最小合法值（S1 试 2×2 或文档默认），仅满足配置约束 |
| 落盘 | **永不**写截图 / 视频 / 原始 display buffer |

**产品承诺：** 临时介质只含 **PCM 音频片段**（见 2.6），确认排轴后销毁；provenance **不含** 音频路径与字节。

### 2.4 `CMSampleBuffer` 如何接入现有 16 kHz mono PCM 管线

```text
SCStream (.audio)
  → CMSampleBuffer (AudioBufferList, 配置 sampleRate/channelCount)
  → AVAudioConverter / Accelerate
       → Int16 16_000 Hz mono interleaved
  → 路径 A：追加写入临时 WAV（与 SpeechTimedTranscriptProvider 兼容）
  → 路径 B：SFSpeechAudioBufferRecognitionRequest.append（流式，S1/S3 评估）
```

**配置建议（S1 可先用接近最终的参数）：**

- `configuration.sampleRate = 48000` 或 `16000`（以系统实际吐出为准；**以回调 ASBD 为准再转换**）
- `channelCount = 1` 或 2→downmix mono
- 时间戳：优先 buffer 的 `CMSampleBufferGetPresentationTimeStamp`，与 host 时钟交叉校验

**与 `AudioPCMConverter` 的关系：**

- 现有 `prepare(audioURL:)` 面向 **完整文件**。
- SCK 需要新模块（建议名 `CapturedPCMAssembler` / `ScreenCaptureAudioIngest`），产出 **与 `PreparedAudio.pcmURL` 同构的临时 WAV**，再调用现有 `transcribe(pcmURL:)`。
- **不要**把 SCStream 逻辑塞进 `LineForcedAligner`。

### 2.5 `SpeechTimedTranscriptProvider` 是否支持流式 PCM；最小适配点

| 现状 | 说明 |
|---|---|
| 协议 | `transcribe(pcmURL:localeIdentifier:progress:)` **仅 URL** |
| 实现 | `SFSpeechURLRecognitionRequest(url:)` |
| 流式 | **当前未用** `SFSpeechAudioBufferRecognitionRequest` |

**最小适配点（实现阶段，二选一或分阶段）：**

1. **S1–S2 推荐最小：** 捕获连续段 → 写 `.../capture_<continuity>.wav` → **零改 Speech 实现** 调现有 provider。  
2. **S3 可选增强：** 扩展 `TimedTranscriptProvider`：
   - `transcribe(pcmURL:…)` 保留  
   - 或新增 `transcribe(samples: AVAudioPCMBuffer / fileURL 段列表)`  
   - 流式用 `SFSpeechAudioBufferRecognitionRequest`（注意：长时流式识别的稳定性与取消语义需实测）

**Partial 行级对齐不依赖流式 ASR：** 可在「一段连续播放结束 / 用户点停止 / 切歌前」对 **已累计 PCM** 跑 batch 识别 + DP。

### 2.6 内存 vs 自动清理临时文件

| 方案 | 优点 | 缺点 | 建议 |
|---|---|---|---|
| 纯内存 | 无落盘 | 3–5 分钟曲 × 16k mono ≈ 数 MB～数十 MB 尚可，但崩溃难审计；Speech URL API 仍要文件 | 仅 S1 统计用 ring buffer |
| **临时文件 + 显式 cleanup** | 与现网 Speech 路径一致；可 hash；可限生命周期 | 需严格删除 | **产品默认** |
| 长驻 Application Support | 方便调试 | 违反「不保存音频」 | **禁止** |

**清理触发（必须设计为幂等）：** 成功确认排轴、失败、取消、切歌、会话结束、App 退出（`atexit`/AppDelegate）、启动时清扫 `tmp/SpotifyLyricsCapture/*` 孤儿目录。

### 2.7 必须记录的关联字段（设计）

```text
CapturedAudioSegment
  trackIdentity: TrackIdentity          // 捕获开始时冻结
  continuityID: UUID                    // 同一次连续录制；pause/seek 打断则新 ID
  spotifyPositionStart: TimeInterval    // 该段起点对应的 PlaybackState.currentTime
  spotifyPositionEnd: TimeInterval?     // 段结束时的 position（若可知）
  hostTimeStart: UInt64 / TimeInterval  // mach_absolute_time 或 CFAbsoluteTime
  hostTimeEnd: …
  duration: TimeInterval                // 由 PCM 帧数 / sampleRate 推导
  pcmByteCount: Int
  temporaryPCMReference: URL?           // 仅运行时；不得进 SQLite / provenance
  interruptionReason: enum?             // none | pause | seek | trackChange | permission | spotifyExit | cancel | error
  sha256: String?                       // 段或拼接后文件的 hash（可进 provenance 的 audioSHA256）
```

**会话级：**

```text
LiveAlignmentCaptureSession
  sessionGuard: AlignmentSessionGuard   // identity + parentVersionID + sourceHash + revision
  continuityID: UUID
  segments: [CapturedAudioSegment]
  localeIdentifier: String
  state: idle | explaining | requestingPermission | capturing | recognizing | aligning | preview | failed
```

**对齐时时间映射：**

```text
lyricLineAbsoluteTime ≈ spotifyPositionStart
  + (transcriptSegment.startTime - pcmTimelineOrigin)
```

`pcmTimelineOrigin` 为该 continuity 内 PCM 时间轴零点；seek/切段后 **新 continuity**，禁止把旧段时间轴直接接到新段而不 remap。

### 2.8 场景处理矩阵

| 场景 | 行为 |
|---|---|
| **从歌曲中间开始** | 允许；仅对齐「捕获开始之后」能证据覆盖的行；更早行保持 **unresolved**；不回填假时间 |
| **暂停** | 停止写入当前 continuity；标记 `interruptionReason=pause`；恢复播放时 **新 continuityID**（避免静音被当成歌词） |
| **继续** | 新段 `spotifyPositionStart = 当前 position`；合并策略：多段 transcript 映射到同一歌词表再 DP，或分段 DP 后合并（S3 定） |
| **seek** | 检测 `position` 非单调跳跃超过阈值 → 结束段 + 新 continuity；旧段仍可用于已覆盖行 |
| **重复播放 / 循环** | identity 不变但 position 回绕 → 视为 seek；避免双重证据冲突（后段覆盖需用户确认或取更高置信） |
| **切歌** | `trackChange` 已有 `alignmentTask?.cancel`；**同时** stop SCStream、作废 guard、删临时 PCM、丢弃未确认 preview |
| **A → B → A** | B 期间结果不得写入 A；回到 A 时新会话，不自动复活 B 的迟到 buffer（guard + continuity 绑定 identity） |
| **权限中断** | stream error / 系统撤销录屏 → 停捕、提示、保留已 partial 预览可选；不静默重试全盘捕获 |
| **Spotify 进程重启** | applications 列表失效 → stop；用户需重新启动捕获；不自动绑到错误 PID |

### 2.9 迟到结果不写入新歌曲

沿用并扩展现有机制：

1. 捕获启动时冻结 `AlignmentSessionGuard`（identity + parent version + hash + **captureSessionID/revision**）。  
2. SCStream 回调、PCM 收尾、ASR 完成、DP 完成 **每一步** `guard.accepts(...)`。  
3. `PlaybackState.synchronize` 在 `identityChanged` 时 **cancel alignmentTask + stop capture**（S2 接线）。  
4. 任何失败路径不调用 `saveAlignedVersion`。  
5. Preview 态切歌：回落新曲 session，旧 preview 丢弃。

### 2.10 退出 / 失败 / 切歌 / 取消 / 崩溃恢复清理

| 时机 | 动作 |
|---|---|
| 正常结束 | stop stream → flush → 可选识别 → cleanup 目录 |
| 取消 | cancel task + stop stream + delete temp |
| 切歌 | 同上 + 提升 revision |
| 失败 | 同上；日志记 reason |
| App 退出 | `stop` + cleanup；不依赖用户点确认 |
| 崩溃恢复 | 启动时扫描并删除 `NSTemporaryDirectory()/SpotifyLyricsCapture/**` 孤儿 |

**禁止** 把捕获音频拷进 Application Support 或用户音乐库。

---

## 3. Partial 策略（强制，替代「一行失败整次失败」）

### 3.1 规则

| 规则 | 说明 |
|---|---|
| 已对齐行 | 保留 `startTime`/`endTime`/confidence/evidence |
| 未解决行 | `status = unmatched`（或显式 `unresolved`），**无伪造时间** |
| 禁止 | 平均铺轴、按行数均分、无 anchor 插值超出现有「双侧真实 anchor 有界插值」 |
| 低置信 | 仅候选；默认不 lock |
| 正式采用 | 用户确认；建议 unresolved 存在时禁止 lock，或仅允许「保存为未锁定候选」 |
| 父版本 | 永远可恢复 |

### 3.2 对现有代码的冲击点（实现时）

| 位置 | 现状 | S3 方向 |
|---|---|---|
| `SpeechForcedAlignmentService` | `guard result.isComplete else { throw insufficientEvidence }` | 改为产出 **partial report**，不 throw（或 throw 仅当 0 行有证据） |
| `LineForcedAligner` | 已支持 unresolved 列表 | 基本可复用 |
| `AlignmentReport.makeDocument` | 全部行映射为 synced | partial 时：`isSynchronized` 语义需定义——建议 **仍可预览**，播放层对 unresolved 行不 seek |
| `AlignmentPreviewView` | 只读展示 | 标明 unresolved / 覆盖率 |
| 确认保存 | `is_synced=1` 整版 | 允许保存「部分同步」候选；编辑器补全后再 lock |

### 3.3 建议数据结构（只设计）

见 §2.7 `CapturedAudioSegment` + 会话态；对齐输出沿用 `AlignedLyricLine` + `AlignmentLineEvidence.kind = noEvidence`。

**Provenance 扩展字段（仍 sidecar JSON，无 migration）：**

- `captureMethod: "screenCaptureKit.spotifyAudio.v1" | "localFile.v1"`
- `continuityCount`, `segmentCount`, `coverageRatio`
- `localeIdentifier`
- **不写** 临时路径、不写 PCM

---

## 4. 语言 / Locale 最小策略

| 规则 | 设计 |
|---|---|
| 推荐来源 | ① `LyricsDocument.language` ② `LyricsLanguageGate.inferredLanguage`（假名→ja）③ Track 元数据弱提示 ④ fallback |
| 可选 locale | `ja-JP` / `zh-CN` / `en-US`（Speech 系统词典可用性以设备为准） |
| UI | **不在普通界面常驻**；仅在「边听边排轴」说明 sheet 内一行「识别语言」+ 可改 |
| Fallback | 无法判断 → **显式** `ja-JP` 并文案说明「可改为中文/英文」；不静默乱猜 en |
| 不做 | Whisper、云端、付费 STT |

---

## 5. 产品与权限（信息最小原则）

### 5.1 入口

| 位置 | 行为 |
|---|---|
| **当前歌曲面板** | 仅当：live track + **纯文本**（`!isSynchronized`）+ 已有可绑定父版本 → 显示 **「边听边自动排轴」** |
| 点击后 | Sheet：隐私说明（只捕获 Spotify 音频、不录麦、不存音频、只生成时间候选）→ 系统权限 → 开始 |
| **设置首页** | **不放**醒目开关 |
| **设置 → 高级 → 自动排轴** | 永久权限状态、打开系统设置、**默认关闭**相关选项、说明文案；**不是**常驻主推 |
| 捕获中 | 克制状态：如「正在捕获 Spotify 音频以排轴…」+ 停止按钮；不闪动大横幅 |
| 本地文件排轴 | **保留**为二级/回退：「选择本地音频排轴」 |

### 5.2 权限文案方向（实现时写入 Info.plist）

- 屏幕录制用途说明须诚实：**为对齐歌词时间轴，仅捕获 Spotify 播放音频；不采集麦克风；不上传。**
- 现有 Speech 文案需同步修订（今日写「不会读取 Spotify 受保护音频」——与 SCK 入口语义冲突）。

### 5.3 用户心智

- **主动、可停、可丢弃、可回退版本。**
- 默认关闭；无后台静默捕获。

---

## 6. 法律与发布边界（不宣称完全合法）

| 维度 | 审计结论 |
|---|---|
| ScreenCaptureKit | **公开系统 API**；需屏幕录制权限 |
| 仅捕获 Spotify 音频 | 技术上过滤 App；**不消除** 对 Spotify **服务条款** 与内容版权的产品责任 |
| App Store | 屏幕录制、第三方媒体相关审核 **不确定**；需真实 Privacy 描述与用途限制；可能被拒或要求澄清 |
| Sandbox | 当前工程 **未开 sandbox**；若上架需评估 sandbox + 录屏 entitlement 组合 |
| 系统选择器 | 新系统可能倾向 `SCContentSharingPicker` 用户手选内容——S1 必须测「能否程序化限定 Spotify」 |
| 首次授权后 | 部分环境需 **重启 App** 或重新开关权限——S1 记录 |
| **综合** | **技术可行** · **本地实验可行** · **正式发布需进一步条款／审核核验** |

**本项目红线（不变）：** 不逆向缓存/DRM、不下载盗版音源、不付费歌词 API、不录麦克风、不默认全屏全 App 录音。

---

## 7. 分阶段实施计划

### S0 — 本轮只读审计 ✅

| 项 | 内容 |
|---|---|
| 修改文件 | 仅文档（本文件） |
| 数据库 | 无 |
| 测试 | 无 |
| 产物 | 本 Markdown |
| 风险 | 无代码风险 |
| 回退 | 删除文档即可 |

---

### S1 — ScreenCaptureKit 音频捕获技术 Spike — **DONE 2026-08-04**

见 `s1-screencapturekit-spike/ACCEPTANCE.md`。已证明 `com.spotify.client` 可捕获有效 PCM；Helper 进程树存在但 SC 仅暴露 client；无视频帧、无音频落盘、正式库未打开。

**S1 明确不做：** ASR、DP、SQLite 歌词写入、主窗 UI、正式库。

---

### S2 — Spotify position 与不连续 `CapturedSegment` — **DONE 2026-08-04**

见 `s2-live-capture/ACCEPTANCE.md`。`LiveCaptureCoordinator` + 集中阈值 + PlaybackState seek/跳变通知；pause/resume/seek/切歌/A→B→A 已有真实 Spotify 日志。

---

### S3A — 现有 Speech + Partial 行级对齐

| 项 | 内容 |
|---|---|
| 修改文件 | `SpeechForcedAlignmentService` 取消 complete-or-fail；preview 覆盖率；确认保存候选规则 |
| 数据库 | 无 schema migration |
| 测试 | unresolved 保留；无平均铺轴；0 证据失败 |
| 风险 | 歌唱/伴奏下 Speech 不稳定（**预期，不阻塞路线**） |
| 回退 | 本地文件路径仍可用 |

**说明：** SCK 只解决音频从哪来；**准确率**要到 S3A/S3B 用真实曲验证。不引入 Whisper/付费服务。

---

### S3B — 可靠识别锚点 + 锚点间强制对齐

| 项 | 内容 |
|---|---|
| 思路 | 参考网易云等**公开技术思想**（识别可靠片段作锚点，再在锚点间做行级强制对齐）；**不复制实现** |
| 修改文件 | 对齐策略层扩展；仍复用 `LineForcedAligner` / transcript 边界 |
| 不做 | 逐字 YRC、训练模型、Whisper |
| 风险 | 实现复杂度；需真实曲对比 S3A |
| 回退 | 仅用 S3A Partial |

---

### S3C — 按真实测试决定是否实验人声分离

| 项 | 内容 |
|---|---|
| 触发 | 仅当 S3A/S3B 在真实曲上证明伴奏严重拖累时 |
| 不做默认 | 不因「可能需要」阻塞 S1–S3B |
| 约束 | 本地/系统 API 优先；无付费服务 |

---

### S4 — 权限、录制状态、按需入口

| 项 | 内容 |
|---|---|
| 修改文件 | `CurrentSongOperationsView` 条件「边听边自动排轴」；高级设置；locale sheet |
| 原则 | 设置首页无常驻开关；纯文本才显示入口 |
| 回退 | 隐藏 SCK，仅本地文件 |

---

### S5 — 真实验收（日语 / 中英 / 纯音乐）

| 项 | 内容 |
|---|---|
| 数据库 | **仅临时库**；正式库 SHA 门禁 |
| 证明 | 时间来自捕获+识别；人工修正；重启恢复；纯音乐不造假轴 |
| 回退 | SCK 标实验，默认本地文件 |

---

## 8. 最小需补接口清单（实现时）

| 接口 / 模块 | 作用 |
|---|---|
| `SpotifyAudioCaptureServing` | start/stop；仅 Spotify filter；audio sample 回调 |
| `CapturedPCMAssembler` | buffer → 16k mono；按 continuity 写临时 WAV；cleanup |
| `LiveCaptureCoordinator` | 绑定 `PlaybackState` 位置/播放态/切歌；产出 `CapturedAudioSegment` |
| `TimedTranscriptProvider` 适配 | 文件 batch 优先；可选 buffer 扩展 |
| `AlignmentService` 变体或参数 | `allowPartial: true`；捕获来源 metadata |
| `AlignmentSessionGuard` 扩展字段 | `captureSessionID`（可选） |
| UI | 条件入口 + sheet + 高级设置状态（非首页） |

**不需要：** 第二套 PlaybackState / Session / Timer / 数据库 / 逐字轴 / 主窗重构。

---

## 9. 最终六问（明确回答）

### 1. ScreenCaptureKit 是否适合成为 **默认** 自动排轴入口？

**不适合作为静默默认。**  
适合作为：**用户主动触发的「边听边自动排轴」实验入口**（默认关闭、可解释、可停止）。  
稳定默认回退仍应是 **本地完整音频文件**。

### 2. 本地音频文件是否应保留为稳定回退？

**必须保留。**  
原因：无录屏权限、捕获失败、Helper 漏音、审核受限、用户拒绝 SCK 时仍可完成排轴 V1 闭环。

### 3. 当前代码最小需要补哪些接口？

见 §8；核心是 **捕获 → PCM 组装 →（可选）partial 对齐开关 → 会话接线**，**不重写** DP/Speech 文件识别主干。

### 4. 是否需要数据库 migration？

**S1–S5 主路径：不需要。**  
时间轴继续 `lyrics_versions` 子版本 + `lyric_lines` + provenance sidecar。  
最多 UserDefaults 记「已看过隐私说明」。

### 5. 是否具备进入 S1 技术 Spike 的条件？

**具备（本地实验）。**  
前提：开发机 macOS ≥ 14、可授权屏幕录制、Spotify Desktop 可播放；使用临时目录；**不写正式库**。  
正式上架结论 **不在 S1 关闭**。

### 6. 用户需要提供哪些真实测试 / 操作？

1. 日语清晰人声曲（Spotify 播放 + 可选同曲本地文件对照）。  
2. 中文或英文曲（测 locale）。  
3. 纯音乐负例。  
4. 操作脚本：中途开始、暂停、seek、切歌 A→B→A、拒绝权限、停止捕获。  
5. 确认验收 **只用临时库**。  
6. 知晓：SCK 路径属 **实验**；条款/上架未背书。

---

## 10. 禁止事项核对（本轮与后续）

| 禁止 | S0 状态 |
|---|---|
| 获取 Spotify 原始 DRM 流 / 逆向缓存 | 未做；SCK 走系统捕获 API，仍须合规边界 |
| 下载第三方音频 | 未做 |
| 付费 API / Whisper | 未做 |
| 麦克风 | 设计明确禁止 |
| 第二套 Session/库 | 禁止 |
| 重写排轴引擎 | 禁止 |
| 逐字轴 | 禁止 |
| 改主窗视觉 / 2.7 / 3 | 禁止 |
| 改代码 / 构建 / commit / 正式库 | **本轮未做** |

---

## 11. 建议的用户确认项（再开 S1）

1. 同意 SCK 仅为 **实验入口**，本地文件为回退。  
2. 同意 S3 **Partial** 策略（否决整次失败）。  
3. 同意 S1 只做 PCM 统计 Spike，不接正式保存。  
4. 提供/配合三类播放场景。  
5. 知悉正式发布仍需条款与审核核验。

---

## 12. 暂停点

- 文档路径：`docs/phase-2-11b-alignment-audit/PHASE_2_11B_S0_SCREENCAPTUREKIT_ENTRY_AUDIT.md`
- 基线仍为 `c8e4fce`
- **无代码变更、无构建、无 commit、未打开正式数据库**
- **等待确认后再进入 S1 Spike**

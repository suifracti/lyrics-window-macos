# Phase 2.11C-S0 — Zero-Operation Automatic Alignment 只读架构审计

| 项 | 值 |
|---|---|
| 产品 | **Lyric Island** |
| 项目 | `/Users/apple/backup/sptifylyrics` |
| 分支（审计时） | `codex/phase-2-11b-assist-mvp` |
| 日期 | 2026-08-05 |
| 性质 | **只读架构审计 · 不实施** |
| 前置 | Phase 2.11B：**实现与工程验收完成；真人 UI 验收延期** |
| 禁止 | 改代码 · rebuild · 改库 · whisper.cpp · Demucs/Spleeter · Phase 2.7/2.8/3 |

---

## 0. 执行摘要

### 最终产品目标（默认主路径）

用户在设置中**只开启一次**「自动为未排轴歌词生成时间轴」后，对符合条件的每首纯文本曲自动：

检查权限 → 捕获 Spotify 音频 → 分段积累 → Speech/对齐 → 质量评估 → **达标则保存并采用** → 主歌词跟播。

普通用户**不需要**点「边听边排轴」、Sheet、编辑器、确认建议、手动保存或手动选版本。  
失败：保留纯文本、不伪造、不覆盖锁定、不强制弹窗。

### 架构结论（经 S0.5 真实 A/B 修订 · 2026-08-05）

| 问题 | 建议 |
|---|---|
| 是否先用现有 Apple Speech 做自动调度 MVP？ | **否** — S0.5 显示 Speech→S3 覆盖率极低（A≈6–12%，B≈0.7%）；自动调度只会「自动产出近零可用」 |
| 是否必须先做引擎层 A/B？ | **是** — 同音频上 whisper.cpp small 日语转写显著更可用；S1 应优先 **SpeechEngine + whisper 实验** |
| 能否复制第二套捕获/对齐/仓库？ | **禁止** — 必须抽共享服务；Whisper 只替换 ASR 输入，**不**新 DP |
| 最大结构障碍 | ① Capture 整树 DEBUG；② Speech 歌唱覆盖不足；③ UI 路径曾出现 `lastPartialReport==nil` |
| S1 能否独立验收？ | **能** — 引擎对比 + nil-report 修复；**自动 Job 调度后移** |
| 详见 | `S0_5_ENGINE_VIABILITY.md` |

---

## 1. 当前可复用能力地图

### 1.1 能力一览

| 能力 | 类型 / 符号 | 文件 | 编译门控 | 复用判定 |
|---|---|---|---|---|
| ScreenCaptureKit Spotify 捕获 | `SpotifyScreenCaptureAudioSpike` | `Capture/SpotifyScreenCaptureAudioSpike.swift` | **DEBUG** | **抽共享** — 自动/手动共用底层 |
| 音频会话 | `CapturedAudioSession` | `Capture/CapturedAudioModels.swift` | DEBUG | **原样复用模型** |
| 音频分段 | `CapturedAudioSegment` · `SegmentBoundaryReason` | 同上 | DEBUG | **原样复用模型** |
| 终止原因 | `CaptureTerminalReason`（userStop / trackChanged / autoStop…） | 同上 | DEBUG | **原样复用** |
| 连续策略 | `CaptureContinuityPolicy` | `Capture/CaptureContinuityPolicy.swift` | DEBUG | **原样复用** |
| Live 协调 | `LiveCaptureCoordinator` | `Capture/LiveCaptureCoordinator.swift` | DEBUG | **抽共享服务** — 今日绑定 DEBUG 菜单/Assist；自动模式需同一 coordinator 或薄包装 |
| track/seek/pause/resume | `notifyPlaybackPositionJump` · `$currentTime` · `$isPlaying` · identity 观察 | Coordinator + `PlaybackState` | 混合 | **复用** Playback 已有发布者；**勿**第二 poller |
| S3A Partial | `SegmentPartialAlignmentPipeline` + S3A 分支 | `Capture/SegmentPartialAlignmentPipeline.swift` | DEBUG | **抽共享** |
| S3B Anchor | `AnchorConstrainedAligner` · `AlignmentAnchor` · `AnchorAlignmentPolicy` | `Capture/Anchor*.swift` 等 | DEBUG | **抽共享** |
| 候选合并 | `AssistedCandidateMerger.merge` | `Capture/AssistedCandidateMerger.swift` | DEBUG | **抽共享**；自动模式需 **门控层** 包一层（不可直接「少量建议 = 完整同步」） |
| 草稿模型 | `AssistedAlignmentDraft` · `AssistedLineSuggestion` | `Capture/AssistedAlignmentDraft.swift` | DEBUG | 手动：**原样**；自动：**可选**诊断/工作台，默认不进编辑器 |
| Partial 报告 | `PartialAlignmentReport` · `PartialAlignmentCandidate`（含 coverage/resolved…） | `Capture/PartialAlignmentModels.swift` | DEBUG | **复用指标字段** 作门控输入；注释写「Never written to formal SQLite」— 自动保存走 **正式版本路径**，不直接塞 report 进 SQLite |
| 会话守卫 | `AlignmentSessionGuard` | `Lyrics/AlignmentSessionGuard.swift` | Release 可用 | **原样复用** |
| 部分时间轴 mask | `LyricsDocument.explicitlyTimedLineIndices` | `Lyrics/LyricsModels.swift` + mapper | Release | **原样复用** |
| 部分时间轴落库 | `documentWithoutTranslations` 保留 mask · lineRecords 写部分 start_time | `Persistence/SQLiteLyricsRepository.swift` · `LyricsPersistenceMapper` | Release | **原样复用** |
| 完整同步判定 | `LyricsTimelineValidator` → `isSynchronized` | `Editor/LyricsTimelineValidator.swift` | Release | **原样复用** |
| 本地音频全曲排轴确认 | `saveAlignedVersion` · `AlignmentPersistenceRequest` · source `.automaticAlignment` | `LyricsSessionController` · repository | Release | **复用保存/采用模式**；输入文档来自捕获对齐而非本地文件 FA |
| 编辑器人工保存 | `saveManualEdit` · source `.manualEdit` | `LyricsEditorSessionController` | Release | **手动 DIY 保留**；自动模式优先 `saveAlignedVersion` 或等价「子版本 + parent」API |
| 采用当前版本 | `adoptPersisted` | `LyricsSessionController` | Release | **原样复用** |
| 主界面跟播 | `liveLyricsAreSynchronized` + viewport | V3 / Canvas | Release | **原样** — 仅 `is_synced=1` 跟播 |
| 切歌防串 | `invalidateAssistOnTrackChange` + coordinator `trackChanged` | `PlaybackState`（DEBUG Assist）+ Coordinator | 混合 | **抽共享** 到自动 job 的 invalidate |
| 取消 / WAV 清理 | `stop` · `cleanupSessionDirectory` · scavenge | Coordinator / Spike | DEBUG | **原样复用** 清理契约 |
| 手动 Assist UI | Sheet · CurrentSong 面板 · harness | Views + PlaybackState | DEBUG | **仅手动** — 不作为默认主路径 |
| 调试菜单 S1/S2/S3A | `Main.swift` CommandMenu | DEBUG | **仅诊断** — 不驱动自动 adopt |

### 1.2 三分类（强制）

#### A. 可原样复用（逻辑/模型/Release 持久化）

- `TrackIdentity` · `AlignmentSessionGuard`
- `CapturedAudioSession` / `Segment` 模型语义
- `CaptureContinuityPolicy` 阈值思想
- `PartialAlignmentCandidate` 的 coverage / resolved / lowConfidence / outsideCapturedRange 指标
- `explicitlyTimedLineIndices` + 部分 `start_time` 持久化
- `LyricsTimelineValidator.isSynchronized`
- `saveAlignedVersion` / parent 子版本 / `adoptPersisted`
- `LyricsSource.automaticAlignment`（已有 display「自动排轴」）
- 主界面「未同步不跟播 / 同步才跟播」

#### B. 仅适合手动 Assist（或 DIY 工作台）

- `presentListeningAssistExplanation` / Explain Sheet / V3「边听边排轴」按钮
- 编辑器 `applyAssistedDraft` · Space/N 标记 · 用户 partial confirm 对话框
- Acceptance harness（`assist_start` 等）
- DEBUG 菜单 S1/S2/S3A（诊断）
- 「建议 / 未排」徽章作为**默认**完成标准（自动模式不能只停在少量建议）

#### C. 必须抽成自动/手动共享服务（禁止复制第二套）

| 共享服务（规划名） | 从何处抽 | 职责 |
|---|---|---|
| `SpotifyAudioCaptureService` | Spike + Coordinator 捕获面 | 仅 Spotify 音频 · PCM · 无 mic |
| `LiveSegmentSession` | `LiveCaptureCoordinator` | segment 生命周期 · seek/pause · identity |
| `PartialAlignmentEngine` | `SegmentPartialAlignmentPipeline` | S3A/S3B · locale · report |
| `AlignmentCandidateMerger` | `AssistedCandidateMerger` | 行级候选合并（可改名去 Assist 前缀） |
| `AutomaticAlignmentGate` | **新建** | A/B/C 门控 · 不写入算法阈值硬编码到 UI |
| `AutomaticAlignmentJob` | **新建** 调度器 | 状态机 · 触发 · 取消 · 与 Playback 绑定 |
| `AlignmentVersionWriter` | 封装 `saveAlignedVersion` / partial 写 | 子版本 · 不覆盖 parent/lock · adopt |

手动 Assist 与 Zero-Op **都只调用** 上述服务；UI/开关不同。

### 1.3 关键编译现实

```text
SpotifyLyrics/Capture/*  全部以 #if DEBUG 包裹
```

含义：

- 今日 Release 构建 **不含** 捕获对齐栈  
- 2.11C 产品开关若要进正式默认路径，S1+ 必须规划：  
  - **方案 P1（推荐 MVP）：** 将共享捕获/对齐编译进 Debug **与** 受开关保护的非 DEBUG 配置（或 `#if DEBUG || AUTOMATIC_ALIGNMENT`）  
  - **方案 P2：** 长期仍 Debug-only 实验（与「默认产品主路径」冲突，**不推荐**作为 2.11C 终态）

---

## 2. Zero-Operation MVP 定义（无 whisper / 无 Demucs）

### 2.1 全局开关

| 项 | 值 |
|---|---|
| 稳定 ID | **`automaticAlignment.enabled.v1`** |
| 存储 | `AppSettingsStore` + UserDefaults（与 `lyrics.sourceMode` 同边界） |
| 默认 | **关** |
| 文案（普通） | 自动为未排轴歌词生成时间轴 |
| 开启 | 可选一次性隐私说明（仅当前 Spotify 音频、不上传、可关） |
| 关闭 | 不启动新 job；**安全取消**进行中 job；**已保存时间轴保留** |

### 2.2 自动触发条件（AND）

1. `automaticAlignment.enabled.v1 == true`  
2. 可靠 `TrackIdentity`（`hasLiveTrack` · 非 mock）  
3. Spotify **实际播放中**（`isPlaying`）  
4. 当前歌词 **纯文本**：`alignmentQueued` 或 `!isSynchronized` 且有正文  
5. **无**可靠完整时间轴（`!liveLyricsAreSynchronized`）  
6. 存在 `activeLyricsVersionID`（可挂 parent）  
7. 当前版本 **未**锁定禁止自动改（`is_locked` 策略：锁定同步/锁定父版则不自动写）  
8. ScreenCapture 权限可用（失败 → deferred/failed 软态，不循环弹窗）  
9. 无同 identity 的 active automatic job  
10. 未命中失败冷却 / 用户「本次忽略」  
11. 非手动 Assist capturing、非本地 FA running、非编辑器强制占用（可配置）

### 2.3 自动任务状态机

```text
                    ┌──────────────┐
                    │     idle     │
                    └──────┬───────┘
           eligible + playing │
                    ▼
            waitingForPlayback ◄── pause / 等播放
                    │ playing + ready
                    ▼
               capturing ──seek──► (end segment → new segment, stay capturing)
                    │ pause
                    ▼
                 paused ──resume──► capturing
                    │ enough / end / policy stop
                    ▼
                aligning
                    │
                    ▼
               evaluating
              /    |    \
           saved  failed  deferred
              │      │       │
              └──► idle ◄────┘
                    ▲
                 canceled
```

| 状态 | 含义 | 进入 | 退出 / 副作用 |
|---|---|---|---|
| **idle** | 无自动 job | 初值；任何终态 | — |
| **waitingForPlayback** | 合格但未在播 | 开关开 + 条件满足 + !playing | playing → capturing；切歌 → cancel |
| **capturing** | 正在 SCK + segment | 播放中启动 | pause→paused；seek 换段；切歌→canceled；策略结束→aligning |
| **paused** | 播放暂停，会话可挂起 | capturing 时 pause | resume→capturing；切歌→canceled；超时可选 deferred |
| **aligning** | Speech + S3A/S3B + merge | 捕获窗口结束或周期性 | → evaluating；失败→failed |
| **evaluating** | 质量门控 A/B/C | aligning 完成 | A→saved；B 缓存候选→deferred/idle；C→failed/idle |
| **saved** | 已写子版本且（若 A）已 adopt | gate A | → idle |
| **failed** | 软失败 | 权限/捕获/对齐/门控 C | 冷却；→ idle；**不写正式时间轴**（或仅诊断） |
| **canceled** | 用户关开关 / 切歌 / 本次停止 | 任意活动态 | 清理 WAV；不 adopt；→ idle |
| **deferred** | 证据不足但可续排 | 半首歌 / gate B | 写 **任务缓存** 非当前版；同曲再播续排 |

#### 横切行为

| 事件 | 行为 |
|---|---|
| 切歌 A→B | A → **canceled**；丢弃未确认；B 重新 idle→评估触发 |
| A→B→A | **新 jobId**；可加载 A 的 partial **缓存** 续排；永不合并 B 证据 |
| seek | capturing 内 end segment + new segment（`CaptureTerminalReason`/boundary 已有） |
| 暂停 | capturing → paused |
| 退出 App | 见 §4.3 中间状态；进行中捕获 **不**假装完成 |
| 重启 App | 读开关；读磁盘 partial 缓存；**不**自动 resume 半截 SCK，除非重新 eligible 且用户在播 |
| 用户关开关 | 全 job **canceled** |

---

## 3. 触发与取消规则（汇总）

| 动作 | 规则 |
|---|---|
| 启动 | §2.2 全满足 |
| 不启动 | 已同步 · noSelection · 锁定 · 冷却 · 已有 job · 手动占用 · 权限无 |
| 用户「本次停止」 | 本 identity 本会话 ignore；canceled |
| 用户「重新尝试」 | 清冷却；idle 再评估 |
| 关闭全局开关 | 取消全部；保留已保存版本 |
| 手动 Assist 开始 | **抢占**：cancel automatic job（避免双捕获） |

---

## 4. 分段积累与续排

### 4.1 捕获现实

ScreenCaptureKit **只能**得到当前实际播出的音频。  
因此：

| 场景 | 语义 |
|---|---|
| 从 00:00 连播 | 多 segment 拼 `capturedRanges`，coverage 可趋近全曲 |
| 从中途开始 | 仅中后段有证据；`outsideCapturedRange` 行保持未排 |
| seek | 旧 segment 结束，新 segment，continuity 可能 false |
| 暂停 | 停止累积样本 |
| 切歌 | 关会话；**不串歌** |

### 4.2 合并原则

- 行级合并：**锚点 > S3B 高置信 > S3A 高置信**（现 merger）  
- **禁止**对未捕获区间插值铺满  
- 同 parent `sourceContentHash` 才可续排合并  
- parent 正文变更 → 废弃旧 partial 缓存  
- 冲突时间：保留更高置信 / 锚点；否则标 unresolved  

### 4.3 退出 App 的中间状态（安全）

| 存什么 | 存哪 | 不存什么 |
|---|---|---|
| partial 行候选（index, t0, t1, conf, source） | **任务缓存**（Application Support 子目录或 TEMP，**非**冒充当前歌词版） | 原始 WAV（默认删） |
| identity + parentVersionID + parentHash + engineId + updatedAt | 缓存元数据 | 完整 PCM |
| 可选：上次 gate 结果 | 元数据 | 把 partial 标成 is_synced=1 |

**不得**因半曲捕获写 `is_synced=1` 并 adopt。

### 4.4 多次播放

1. 播 #1：听副歌 → 缓存 partial  
2. 播 #2：听主歌 → merge 进缓存  
3. 当 `listen_union` 与 gate 达标 → 才允许完整 adopt  
4. 更可信结果不覆盖：同 index 仅当新 conf 显著更高或来自 anchor  

### 4.5 与「少量 Assist 建议」的区别

2.11B merger 常产出 **个位数 suggested 行**。  
Zero-Op **禁止**把该结果直接标完整同步。  
自动采用完整版必须过 §5 门控（覆盖率等）。

---

## 5. 自动质量门控

### 5.1 候选指标（本轮 **不冻结阈值**）

| 指标 | 来源线索 |
|---|---|
| 歌词覆盖率 | `coverageRatio` · timed/nonblank |
| 单调性 | `LyricsTimelineValidator` errors |
| 锚点数量 | `acceptedAnchors.count` |
| 高置信行比例 | conf 分档 / `AssistedConfidenceClass` |
| 未排行比例 | unresolved / outsideCapturedRange |
| 重复副歌歧义 | 同文案多行时间冲突计数（规划） |
| 与 duration 合理性 | 末行时间 ≤ duration + ε |
| 首尾覆盖 | 是否触及曲首/曲末 capturerange |
| 冲突数量 | merger skip / validator |
| 异常间隔 | 行间隔 >> 中位数 |

### 5.2 三类结果

| 类 | 名称 | 行为 |
|---|---|---|
| **A** | 自动采用 | 保存子版本 + **adopt**；完整则 `is_synced=1` 跟播；高 partial 仅 `is_synced=0` 且**不**伪跟播 |
| **B** | 未采用候选 | 可写**非当前**候选或仅任务缓存；用户工作台可见 |
| **C** | 丢弃 | 不写正式版本；可选计数冷却 |

**A 的完整 adopt** 建议同时要求：高 coverage + 校验通过 + 足够听过比例（具体数 S2+ 标定）。  
**A 的 partial adopt**（可选产品策略）：`is_synced=0` + 部分 start_time，主界面仍显示未排轴 — 与 2.11B 语义一致。

---

## 6. 保存与版本规则

| 规则 | 说明 |
|---|---|
| 子版本 | 自动结果 **始终**新建 child（parent = 当前纯文本 version） |
| 不覆盖 parent | 父纯文本保留 |
| 不覆盖锁定 | `is_locked` 版不自动改；不 adopt 覆盖锁定当前 |
| 完整达标 | gate A full → `is_synced=1` · `source=.automaticAlignment` · adopt |
| 部分 | 优先 **任务缓存**；若产品要入库：`is_synced=0` + mask，**默认不**打扰式 adopt（或可配置） |
| 用户恢复 | 版本历史 / 选回 parent 或旧同步（已有编辑器/版本能力） |
| 防版本爆炸 | 同 parentHash + 同 engine 代际：更新「最新自动候选」而非无限 insert；或 cap N 条自动版 LRU |
| 算法升级 | `engineId + algoGeneration`；升级允许新 child，旧版保留 |
| 元数据 | provider_source_id / confidence / 未来 provenance（已有 alignment provenance 方向）；**本轮不改 schema**，用现有字段 + 可选 JSON 侧车缓存 |

### 6.1 Schema

- **MVP：不迁移**  
- 任务缓存可用文件系统 JSON（identity digest 文件名）  
- 若未来要查「自动候选列表」再考虑表；S0 **不要求** migration  

### 6.2 写入 API 选择

| 路径 | 适用 |
|---|---|
| `saveAlignedVersion` + `AlignmentPersistenceRequest` | 完整（或校验通过的）对齐文档 · 已有 automaticAlignment |
| `saveManualEdit` | 手动 DIY；自动慎用 |
| 仅缓存文件 | gate B/C · 续排 |

---

## 7. 普通 / 高级 UI

### 7.1 普通设置

```text
自动为未排轴歌词生成时间轴  [开关]   // automaticAlignment.enabled.v1
```

可选只读状态一行（非强制）：

| 状态 | 文案示例 |
|---|---|
| capturing / aligning | 正在听取并生成时间轴 |
| saved (A) | 已完成 |
| failed / C | 本次未能可靠完成 |
| deferred / partial | 等待继续播放 |
| waitingForPlayback | 等待播放 |
| 权限 | 需要屏幕音频权限（点按去设置） |

**不显示：** S3A/S3B、DP、Anchor、Segment、confidence 数字、ScreenCaptureKit、引擎内部名。

### 7.2 当前歌曲（可选、非必需）

- 本次停止自动排轴  
- 重新尝试  
- 打开工作台检查  

### 7.3 高级 DIY（仅规划）

- 引擎：自动 / Apple Speech / Whisper（未来）  
- 人声预处理：关 / 自动 / Demucs（未来）  
- 速度档：速度 / 平衡 / 准确  
- 仅插电  
- 模型下载删除  
- 自动采用阈值  
- 查看候选、锚点、未排行（复用编辑器 / 只读诊断）  

手动「边听边排轴」**留在高级/DIY**，不再默认主路径。

---

## 8. 数据库影响

| 项 | MVP |
|---|---|
| schema migration | **不需要** |
| 新表 | 不需要（缓存用文件） |
| 新 source | 复用 `automaticAlignment` |
| formal 库 | 仅产品正常路径；验收继续 TEMP |
| 版本爆炸 | 应用层 cap / 去重策略 |
| 锁定 | 读 `is_locked`，不写覆盖 |

---

## 9. whisper.cpp / Demucs 进入条件（A/B Gate）

### 9.1 whisper.cpp

**仅当**同一批真实样本上相对 Apple Speech **明显**提升：

- 可用识别片段数  
- 锚点数  
- coverage  
- 时间误差（若有 GT / held-out）  

且：模型体积、许可证、签名打包、CPU/能耗可接受 → 才进 **实验引擎** 槽。  
**不是** S1 前置。

### 9.2 Demucs

**仅当**失败分析表明主因是 **伴奏干扰**（非歌唱发音/语言）时，才实验：

`Demucs → whisper/Speech`。

默认关；仅插电 + 用户同意下载。

### 9.3 Spleeter

默认 **不进入** 路线，除非 macOS 集成/体积/速度有独立实证优势。

---

## 10. 风险与开放问题

| 风险 | 说明 |
|---|---|
| DEBUG 整树 | 自动产品路径与编译门控冲突 |
| 覆盖率天花板 | 歌唱 Speech 弱；自动 full adopt 率可能低 — **产品可接受 partial 不强制** |
| 双捕获 | 手动 Assist 与自动 job 抢 SCK — 需互斥 |
| 隐私/TCC | 无 UI 时权限失败要软性 |
| 版本膨胀 | 需 cap |
| 误 adopt | 门控过松会污染当前版 — 默认宜严 |
| V3 工具栏 hover | 与自动主路径无关；DIY 入口仍可能难发现 |

开放问题：

1. gate A 是否允许自动 adopt **partial**（is_synced=0）？  
2. 在线 LRCLIB 同步与自动排轴优先级？  
3. 失败是否允许偶发非阻塞徽章？  
4. 任务缓存是否加密/随 App 删除？  

---

## 11. 最小实现拆分与 S1 范围

### 11.1 阶段切分

| 阶段 | 内容 | 独立验收 |
|---|---|---|
| **S0** | 本文档 | 只读 ✅ |
| **S1** | 开关 + Job 状态机 + 触发/取消 + 复用捕获对齐 + **只日志/不自动 adopt**（或仅 TEMP 诊断） | **是** |
| **S2** | Gate A/B/C + 缓存续排 | 是 |
| **S3** | Gate A → saveAlignedVersion + adopt + 跟播 | 是 |
| **S4** | 普通 UI 状态文案 + 当前歌曲「停止/重试」 | 是 |
| **S5** | 引擎协议 + Speech 适配；whisper 槽位空 | 是 |
| **S6+** | whisper A/B · 可选 Demucs | 独立实验 |

### 11.2 S1 建议修改文件（实施时 · 本轮不动）

| 文件 | 变更意向 |
|---|---|
| `AppSettingsStore.swift` | `automaticAlignment.enabled.v1` |
| **新建** `AutomaticAlignmentJobController.swift`（或 Services 下） | 状态机 · 触发 · 与 Playback 订阅 |
| `PlaybackState.swift` | 绑定 job；切歌转发；与 Assist **互斥** |
| `LiveCaptureCoordinator.swift` 等 Capture/* | 逐步去「仅菜单」耦合；评估 DEBUG 宏策略 |
| `Main.swift` / Settings UI | 普通开关一行 |
| `Tests/automatic_alignment_*_contract.sh` | 触发/取消/不双开/不写库（S1） |

**S1 不改：** schema、whisper、Demucs、编辑器主路径、S3C。

### 11.3 S1 验收标准（规划）

1. 开关默认关；开后对纯文本曲在播放时出现 job 日志状态迁移  
2. 切歌 canceled；关开关 canceled  
3. 与手动 Assist 互斥  
4. **不**自动 adopt；**不** formal 脏写（TEMP 验收）  
5. 合同脚本绿  
6. 不要求真人 G1–G7（2.11B 延期项仍不阻塞 S1）

### 11.4 明确建议（S0.5 修订后立场）

1. **不要**先做「仅 Apple Speech 的 AutomaticAlignmentJob 自动调度」——真实样本上有效覆盖过低。  
2. **S1 改为：** 修 `lastPartialReport` 空失败 + `SpeechEngine` 抽象 + **whisper.cpp 实验引擎**（CLI/侧车可接受）+ 注入现有 S3A/S3B；**不做**全局开关与 auto-adopt。  
3. **禁止**第二套 Session/捕获器/仓库/对齐 DP。  
4. 手动 Assist = DIY 回退；零操作默认主路径 **等引擎门控通过后再**上 Job。  
5. S1 **可独立验收**（同 wav 对比 Speech vs Whisper 的 anchors/coverage；UI 不再误报无报告）。  
6. Demucs **暂不**进入，除非 Whisper 后仍证明主因是伴奏。  
7. 完整证据见 **`S0_5_ENGINE_VIABILITY.md`**。

---

## 12. 与 Phase 2.11B 的关系（产品）

| | 2.11B | 2.11C |
|---|---|---|
| 定位 | 半自动校正 / DIY | **默认零操作** |
| 状态 | 实现与工程验收完成；真人 UI 延期 | S0 架构审计（本文） |
| 入口 | 边听边排轴（高级） | `automaticAlignment.enabled.v1` |
| 完成标准 | 建议+用户保存 | 门控 A 自动 adopt |

---

## 13. 产出与暂停

| 文档 | 路径 |
|---|---|
| 本审计 | `docs/phase-2-11c-zero-operation-alignment/S0_ARCHITECTURE_AUDIT.md` |
| 先前规划 | `docs/phase-2-11c-zero-operation-alignment/PLAN.md` |
| 2.11B 状态 | `assist-v3-final-acceptance/ACCEPTANCE.md`（已标工程完成 / 真人延期） |

**S0 完成。暂停。不自动实施 S1。不接入 whisper/Demucs。不进入 2.7/2.8/3。**

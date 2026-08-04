# Phase 2.11B — 真实音频自动排轴：只读审计与最小实施计划

| 项 | 值 |
|---|---|
| 日期 | 2026-08-04 |
| 工作目录 | `/Users/apple/backup/sptifylyrics` |
| 基线 HEAD | `c8e4fce`（`feat(lyrics): dual free source modes with settings gate`） |
| 前序 | Phase 2.6 完成 · Phase 2.11A 完成 · 免费歌词双模式完成 |
| 本轮范围 | **只读审计 + 实施计划**；不修改 Swift、不改库、不 commit、不抓 Spotify 音频、不接入付费服务、不进入 2.7/3 |
| 排轴实现祖先 | `8aea61f`（`feat: implement real audio line alignment v1`，2026-07-30）已在当前基线祖先链上 |

---

## 0. 执行摘要

**一句话：**  
「已知纯文本歌词 + 用户自选完整本地音频 → Speech 带时间片段 → 行级 DP 强制对齐 → 预览/编辑器 → SQLite 子版本 + provenance sidecar」的 **代码与合同已基本落地**；**真实商业歌曲端到端验收仍标记为 UNVERIFIED**。Phase 2.11B 不应从零重写，而应做 **真实验收闭环 + 少量产品缺口修补**。

| 维度 | 完成度（主观） | 说明 |
|---|---|---|
| 架构与协议 | ~90% | `AlignmentService` / transcript / DP / guard / persist 边界清晰 |
| 生产代码路径 | ~85% | 本地音频 → PCM → Speech → 行对齐 → 预览 → 确认写入 |
| 合同/合成测试 | ~95% | 多份 contract 覆盖 DP、PCM、guard、persist、wiring |
| 真实商业曲验收 | **~0–10%** | 2026-07-30 明确：无匹配完整人声音频，不声称成功 |
| 逐字时间轴 | 0%（有意不做） | V1 明确只做行级 |
| 非日语 locale 产品化 | ~20% | 默认硬编码 `ja-JP`；中英文需显式扩展 |
| 可视化拖动改轴 | ~40% | 编辑器有时间字段 /「标到当前播放」；**无时间轴拖拽手柄** |

**是否具备进入实现阶段：** **有条件具备**。  
代码侧可开工做「真实验收脚本 + 小缺口修补」；**必须先由用户提供匹配的本地完整人声音频**，否则只能重复合同测试，无法关闭商业验收。

---

## 1. 必读资产地图

### 1.1 时间轴与歌词模型

| 文件 | 角色 |
|---|---|
| `SpotifyLyrics/Lyrics/LyricsModels.swift` | `LyricsDocument` / `LyricsSource` / 行查找 `activeLineIndex` / seek 校验 |
| `SpotifyLyrics/Lyrics/AlignmentModels.swift` | `AlignedLyricLine`、`AlignmentLineEvidence`、`AlignmentRequest/Report`、时长门 |
| `SpotifyLyrics/Lyrics/TimedTranscript.swift` | 识别片段抽象（非歌词正文） |
| `SpotifyLyrics/Lyrics/LRCParser.swift` | LRC 导入/导出；有时间戳 → `isSynchronized` |

**行级时间结构（持久化与播放共用）：**

- 播放层：`LyricLine.timestamp`（起点）+ `LyricsDocument.isSynchronized`
- 对齐层：`AlignedLyricLine.startTime` / `endTime?` / `confidence` / `status` / `evidence`
- **无** 字级/音节级/音素级字段或表

### 1.2 版本与仓库

| 文件 | 角色 |
|---|---|
| `Persistence/DatabaseMigrator.swift` | schema v1–v6；`lyrics_versions` + `lyric_lines`；v3 起 `parent_version_id` |
| `Persistence/SQLiteLyricsRepository.swift` | `saveAlignedVersion`、锁定时 provenance 检查 |
| `Persistence/AlignmentProvenanceStore.swift` | 原子 sidecar JSON（无音频路径/无完整 transcript） |
| `Persistence/LyricsRepository.swift` | `AlignmentPersistenceRequest` 协议边界 |
| `Lyrics/LocalAlignedLyricsStore.swift` | 可选 `.aligned.lrc` 旁路导出 |

**`lyric_lines` 列（行级，非逐字）：**

```text
lyrics_version_id, line_index, start_time, end_time,
original_text, kana_text, romaji_text, translation_text
```

**确认排轴写入约定（代码意图）：**

- `source = automaticAlignment`
- `parent_version_id =` 纯文本父版本
- `is_synced = 1`
- `is_manually_edited = 1`（标记可审，非「用户已拖过」的充分条件）
- 默认 `lockResult = false`；低置信 + 锁定会被拒
- sidecar：`~/Library/Application Support/SpotifyLyrics/AlignmentProvenance/<versionID>.json`

### 1.3 Alignment / ASR / Forced Alignment

| 文件 | 角色 | 真/假 |
|---|---|---|
| `AlignmentService.swift` | 协议边界 | 真 |
| `SpeechForcedAlignmentService.swift` | 生产编排：PCM → transcript → DP | 真（Speech） |
| `SpeechTimedTranscriptProvider`（同文件） | `SFSpeechURLRecognitionRequest` | 真 on-device ASR 片段 |
| `LineForcedAligner.swift` | 全局单调 DP 行对齐 | 真算法（确定性） |
| `AudioPCMConverter.swift` | 解码/元数据/hash/16k mono PCM/清理 | 真 AVFoundation（+可选 ffmpeg） |
| `AudioInputMetadata.swift` | 时长/采样率/声道/内嵌标签/SHA-256 | 真 |
| `AlignmentSessionGuard.swift` | identity + parent version + hash + revision | 真 |
| `LocalAudioASRService.swift` | **无词时**从音频生成歌词草稿 | 真 Speech，但是 **另一条产品路径** |
| 合同中的 TEST transcript provider | 合成片段 | 仅测试，不得当商业证据 |

**明确已去掉/禁止的假路径（V1 目标与当前代码意图）：**

- 按歌曲总时长平均铺开（`spreadLowConfidence` 类逻辑已从产品路径移除）
- `SPOTIFYLYRICS_AUTO_ALIGN` 自动触发
- 用 TTS / `kawasaki_tts.wav`（79s vs 171s 曲）冒充商业验收

### 1.4 UI / 会话边界

| 入口 | 位置 |
|---|---|
| 选择本地音频排轴 | `PlaybackState.alignCurrentLyricsWithLocalAudio()` |
| 确认 / 取消 | `confirmAlignmentPreview` / `cancelAlignmentPreview` |
| ASR 草稿（无已知歌词） | `importLocalAudioForASR` / `runLocalAudioASR` |
| 预览面板 | `AlignmentPreviewView`（只读 evidence，**不**改时间） |
| 主窗/当前歌曲 | `AppleMusicImmersiveV3WindowView`、`CurrentSongOperationsView` |
| 人工改时间 | `LyricsEditorWindowView`：时间文本框 +「标到当前播放」+ 行点击 seek |
| 会话状态机 | `LyricsSessionController`：`alignmentRunning` / `alignmentPreview` / confirm |
| TrackIdentity | 排轴全程绑定 live identity；迟到结果用 `AlignmentSessionGuard` 丢弃 |

### 1.5 历史证据与 commit

| 资产 | 结论 |
|---|---|
| `8aea61f` Real Audio Line Alignment V1 | 实现主体；仍是当前 HEAD 祖先 |
| `docs/superpowers/plans/2026-07-30-real-audio-line-alignment-v1.md` | 实施计划（已大部分落地） |
| `docs/superpowers/specs/acceptance-2026-07-30-real-audio-line-alignment-v1/README.md` | **合同 PASS · 商业曲 UNVERIFIED** |
| `docs/superpowers/specs/acceptance-2026-07-27-alignment-v1/` | 早期接线/时长门修复证据；含错误 TTS 路径教训 |
| `docs/superpowers/specs/2026-07-27-asr-lyrics-fallback-design.md` | ASR 草稿设计（与「已知词强制对齐」分离） |
| `progress.md` / `task_plan.md` Phase 39 | 与上一致：商业验收 pending |

### 1.6 导入纯文本 / TXT / LRC 后的路径（与排轴的关系）

```text
TXT / 粘贴 / 人工创建  →  manualImport|manualCreate  →  isSynchronized=false
     →  可进入「已知纯文本 + 本地音频」强制对齐

LRC（含时间）         →  isSynchronized=true
     →  alignCurrentLyricsWithLocalAudio **拒绝**（要求先建纯文本副本）

Provider 纯文本（如部分实验源/LRCLIB 非同步）→  isSynchronized=false
     →  同上可排轴（需已有 SQLite 父版本 ID）

Provider 同步 LRC    →  isSynchronized=true → 直接播放，不经排轴

ASR 草稿             →  source=asrMachineGenerated，可能带粗时间
     →  产品上是「生成正文」；强制对齐主路径要求「已有纯文本版本」
```

**前置硬条件（代码）：** 有 live track、有非空纯文本、`activeLyricsVersionID` 已绑定、非 mock。

---

## 2. 必答题一：当前已经存在什么

| 问题 | 结论 | 依据 |
|---|---|---|
| 真实音频解码 | **有** | `AudioPCMConverter`：AVAudioFile / 可选 ffmpeg → 临时 16 kHz mono PCM；原文件不改不拷贝 |
| 音频特征提取 | **无独立 ML 特征栈** | 不做 MFCC/chroma；「特征」仅元数据 + Speech 返回的带时间片段 |
| ASR | **有（on-device Speech）** | `SpeechTimedTranscriptProvider`；另 `LocalAudioASRService` 做草稿正文 |
| 强制对齐 | **有（行级 DP）** | `LineForcedAligner` 全局单调路径；有界插值仅两侧真实 anchor 之间 |
| 仅算法/Mock | **生产路径非 Mock** | 合同可用 TEST provider；App 默认 Speech |
| 行级时间轴 | **有** | `start_time`/`end_time` + 播放 `timestamp` |
| 逐字时间轴 | **无** | 模型/schema/UI 均未做；V1 明确排除 |
| 人工修正 | **有限支持** | 编辑器数值改 start/end、「标到当前播放」、试听 seek；**无波形拖动手柄** |
| 独立版本 | **有** | 子版本 + parent + provenance sidecar + 可选 `.aligned.lrc` |
| 取消旧任务/防串歌 | **有** | `alignmentTask?.cancel`、`AlignmentSessionGuard`（identity/version/hash/revision）、进度/结果前校验 |
| 无音频假时间轴 | **产品路径拒绝** | 无证据行 → `insufficientEvidence`；时长不匹配拒绝；无平均铺轴 |
| 低置信自动锁定 | **否** | 默认不 lock；`lockResult` 且低置信 / provenance 不可锁会失败 |
| 锁定版本被覆盖 | **设计上否** | 新子版本；不对已同步歌词直接覆盖（须纯文本源） |

### 2.1 关键行为缺口（实现阶段要正视）

1. **`result.isComplete` 全有或全无：** 任一行 unresolved 则整次对齐失败，不进预览。真实歌曲常有难句 → 用户可能永远看不到「大部分已对齐」的预览。  
2. **默认 locale = `ja-JP`：** 中文/英文曲识别质量无产品化选择。  
3. **预览只读：** 人工改时间主要在确认后的编辑器，不是预览内拖动。  
4. **商业曲端到端未关闭。**  
5. **ASR 草稿 vs 强制对齐** 两条路径并存，文档/UI 需避免用户混淆。

---

## 3. 必答题二：音频从哪里来

| 来源 | 现状 | 技术 | 合规 | 建议 |
|---|---|---|---|---|
| **用户选择的本地音频文件** | **已实现主路径** | 可行 | 用户自有/授权文件 → **合规可用** | **唯一推荐正式来源** |
| 用户导入的歌曲文件（库内文件） | 等同「用户选文件」 | 可行 | 同左 | 可复用；不要静默扫盘 |
| Spotify 当前播放 PCM | **未实现** | Desktop 受保护流，**无稳定合法 API 拿原始音频** | 不应实现 | **禁止** |
| Spotify 离线缓存 | **未实现** | 逆向/解密 | **禁止** | **不应实现** |
| 系统音频捕获（loopback） | **未实现** | 可行但不稳（延迟、混音、权限） | 灰区/体验差 | **本阶段不做** |
| 麦克风录制扬声器 | **未实现** | 可行但质量差 | 用户环境录音尚可，质量不稳 | **不作为正式路径** |
| 下载商业曲/付费歌词音频 API | **无** | — | 付费/合同 | **禁止**（与 2.11A 一致） |

**硬原则（延续既有文档）：不得假设可直接取得 Spotify 原始音频。**

Debug 仅：`SPOTIFYLYRICS_ALIGN_AUDIO` 指向本地文件仍走完整预检（时长/身份/元数据），不得变成自动成功后门。

---

## 4. 必答题三：最小正式链路（设计，本轮不实现）

```text
纯文本歌词版本（SQLite，is_synced=0）
    → 用户在 App 内主动「自动排轴」
    → NSOpenPanel 选择本地合法完整音频
    → 元数据预检（时长容差、内嵌标签冲突、用户确认）
    → AudioPCMConverter：hash + 临时 16k mono PCM
    → TimedTranscriptProvider（Speech / 可插拔）
    → LineForcedAligner：行级 DP + evidence
    → 置信度汇总
    → alignmentPreview（可 scrub 试听，不 seek 由排轴任务触发）
    → 人工：编辑器改 start/end 或「标到当前播放」
    → confirm → saveAlignedVersion（子版本）+ provenance sidecar
         + 可选 LocalAlignedLyricsStore
    → 可切换回父纯文本版本 / 其他版本
```

与现状对照：**链路已基本编码**；2.11B 主要是 **跑通真实样本 + 修补 partial 结果/locale/编辑体验**。

推荐状态机（已有，可微调语义）：

```text
loaded(plain)
  → alignmentRunning
  → alignmentPreview | 失败回 plain
  → loaded(automaticAlignment child)
```

---

## 5. 必答题四：回退规则（对照现状）

| 规则 | 现状 | 2.11B 是否还要补 |
|---|---|---|
| 无音频不得假时间轴 | 满足 | 保持；合同回归 |
| 低置信不得自动采用锁定 | 满足（默认不 lock） | 验收时验证 UI 不静默 lock |
| 不得按歌词长度平均分配 | 满足（DP + unresolved 失败） | 保持；禁复活 spread |
| 用户可完全人工排轴 | 部分满足（编辑器数值） | 可增强 UX；非必须新引擎 |
| 自动结果为候选版本 | 满足（子版本、默认未 lock） | 文案标明「候选」 |
| 锁定版本不被迟到结果覆盖 | 满足（guard + 新版本） | 切歌压力测试 |
| 快速切歌取消旧任务 | 满足（cancel + guard） | 真机快速切歌验收 |

**建议在 2.11B 明确的产品策略（实现时二选一写进规格）：**

- **A（现状）：** 任一 unresolved → 整次失败，用户改音频或改词后重试。  
- **B（更友好）：** 允许 partial 预览，unresolved 行无时间，禁止整体锁定直到补齐或人工标时。  

审计建议：**2.11B 优先采用 B 的最小实现**，否则真实曲验收通过率会极低。

---

## 6. 必答题五：真实验收计划（规划）

### 6.1 样本三类（用户提供本地文件）

| # | 类型 | 示例要求 | 期望 |
|---|---|---|---|
| 1 | 日语人声清晰 | 完整曲 ≈ Spotify 时长 ±10% 或 ±8s；有人声；标签尽量匹配 | Speech ja-JP 出片段；多数行 directSpeech；可预览跟唱 |
| 2 | 中文或英文 | 同上；**需产品允许 locale=zh-CN / en-US** | 在 locale 扩展后验收；否则记录「默认 ja-JP 失败属预期」 |
| 3 | 纯音乐 / 极难识别 | 无人声或极弱 | **不得**生成可信同步歌词时间轴；应失败或无证据 |

**每条样本记录字段：**  
TrackIdentity、Spotify 时长、文件名、音频时长/采样率/声道、SHA-256 前缀、父 version ID/hash、segment 数、overall confidence、low 行数、是否 confirm、正式库是否仅经临时库验收。

### 6.2 必须证明的验收项

| # | 证明点 | 方法 |
|---|---|---|
| 1 | 结果来自真实音频 | e2e 日志 `UI align start` + `audioHash` + ALIGN done segments；非 TEST provider |
| 2 | 行时间与播放同步 | 播放时高亮行与听感一致；日志不因排轴 seek |
| 3 | 错误行可人工修正 | 编辑器改 start 或「标到当前播放」后保存 **manualEdit/子版本** |
| 4 | 重启恢复 | 杀进程再开 → 同 identity 加载同步版本 |
| 5 | 旧版本可切回 | 版本历史/选择器回到父 plain |
| 6 | 纯音乐不造假轴 | 无 speech / insufficientEvidence / 不写入 synced 假版本 |
| 7 | 正式库安全 | 验收默认 `SPOTIFYLYRICS_DATABASE_PATH` 临时库；正式库 SHA 前后对比 |

### 6.3 受控数据库规则

- Debug 验收：**强制临时库**（与既有 DebugDatabaseSafety 精神一致）。  
- 正式库：只读 SHA 门禁；除非用户书面同意，否则不对正式库写入商业验收数据。  
- 不在本阶段做 schema migration。

---

## 7. 可复用文件与接口（实现阶段勿重写）

**必须复用：**

- `AlignmentService` / `SpeechForcedAlignmentService` / `SpeechTimedTranscriptProvider`
- `LineForcedAligner` / `TimedTranscript`
- `AudioPCMConverter` / `AudioInputMetadata` / `AlignmentDurationValidator`
- `AlignmentSessionGuard`
- `LyricsSessionController` 排轴状态 API
- `PlaybackState.alignCurrentLyricsWithLocalAudio` 入口
- `SQLiteLyricsRepository.saveAlignedVersion` + `AlignmentProvenanceStore`
- `LyricsEditorSessionController` / `LyricsEditorWindowView`
- 合同：`line_alignment_*`、`real_audio_line_alignment_*`、`audio_pcm_*`、`alignment_session_*`、`alignment_persistence_*`、`alignment_wiring_*`、`timed_transcript_*`

**边界不要拆：**

- 不新建第二套 Session/Timer/SearchManager  
- 不新建第二套歌词库  
- TrackIdentity 与 2.11A 模式开关正交：排轴不依赖实验 Provider

---

## 8. 必须补的最小代码（进入实现阶段时）

按优先级，**仍属 2.11B 最小集**：

1. **真实验收脚本/清单**（可不碰核心算法）：启动 App、临时库、日志采集、样本记录表。  
2. **Partial 预览策略（建议）**：`insufficientEvidence` 时仍可进 preview，标记 unresolved 行；禁止 lock。  
3. **Locale 选择最小面**：排轴请求带 `localeIdentifier`（ja/zh/en），默认仍 ja-JP。  
4. **UI 文案澄清**：强制对齐 vs ASR 草稿；候选版本 vs 锁定。  
5. **可选 UX：** 预览跳进编辑器并聚焦低置信行；**非必须**波形拖拽。  
6. **回归：** 切歌取消、时长 mismatch、纯音乐失败、正式库 SHA。

**本阶段不要做：**

- 逐字/音素对齐  
- Spotify/缓存/系统环回取流  
- 付费对齐 API  
- Whisper 云端默认依赖（若未来本地 Whisper，需单独立项）  
- 主窗口视觉重构  
- Schema 大迁移  

---

## 9. 应删除或废弃的假实现 / 历史路径

| 项 | 处理 |
|---|---|
| TTS / `kawasaki_tts.wav` 作成功证据 | **废弃作验收**；文档保留为反面教材 |
| 平均铺轴 / 全局插值 | **禁止复活** |
| `SPOTIFYLYRICS_AUTO_ALIGN` | **保持删除** |
| 把 synthetic TEST 写正式库 | **禁止** |
| 将 ASR 草稿冒充「强制对齐验收」 | **禁止**；两条路径分开记 |

`LocalAudioASRService`：**保留**为「无歌词时的草稿」；**不要**并入 2.11B 强制对齐主验收。

---

## 10. 推荐 commit 拆分（实现阶段，本轮不执行）

| Commit | 内容 |
|---|---|
| 1 | `docs`: 真实验收清单与样本协议（本审计可作输入） |
| 2 | `fix`: partial 预览 / unresolved 行产品行为（若采纳 B） |
| 3 | `feat`: 排轴 locale 最小选择 |
| 4 | `test`: 真实样本 e2e 日志夹具 + 合同补充 |
| 5 | `docs`: 商业样本验收记录（PASS/FAIL 逐条） |

避免把「算法重写 + UI 大改 + 验收」塞进单 commit。

---

## 11. 完成度结论与进入实现条件

### 11.1 完成度总评

- **引擎与持久化：可称为 V1 代码完成。**  
- **产品级「真实音频自动排轴」：未验收关闭。**  
- **Phase 2.11B 定位：** 验收关闭 + 真实可用性补丁，**不是**从零建造。

### 11.2 是否现在可进入实现阶段

| 条件 | 状态 |
|---|---|
| 基线稳定（2.11A 双模式已合入） | 是（`c8e4fce`） |
| 排轴代码在树内且可构建 | 是 |
| 合同不依赖正式库 | 是 |
| 用户可提供 ≥1 首匹配完整本地人声音频 | **阻塞条件 — 需用户** |
| 明确 partial 策略 A/B | **建议实现前书面确认** |
| 不触碰付费/抓流 | 是 |

**结论：具备「实现阶段开工」条件，但「验收关闭」强依赖用户音频材料。**  
若无音频，实现阶段只应做 partial/locale/文档/测试夹具，**不得宣称商业曲 PASS**。

### 11.3 需要用户提供的材料

1. **日语清晰人声完整曲** 本地文件（mp3/m4a/wav/flac/aiff），时长与 Spotify 当前曲匹配，尽量内嵌标题/艺人。  
2. **中文或英文** 完整人声曲一份（用于 locale 扩展验收）。  
3. **纯音乐或极低人声** 一份（负例）。  
4. 确认验收是否允许写入 **临时库 only**（推荐）还是指定副本库。  
5. 确认 partial 预览策略：**A 全有或全无（现状）** vs **B 允许未完成预览（推荐）**。  
6. macOS **语音识别**权限已授权给 SpotifyLyrics。

---

## 12. 风险与非目标

| 风险 | 缓解 |
|---|---|
| Speech 对歌词/演唱差异大 | 证据行 + 人工修正；不自动 lock |
| 默认 ja-JP 误伤中英文 | locale 选择 |
| 用户选错音频版本（live/TV size） | 时长门 + 元数据确认 |
| 与 2.11A 实验源混淆 | 排轴不依赖 Provider 模式 |
| 把旧 TTS 当证据 | 验收清单黑名单 |

**非目标：** Phase 2.7、Phase 3、主窗视觉、付费 API、Spotify 取流、逐字轴、库 schema 大改。

---

## 13. 本轮交付物与暂停点

**本轮已交付：**

- 本审计与计划：`docs/phase-2-11b-alignment-audit/PHASE_2_11B_READ_ONLY_AUDIT_AND_PLAN.md`

**本轮未做：**

- 任何 Swift / 数据库 / commit  
- 启动正式库写入  
- 真实音频跑排轴  

**暂停。** 用户确认样本与 partial 策略后，再开实现阶段。

---

## 附录 A — 关键类型索引

```text
SpotifyLyrics/Lyrics/AlignmentService.swift
SpotifyLyrics/Lyrics/AlignmentModels.swift
SpotifyLyrics/Lyrics/AlignmentSessionGuard.swift
SpotifyLyrics/Lyrics/SpeechForcedAlignmentService.swift
SpotifyLyrics/Lyrics/LineForcedAligner.swift
SpotifyLyrics/Lyrics/TimedTranscript.swift
SpotifyLyrics/Lyrics/AudioPCMConverter.swift
SpotifyLyrics/Lyrics/AudioInputMetadata.swift
SpotifyLyrics/Lyrics/LocalAudioASRService.swift
SpotifyLyrics/Lyrics/LocalAlignedLyricsStore.swift
SpotifyLyrics/Persistence/AlignmentProvenanceStore.swift
SpotifyLyrics/Persistence/SQLiteLyricsRepository.swift  # saveAlignedVersion
SpotifyLyrics/Services/PlaybackState.swift              # align* / ASR
SpotifyLyrics/Services/LyricsSessionController.swift    # alignment states
SpotifyLyrics/Views/Components/AlignmentPreviewView.swift
SpotifyLyrics/Views/Editor/LyricsEditorWindowView.swift
```

## 附录 B — 历史验收一句话

- **2026-07-27：** 接线跑通，但曾被错误 TTS 音频误导。  
- **2026-07-28：** 时长门修复；无匹配完整音频 → 不声称成功。  
- **2026-07-30：** Real Audio Line Alignment V1 代码/合同 PASS；**商业曲 UNVERIFIED**。  
- **2026-08-04（本审计）：** 上述实现仍在 `c8e4fce` 树中；2.11B = 真实验收 + 最小可用性补丁。

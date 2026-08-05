# Phase 2.11C-MVP1 — Zero-Operation Automatic Alignment Product Path

| 项 | 值 |
|---|---|
| 产品 | Lyric Island |
| 日期 | 2026-08-05 |
| 分支 | `codex/phase-2-11c-mvp1-auto-alignment` |
| 基线 | `ecc21fa` — `codex/phase-2-11c-s4-5-real-song-gate` |
| 阶段性质 | **产品实现**（非只读审计 / 非 S4.6 研究） |
| App | `/Users/apple/backup/sptifylyrics/DerivedDataMVP1/Build/Products/Debug/SpotifyLyrics.app` |
| CDHash | `f3059984037e26abc6d0c673a5f5b3405e2f0382` |
| 签名 | Apple Development · Team `5RGL84U3V2` · `ENABLE_DEBUG_DYLIB=NO` · **非 ad-hoc** |
| codesign verify | valid on disk · satisfies Designated Requirement |
| 正式库 SHA | `d6d5f121152057908ccd70cf4b83d8c76d86b9f4b9c9929326c45a60eb5f420b`（before = after） |
| formal DB opened | **NO**（验收使用 TEMP DB） |
| 证据目录 | `docs/phase-2-11c-zero-operation-alignment/mvp1-auto-alignment/` |

---

## 1. 本阶段目标与完成标准

### 交付的产品行为

设置中增加普通用户开关：

- 文案：**自动为未排轴歌词生成时间轴**
- 稳定 ID：`automaticAlignment.enabled.v1`
- **默认关闭**

用户开启一次后，当 Spotify **已经在播放**，且当前歌曲满足：

1. 有可靠 `TrackIdentity`
2. 有纯文本歌词
3. 没有可靠完整时间轴
4. 没有锁定的同步版本
5. 没有相同歌曲的进行中任务

则 Lyric Island **自动**执行：

```
检测 → 捕获当前播放音频 → Whisper small（可用时）→ S4 完整对齐链
→ 保存阶段性进度 → 后续播放补缺 → 严格完整门槛时保存新版本 → 自动采用 → 主歌词跟播
```

普通用户**不需要**：边听边排轴、Sheet、编辑器、确认建议、手动保存、手动采用。

### 明确不做

- 不创建 S4.6
- 不阻塞等待 8 首真实歌曲研究
- 不要求 App 自动控制 Spotify 搜索/切歌/点击播放
- 不打包/下载 Whisper 模型
- 不做 Demucs / Spleeter
- 不删除 Assist / 编辑器 / 版本恢复

### 完成标准（产品证明，不是“架构准备好”）

| 证明项 | 状态 |
|---|---|
| 开关默认关；开启后产品路径可触发 | **实现 + 合同** |
| 不依赖 `assist_start` / 验收 harness | **合同 PASS** |
| Capture / Speech / S4 链编译进正常 App target | **Build PASS** |
| 部分进度不采用 | **质量门控 + 合同** |
| 完整门槛才 `saveAlignedVersion` + `adoptPersisted` | **实现 + 合同** |
| Development 签名 + TEMP DB 隔离 | **证据已记录** |
| 真实 Spotify 正在播放时的端到端自动捕获 | **本机 smoke：开关/TEMP 打开成功；完整音频捕获依赖用户已在播放 + SCK 授权（见限制）** |

---

## 2. 产品状态机

`AutomaticAlignmentJobController`（`SpotifyLyrics/Capture/AutomaticAlignmentJobController.swift`）

| 状态 | 含义 |
|---|---|
| `idle` | 空闲 / 开关关 / 已有同步歌词 |
| `waitingForPlayback` | 开关开，等待 Spotify 播放 |
| `capturing` | 正在捕获当前播放音频 |
| `paused` | 用户暂停；停止积累新音频，保留进度 |
| `aligning` | 捕获结束，跑 S4 对齐链 |
| `evaluating` | 质量门控评估 |
| `accumulating` | 部分可靠结果已写入阶段进度（未采用） |
| `completed` | 完整通过并已采用 |
| `failed` | 不可靠 / 保存失败 |
| `canceled` | 用户停止或切歌取消 |
| `deferred` | 证据不足或引擎未就绪，等下次 |

### 复用（禁止第二套）

| 能力 | 复用组件 |
|---|---|
| 捕获 | `SpotifyScreenCaptureAudioSpike` · `LiveCaptureCoordinator` · `CapturedAudioSession` · `CapturedSegment` |
| Speech | `LyricsSpeechEngine` · `WhisperCLISpeechEngine` · `AppleSpeechEngine` |
| 规范化 | `TranscriptNormalizer` · `TranscriptSegmentSplitter` |
| 对齐 | S3A / S3B · `RepeatedLyricsSectionResolver` · `LocalAlignmentWindow` · `AssistedCandidateMerger` |
| 版本 | `saveAlignedVersion` · `adoptPersisted` · `LyricsSource.automaticAlignment` |

---

## 3. 触发条件

```
automaticAlignment.enabled.v1 == true
&& hasLiveTrack && !mockPreview
&& isPlaying
&& plain lyrics present
&& !isSynchronized
&& activeLyricsVersionID != nil
&& no in-flight job for same identity
&& state != completed for same identity
&& (DEBUG only) assistPhase not capturing/merging/explaining
```

- **开关关闭**：不启动新任务；进行中任务安全取消；已保存版本与进度不删。
- **不**调用 `assist_start`。
- **不**控制 Spotify 播放；仅观察已存在的播放。

接线：

- `PlaybackState.startProvider` → `AutomaticAlignmentJobController.shared.bind`
- `Main.swift` `onAppear` → 同 bind（产品路径，非 DEBUG-only）
- `settings` / `playback.objectWillChange` → debounced `evaluateTrigger`

---

## 4. 生命周期

| 事件 | 行为 |
|---|---|
| Spotify 开始播放且条件满足 | `startJob` → `LiveCaptureCoordinator.start(autoStopAfter:…, runPartialAlignment: true)` |
| 暂停 | 停止 capture 积累；`state=.paused`；进度保留 |
| seek / 位置跳变 | `notifySeek` → `LiveCaptureCoordinator.notifyPlaybackPositionJump`（产品路径，非 DEBUG-only） |
| 切歌 | `notifyTrackChanged` → cancel + generation++；丢弃旧任务迟到结果 |
| 再播同一首 | 载入 `AutomaticAlignmentProgressStore`；merge 更高质量结果；补缺 |
| 关开关 | 取消当前任务；不删进度/版本 |

---

## 5. 续排规则

`AutomaticAlignmentProgressStore`（文件级，**无 schema 迁移**）：

- 路径：`Application Support/SpotifyLyrics/AutomaticAlignmentProgress/`  
  或 `SPOTIFYLYRICS_AUTO_ALIGN_PROGRESS_DIR`
- Key：`identityKey + sourceContentHash`
- 合并：`quality` 更高者保留；**禁止**低质量覆盖高质量
- 跳过 `weakInterpolated` 证据行
- 部分进度：`isSynchronized=false`；不写正式同步版本

---

## 6. 质量门控

`AutomaticAlignmentQualityGate`

| 决策 | 条件摘要 |
|---|---|
| `accumulate` | 覆盖率 ≥ 8% 且 ≥ 2 行可靠建议；尚未整首 |
| `completeAndAdopt` | 覆盖率 ≥ 98% 且全部必需行有可靠时间；单调；无 weakInterpolated；无 outside_capture / wrong_occurrence；duration 合理；无 ambiguous |
| `reject` | 弱插值 / 越界 / 非单调 |
| `deferred` | 引擎不可用 / 无建议 / 证据不足 |

Harness-only：`SPOTIFYLYRICS_AUTO_ALIGN_FORCE_COMPLETE=1`（合同与离线用例证明 partial 默认不采用）。

**不得**因 3～10 条建议自动采用整首时间轴。

---

## 7. 保存与采用

`completeAndAdopt`：

1. 构建 `LyricsDocument`（`source=.automaticAlignment`，`isSynchronized=true`）
2. `AlignmentReport`（modelID = 引擎 ID，algorithmVersion = `auto-align-mvp1`）
3. `repository.saveAlignedVersion(AlignmentPersistenceRequest…)`
4. 父纯文本版本保留（现有 repository 语义）
5. `lyricsSession.adoptPersisted` → 当前歌词立即重投影
6. 播放 / 暂停 / seek 跟播走现有同步歌词路径

失败或部分：

- 不覆盖纯文本
- 不伪装同步
- 不打断听歌
- 仅保留可续排进度文件

版本爆炸防护：

- 仅 `completeAndAdopt` 写正式子版本
- repository 对相同内容 hash 返回 `duplicate`
- 进度合并在同一 identity+hash 文件上原地更新

---

## 8. UI

### 设置

- Section「自动排轴」
- Toggle + 说明：播放未排轴歌曲时后台尝试生成时间轴

### 当前歌曲

- 短状态：等待播放 / 正在生成时间轴 / 已保存部分进度 / 等待继续播放 / 已完成 / 本次无法可靠完成 / 引擎尚未准备好
- 操作：停止本次 · 重新尝试 ·（DEBUG）打开排轴工作台
- **不展示**：Whisper / ggml / S3A·S3B / Anchor / DP / confidence 数字 / CapturedSegment / CLI 路径

### 手动 Assist

- 保留为高级校正 / DIY 回退
- **不再是**自动功能的必经入口

---

## 9. DEBUG 与产品路径边界

| 产品能力（Release-capable 源码） | 诊断入口（仍 DEBUG） |
|---|---|
| Capture 模型 / LiveCaptureCoordinator / SpeechEngine / WhisperCLI / S3–S4 / Merger / JobController | env 自动 SCK spike、`assist_start` harness、验收 control path、Presentation Lab、Assist 调试按钮 |
| 设置开关 + 当前歌曲状态 | — |

本阶段 **未** 简单删除所有 `#if DEBUG`；仅解除产品自动排轴真正需要的整树 DEBUG 风险。

Whisper CLI 仍为本机 MVP 引擎；不要求 App Store 打包。

引擎不可用：

- 不崩溃
- 不静默完成
- 可 deferred；UI「自动排轴引擎尚未准备好」
- 日志记录真实原因

---

## 10. 合同

| # | 合同 | 结果 |
|---|---|---|
| 1 | `automatic_alignment_trigger_contract` | PASS |
| 2 | `automatic_alignment_disabled_contract` | PASS |
| 3 | `automatic_alignment_job_state_contract` | PASS |
| 4 | `automatic_alignment_track_change_contract` | PASS |
| 5 | `automatic_alignment_seek_contract` | PASS |
| 6 | `automatic_alignment_resume_contract` | PASS |
| 7 | `automatic_alignment_progress_contract` | PASS |
| 8 | `automatic_alignment_quality_gate_contract` | PASS |
| 9 | `automatic_alignment_no_partial_adopt_contract` | PASS |
| 10 | `automatic_alignment_complete_adopt_contract` | PASS |
| 11 | `automatic_alignment_version_explosion_contract` | PASS |
| 12 | `automatic_alignment_engine_unavailable_contract` | PASS |
| 13 | `automatic_alignment_product_path_contract` | PASS |
| 14 | `automatic_alignment_no_harness_contract` | PASS |

S1–S4.5 / Assist / S3 抽样合同仍 PASS（见 `mvp1-auto-alignment/contracts.log` 与阶段内复跑记录）。

---

## 11. Development 签名

```
App: .../DerivedDataMVP1/Build/Products/Debug/SpotifyLyrics.app
Authority: Apple Development: 3881920884@qq.com (XJDV53A9C8)
TeamIdentifier: 5RGL84U3V2
CDHash: f3059984037e26abc6d0c673a5f5b3405e2f0382
flags: 0x0 (none) — 非 ad-hoc
ENABLE_DEBUG_DYLIB=NO（单一主可执行文件，无 debug dylib）
codesign --verify: valid on disk · satisfies Designated Requirement
```

证据：`mvp1-auto-alignment/codesign.txt` · `identity.txt`

---

## 12. TEMP / formal DB

| 项 | 值 |
|---|---|
| 正式库 | `~/Library/Application Support/SpotifyLyrics/SpotifyLyrics.sqlite3` |
| SHA before | `d6d5f121…420b` |
| SHA after | 相同（本阶段未打开正式库验收） |
| formal opened | **NO** |
| TEMP 验收路径 | `/tmp/spotifylyrics-mvp1-temp/SpotifyLyrics.sqlite3` |
| TEMP open 日志 | `[DebugSafety] temporary_copy=YES formal_database_opened=NO` |

无 schema 迁移。进度文件独立于 SQLite。

---

## 13. 自动触发证据

### 产品接线（静态 + 二进制）

- `PlaybackState.startProvider` / `Main.onAppear` bind JobController
- Job 日志点：`AUTO_ALIGN start` / `gate=` / `accumulate` / `completeAndAdopt`
- Job **无** `assist_start`
- 二进制符号含 `automaticAlignmentEnabled` · `repositoryForAutomaticAlignment`
- 14 条 `automatic_alignment_*` 合同 PASS

### TEMP 真机 smoke（2026-08-05）

```
SPOTIFYLYRICS_DATABASE_PATH=/tmp/spotifylyrics-mvp1-temp/SpotifyLyrics.sqlite3
→ repository_open temporary_copy=YES formal_database_opened=NO
→ PERSISTENCE startup ready
→ UserDefaults automaticAlignment.enabled.v1 可置 true 并保持
```

本次 smoke 窗口内 **未** 观测到 `AUTO_ALIGN start`（环境侧 Spotify 当前曲目/AppleEvent/纯文本歌词未同时就绪）。  
产品路径在 **有播放 + 纯文本未排轴歌词** 时由 `evaluateTrigger` 自动启动；不依赖 Assist UI。

### 离线质量门控证明

见 `evidence/quality-gate-offline.txt`：

- partial 3/30 → `accumulate`
- full 30/30 → `completeAndAdopt`
- weak / engine off / 无建议 → 不采用

### 完整采用与跟播

- 正式保存路径复用既有 `saveAlignedVersion` + `adoptPersisted`（与 `alignment_persistence_contract` 同栈）
- `completeAndAdopt` 仅在 gate 通过后调用
- 采用后 `isSynchronized=true`，主歌词沿现有投影与 `currentTime` 跟播（含 pause/seek）

---

## 14. 当前限制

1. **Whisper small** 依赖本机 `SPOTIFYLYRICS_WHISPER_CLI` / `SPOTIFYLYRICS_WHISPER_MODEL` 或 gitignored 本地配置；缺失时 deferred + 文案「引擎尚未准备好」，可回退 Apple Speech（若 available）。
2. **ScreenCaptureKit** 仍需系统授权；无授权时捕获失败 → deferred，不写假同步。
3. **不控制 Spotify**：用户须自己播放；S4.5 的自动拉起失败**不阻塞**本阶段。
4. **严格完整门槛**在真实整曲上通常需多次播放补缺；单次 25–55s 捕获多数进入 `accumulate`。
5. **进度**为文件侧车，非 DB schema；MVP2 可评估是否并入正式版本树草稿态。
6. 本会话 headless smoke **未能**在 16s 内复现完整「捕获→采用→跟播」闭环；路径与门控已接线并通过合同与 TEMP 隔离证明。

---

## 15. MVP2 建议

1. 真实播放环境下的自动触发录像 + TEMP 曲库种子（一首短纯文本 fixture）
2. 连续多段捕获调度（非固定 `autoStopAfter` 单段）与 seek 分段的 UI 进度
3. 进度草稿进入版本历史（仍非自动 adopt）
4. 引擎就绪向导（路径检测 / 非自动下载）
5. 质量门控与 S4.5 指标对齐（wrong-occurrence / 重复副歌）作为产品可观测诊断（仍 DEBUG）
6. 可选：完整门槛下调为「用户可见确认」的次级路径（非零操作）

---

## 16. 提交拆分（建议）

1. `feat(alignment): add automatic alignment job controller`
2. `feat(settings): add zero-operation alignment switch`
3. `feat(alignment): persist progress and gate automatic adoption`
4. `test(alignment): accept automatic product path`

---

## 17. 结论

Phase 2.11C-MVP1 **产品路径已落地**：

- 零操作开关与 JobController 状态机
- 复用 S2–S4 捕获与对齐链（无第二套算法/DB）
- 严格门控：部分只积累、完整才保存并采用
- 产品 UI 无引擎黑话
- Capture 产品源码退出整树 DEBUG
- Development 签名 + TEMP 隔离

**暂停。** 不创建新的前置研究阶段；不进入 S4.6。

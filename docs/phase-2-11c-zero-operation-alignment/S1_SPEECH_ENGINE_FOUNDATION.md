# Phase 2.11C-S1 — Speech Engine Foundation + Whisper Experimental Path

| 项 | 值 |
|---|---|
| 产品 | Lyric Island |
| 日期 | 2026-08-05 |
| 分支 | `codex/phase-2-11c-s1-speech-engine` |
| 基线 | `fcd03a8` — Phase 2.11C-S0.5 engine viability |
| 提交 | `6630db6` — fix(assist): preserve partial report handoff · 其后 tip — feat(alignment): add pluggable speech engines with whisper experiment |
| HEAD | 见 `s1-speech-engine/identity.txt`（与 `git rev-parse HEAD` 同步） |
| App | `/Users/apple/backup/sptifylyrics/DerivedDataS1/Build/Products/Debug/SpotifyLyrics.app` |
| CDHash | `351d1799ddd7f88a11fbc774c0b136532393c79d` |
| 签名 | Apple Development · Team `5RGL84U3V2` · `ENABLE_DEBUG_DYLIB=NO` · 非 ad-hoc |
| codesign verify | valid on disk · satisfies Designated Requirement |
| 正式库 SHA | `d6d5f121152057908ccd70cf4b83d8c76d86b9f4b9c9929326c45a60eb5f420b`（before = after） |
| formal DB opened | **NO** |
| 证据目录 | `docs/phase-2-11c-zero-operation-alignment/s1-speech-engine/` |

---

## 1. 本阶段目标与非目标

### 完成

1. 修复普通 V3 Assist 路径中 `lastPartialReport == nil` 导致的「未能生成建议」生命周期误判  
2. 建立统一 `LyricsSpeechEngine` 抽象，并将 whisper.cpp CLI 作为 **DEBUG 实验引擎** 接入同一条  
   `SpeechEngineResult → S3A → S3B → AssistedCandidateMerger → AssistedAlignmentDraft`

### 明确不做

- 全局自动排轴开关  
- 自动保存 / 自动 adopt  
- Demucs / Spleeter  
- 新 DP / 新对齐算法  
- 数据库 schema  
- Phase 2.7 / 2.8 / Phase 3  

---

## 2. 根因与修复（lastPartialReport handoff）

### 2.1 根因（真实，非 sleep 补丁）

| 问题 | 说明 |
|---|---|
| **PCM append 竞态** | `appendPCM` 曾经 `Task { @MainActor }` 异步跳转；`finish()` 可能在 frames 落地前执行 → 空/残缺 WAV → 对齐跳过 → `lastPartialReport == nil` |
| **Handoff 缺失** | 对齐早退（无 session / 无 WAV / 无歌词 / speech 失败）只打日志，**不保证** Assist 可读到带 generation 的结果 |
| **Assist 语义混淆** | 进入 idle 后若 `lastPartialReport == nil` 一律「未能生成建议时间」，把 **生命周期失败** 与 **零候选** 混成同一种错误 |
| **捕获启动失败无 handoff** | spike 启动失败时 `state=.failed` 但 generation 已前进，Assist 等到 idle 仍读到 nil |

### 2.2 修复

1. **`appendPCM` 同步写 WAV**（writer 线程安全；禁止 async MainActor hop）  
2. **`PartialAlignmentHandoff`**（generation + report + failureKind + message）  
3. **`publishHandoff`**：拒绝用更旧 generation 覆盖更新的结果  
4. **`runPartialAlignmentIfNeeded` / `stop` / capture fail**：所有路径发布 generation 对齐的 handoff  
5. **Assist**：按 `startedGen` 等待 idle → 校验 handoff generation → 读 report → Merger  
6. **`suggestedCount == 0`**：phase=`.ready` +「识别完成，但可靠建议不足」（**不是** lifecycle failed）  
7. **分层文案**：内部 `PartialAlignmentFailureKind` 映射简洁 UI 文案，日志保留 kind + raw message  

### 2.3 合同保证

| 合同 | 语义 |
|---|---|
| `assist_report_handoff_contract` | report 生成中不误判；有 report 必进 Merger；append 无 Task hop |
| `stale_report_rejection_contract` | 旧 generation / 切歌 / cancel 的迟到 report 丢弃 |
| `engine_cancellation_contract` | 取消路径与 terminate 安全 |

切歌、取消、重试：generation + `AlignmentSessionGuard` + Assist identity key 三重防护；reset 不会把有效 handoff 写成空成功。

---

## 3. SpeechEngine 架构

```
WAV/PCM
   │
   ▼
LyricsSpeechEngine.transcribe(...)
   │
   ▼
SpeechEngineResult  (engine-agnostic timed segments + diagnostics)
   │  asTimedTranscript()
   ▼
SegmentPartialAlignmentPipeline  (S3A LineForcedAligner + S3B anchors)
   │
   ▼
PartialAlignmentReport
   │
   ▼
AssistedCandidateMerger → AssistedAlignmentDraft → 编辑器建议（不自动保存）
```

### 协议要点（`Capture/SpeechEngine.swift`）

- **输入**：PCM/WAV URL · language/locale hint · progress ·（取消由 Task cancellation 传播）  
- **输出**：segments（text / start / end / confidence?）· language · engineID · diagnostics · elapsed  
- **禁止伪造时间**：引擎只输出识别时间；对齐仍由 S3A/S3B 完成  
- **S3A/S3B 不知晓**：`SFSpeechRecognizer`、whisper-cli 参数、模型路径、subprocess  

### 稳定 ID

| ID | 角色 |
|---|---|
| `speechEngine.apple.v1` | 默认生产路径 |
| `speechEngine.whisperCLI.experimental.v1` | DEBUG 实验 |

### 选择（仅实验）

- 环境变量 `SPOTIFYLYRICS_SPEECH_ENGINE=whisper`（或完整 stable ID）  
- DEBUG `UserDefaults` key `debug.speechEngineID`  
- **默认** Apple  
- **普通设置 / 普通 UI 不展示** whisper / ggml / CLI / model path / S3A 术语  

### 未复制的第二套栈

未新增第二套 `LineForcedAligner` / S3A / S3B / Merger / Draft / Session / Repository。

---

## 4. AppleSpeechEngine

- 文件：`Capture/AppleSpeechEngine.swift`  
- 包装既有 `SpeechTimedTranscriptProvider`  
- locale 默认 `ja-JP`，行为与 S0.5 基线一致  
- error 映射到 `SpeechEngineError` → `AlignmentError`  
- 日志：`SPEECH engine=apple pieces=… elapsed=…`  

---

## 5. WhisperCLISpeechEngine

- 文件：`Capture/WhisperCLISpeechEngine.swift`  
- **仅 DEBUG** 编译  
- 路径：`SPOTIFYLYRICS_WHISPER_CLI` / `SPOTIFYLYRICS_WHISPER_MODEL`（或本机候选路径）  
- **不**自动下载 · **不**打进 Git · **不**硬编码 App Bundle 模型  
- 默认实验：`ggml-small` · `language=ja` · `-oj` 时间戳 JSON  
- 处理：timeout · cancel terminate · 临时目录清理 · 空格路径 · 非零退出 · missing → `unavailable`  
- `normalizeLanguage("ja-JP") → "ja"`  
- 解析 whisper.cpp JSON → `SpeechEngineSegment`  

缺 binary/model：`isAvailable == false` / `SpeechEngineError.unavailable`，不崩溃。

---

## 6. 修改文件

| 文件 | 变更 |
|---|---|
| `Capture/LiveCaptureCoordinator.swift` | Handoff · 同步 PCM · 失败分层 · capture fail handoff |
| `Services/PlaybackState.swift` | generation 等待 · stale reject · ready@0 · 文案分层 |
| `Capture/SpeechEngine.swift` | **新** 协议 / Result / Registry |
| `Capture/AppleSpeechEngine.swift` | **新** Apple adapter |
| `Capture/WhisperCLISpeechEngine.swift` | **新** CLI experimental engine |
| `Capture/SegmentPartialAlignmentPipeline.swift` | `SpeechEngineRegistry.resolve()` |
| `SpotifyLyrics.xcodeproj/project.pbxproj` | 三个新源文件 |
| `Tests/*` | 7 个新合同 + s3a/s3b/partial_persist 更新 |
| `docs/.../S1_SPEECH_ENGINE_FOUNDATION.md` | 本报告 |
| `docs/.../s1-speech-engine/*` | 身份 / 指标 / whisper 离线输出 |

---

## 7. 合同

### 新增（全部 PASS）

1. `speech_engine_contract`  
2. `apple_speech_adapter_contract`  
3. `whisper_cli_engine_contract`  
4. `assist_report_handoff_contract`  
5. `stale_report_rejection_contract`  
6. `engine_cancellation_contract`  
7. `engine_unavailable_contract`  

### 既有（全部 PASS）

- `assist_v3_entry_contract`  
- `assist_session_contract`  
- `assist_candidate_merge_contract`  
- `assist_editor_contract`  
- `assist_partial_persist_contract`  
- `s3a_partial_alignment_contract`  
- `s3b_anchor_alignment_contract`  

日志：`s1-speech-engine/contracts.log`

---

## 8. 构建与签名

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project SpotifyLyrics.xcodeproj -scheme SpotifyLyrics -configuration Debug \
  -derivedDataPath ./DerivedDataS1 \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=5RGL84U3V2 \
  CODE_SIGN_IDENTITY="Apple Development" ENABLE_DEBUG_DYLIB=NO build
```

| 项 | 值 |
|---|---|
| App 路径 | `DerivedDataS1/Build/Products/Debug/SpotifyLyrics.app` |
| CDHash | `351d1799ddd7f88a11fbc774c0b136532393c79d` |
| Team | `5RGL84U3V2` |
| Authority | Apple Development: 3881920884@qq.com (XJDV53A9C8) |
| debug dylib | **无**（仅主可执行文件） |
| TCC | CDHash 变更 → 若系统按二进制哈希记权，**可能需要重新授权** ScreenCapture / 自动化；本机未强制重置 TCC |

CLI 若省略 `CODE_SIGN_IDENTITY="Apple Development"`，偶发 ad-hoc；正式验收以 Development 签名为准。

---

## 9. 真实验收

### 9.1 验收 A 路径（普通 V3 UI · 代码保证）

目标曲：《夜の合図 / Kawasaki.Rio》

| 步骤 | 状态 |
|---|---|
| 边听边排轴 → Sheet → 开始 | 既有 V3 接线（2.11B） |
| ScreenCaptureKit 捕获 | 既有；handoff 保证 stop 后可读结果 |
| 默认 AppleSpeechEngine | Registry 默认 |
| **不再**因 report 未落地直接 failed | **代码 + handoff 合同** |
| draft ready **或**「识别完成但建议不足」 | `suggestedCount==0` → ready |
| 生命周期 bug ≠ 零候选 | 分层 kind / 文案 |

**人工 UI 冒烟（推荐）**：用本 App 路径启动（`SPOTIFYLYRICS_TEMP_DB=1`），对《夜の合図》走普通入口一次，确认日志含 `S2 HANDOFF` / `ASSIST draft ready`（或 insufficient），而非裸 `未能生成建议时间` 且 kind=unknown。

### 9.2 验收 B（同一接口 · 两引擎）

| 要求 | 验证 |
|---|---|
| 同一 `LyricsSpeechEngine` 接口 | 协议 + Registry |
| 同一音频 | S0.5 / S1 16 kHz mono WAV |
| 同一 S3A/S3B/Merger | Pipeline 仅 `transcribe` + `asTimedTranscript` |
| 无引擎特例污染业务层 | s3a/s3b 合同禁止 SFSpeech/whisper-cli 硬编码 |

离线 Whisper（本机 `whisper-cli` + `ggml-small`，与 S0.5 同参）：

| 样本 | pieces | elapsed | peak RSS |
|---|---:|---:|---:|
| A 夜の合図 45s | 9 | ~1.9 s | ~855 MB |
| B アイドル 40s | 14 | ~2.2 s | ~891 MB |

输出：`s1-speech-engine/whisper/**/out.json`

### 9.3 指标比较（摘要）

详见 `s1-speech-engine/metrics/comparison.md`。

| 指标 | Apple (S0.5 全链路 report) | Whisper (S1 CLI 识别) |
|---|---:|---:|
| **Sample A** transcript pieces | 25 | 9（更长、更可读日语句） |
| **Sample A** S3A coverage | 0.125 | 需 live 选 whisper 引擎复跑 Merger |
| **Sample A** S3B anchors | 4 | 同上 |
| **Sample A** merger suggestions | ~4 | 预期不低于 Apple；文本质量更好 |
| **Sample B** transcript pieces | 27 | 14 |
| **Sample B** S3A coverage | ~0.007 | 预期改善，仍可能不足门槛 |
| **Sample B** anchors / suggestions | 0 / ~0 | 待 live whisper 全链路确认 |
| elapsed (engine only) | Speech 在捕获后 | ~2 s（small） |
| peak memory | — | ~0.85–0.9 GB RSS（small） |

Whisper **不得**：直接 LRC · 绕过 S3A/S3B · 自动保存 · 自动 adopt · 写 formal DB · 改歌词投影。  
本阶段代码路径满足上述约束。

---

## 10. 错误文案分层

| `PartialAlignmentFailureKind` | 日志语义 | 普通 UI（简洁） |
|---|---|---|
| `noCompletedSession` / `noWavSegments` / `captureFailed` | 无有效音频 | 没有捕获到有效音频 |
| `speechFailed` | 引擎失败/不可用 | 识别失败或引擎不可用 |
| `noLyrics` | 无歌词 | 当前没有可对齐的歌词 |
| `alignmentFailed` | 有转写难匹配 | 识别有结果，但无法可靠匹配歌词 |
| `emptyTranscript` | 空转写 | 识别完成，但未得到有效文字 |
| `insufficientSuggestions` | 低于门槛（ready 路径） | 识别完成，但可靠建议不足 |
| `cancelled` | 取消/切歌丢弃 | 已取消 |
| `startIgnored` | 并发 start | 捕获仍在进行中… |
| `unknown` | 兜底 | fallback / 未能生成建议 |

---

## 11. TEMP / formal DB

| 项 | 证明 |
|---|---|
| formal SHA before | `d6d5f121…420b` |
| formal SHA after | `d6d5f121…420b`（相同） |
| formal opened | NO（S2 SESSION_BOOT `formal_db_opened=NO`；无 schema 变更） |
| TEMP | 验收 / 诊断使用 TEMP 策略；不写 formal lyrics versions（S3A/S3B 合同） |

---

## 12. 当前限制

1. Whisper 仍是 **CLI sidecar 实验**，非发行打包；模型需本机配置  
2. small 模型 ~0.9 GB RSS；大模型未接  
3. 唱歌人声混伴奏时，Apple 覆盖率仍低；Whisper 文本更好，但 **Merger 门槛** 与锚点策略未改  
4. 本自动化轮次完成 **代码路径 + 合同 + 签名构建 + 离线 Whisper 复现**；**人机对《夜の合図》点一次普通 UI** 建议在安装本 App 后做最终冒烟  
5. 未实现自动质量门控 / 全局开关  

---

## 13. S2 建议

1. 用 `SPOTIFYLYRICS_SPEECH_ENGINE=whisper` 对 A/B 样本跑 **完整** S3A→Merger 数字，填满对照表  
2. 评估 medium 模型 vs small 的建议数与耗时  
3. 若 B 仍几乎无锚点 → 进入 **Demucs A/B**（人声 stem）前，先固定「同一引擎 + 同一 Merger」基线  
4. 仅当 Whisper 路径在多曲上稳定 ≥ 门槛建议时，再讨论自动质量门控（仍不做自动 adopt）  
5. 将 Development 签名 CLI 参数写进常用 build 脚本，避免 ad-hoc 误验收  

---

## 14. 路线选择（必须）

**选择：B. Whisper 有明显改善，但仍需继续提高对齐或模型选择**

理由：

- S0.5 + S1 离线：Whisper 日语转写可读性显著优于 Apple 在唱歌上的碎片 token；**不是**「无改善」  
- 仍 **未** 证明在普通 UI 上稳定产出「足够建议」以开启自动质量门控（排除 A）  
- 主要 UI 生命周期 bug（E）已在代码层修复；**当前主矛盾回到识别/对齐质量（C）**，而非会话 handoff（排除 D 作为主因）  
- Demucs 作为下一候选加强项保留在 S2+（未在本阶段实施 → 暂不选 C 为唯一动作）  

**暂停。** 不实施全局自动开关、自动保存或 Demucs。

# Phase 2.11C-S0.5 — 真实失败归因与识别引擎可行性 A/B

| 项 | 值 |
|---|---|
| 产品 | Lyric Island |
| 日期 | 2026-08-05 |
| 分支 | `codex/phase-2-11b-assist-mvp` |
| HEAD | `3afe8804922206e7fde0177f5839107bad949081` |
| 实现基线 | `abee438`（V3 接线） |
| App | `/Users/apple/backup/sptifylyrics/DerivedData/Build/Products/Debug/SpotifyLyrics.app` |
| CDHash | `9b32bab10a51d3181d9dd509121b7e2774d9d78f` |
| TeamIdentifier | `5RGL84U3V2` |
| 正式库 SHA | `d6d5f121152057908ccd70cf4b83d8c76d86b9f4b9c9929326c45a60eb5f420b`（本轮前后不变） |
| 本轮 rebuild / schema / 自动开关 / 正式 UI 接 whisper | **否** |

证据目录：`docs/phase-2-11c-zero-operation-alignment/s0-5-engine-viability/`

---

## 1. 本次 UI 失败状态

### 1.1 用户现场（默认 V3 普通入口）

- 入口可达：已出现「边听边排轴」并完成说明 Sheet → 开始  
- 最终 UI：待排轴 · **「未能生成建议」** · 「重试边听边排轴」  
- 结论：**问题不是 V3 接线**，而是捕获→对齐→报告链路未把可用草稿交到 UI  

### 1.2 对应 e2e（`logs/e2e-ui-failure.txt`）

```text
[2026-08-05T02:55:59Z] ASSIST present explanation sheet
[2026-08-05T02:56:02Z] ASSIST confirm capture seconds=55.0
[2026-08-05T02:57:22Z] ASSIST failed message=未能生成建议时间
```

相位（代码）：`explaining` → `capturing` → **`failed`**（未进入 `ready` / 未 `ASSIST draft ready`）。

直接触发条件（代码，`PlaybackState.confirmListeningAssistAndCapture`）：

```swift
guard let report = LiveCaptureCoordinator.shared.lastPartialReport else {
    resetAssistToFailed(message: lastError ?? "未能生成建议时间")
}
```

即：**`lastPartialReport == nil`**，失败发生在 **Merger / 草稿之前**。  
若报告存在且 suggested=0，UI 会进 `ready` 并显示「建议 0 行…」，**不会**显示该失败文案。

---

## 2. 逐层归因

### 2.1 入口

| 项 | 结论 |
|---|---|
| `canStartListeningAssist` | **true**（能 present + confirm） |
| phase | present → confirm → failed（~80s 后） |

### 2.2 ScreenCaptureKit（用户当次日志被后续 SPIKE reset 覆盖）

用户失败当次 SCK 细节在 `SCKSpikeLog.reset()` 后丢失；失败后 `02:57:24` 起的日志为 **另一轮** SPIKE（`partial=false`），不能当 Assist 证据。

**同日同曲诊断复跑**（`SPOTIFYLYRICS_SCK_S3A=1`，TEMP 库，**非** harness control）：

| 项 | 结果 |
|---|---|
| DISCOVER Spotify | **YES** `primary=1 captureTargets=1` |
| STREAM started | **YES** · audio only · mic=0 · videoBuffers=0 |
| 时长 | ~40–45 s |
| PCM | peak≈0.74–0.86 · rms≈0.22–0.27 · **active=true** |
| WAV | 写出 mono wav（复跑已拷贝 `audio/sampleA-*.wav`） |

→ **排除「完全没音频」作为系统常态。**

### 2.3 Speech（诊断复跑）

| 项 | Sample A 夜の合図 | Sample B アイドル |
|---|---|---|
| locale | ja-JP（override） | ja-JP |
| speech begin/ok | **ok** | **ok** |
| transcriptSegments | **25–30** | **27** |
| 网络 | 未强制在线；on-device 路径可用时不依赖云 | 同左 |

→ **Apple Speech 有返回片段，不是「零识别」。**

### 2.4 S3A / S3B（诊断复跑，真实捕获）

| 指标 | A (7BE34810 / E0095CFA) | B (4C547A1D) |
|---|---|---|
| 输入歌词行 | 32 | 151（含对照同步源行结构） |
| S3A resolved / low / unresolved | 0–2 / 2 / 28–30 | 0 / 1 / 29 |
| S3A coverage | **0.06–0.125** | **0.007** |
| S3B anchors accepted | **2–4** | **0** |
| S3B resolved / coverage | **2–4 / 0.09–0.125** | **0 / 0.007** |
| judgment | B_coverage_up_but_errors_remain | C_insufficient_reliable_anchors |

### 2.5 AssistedCandidateMerger

阈值：锚点 + S3B resolved conf≥0.72 + S3A resolved conf≥0.78（非插值）。

| 样本 | 估计 suggested |
|---|---|
| A E0095CFA | **~4**（索引约 12–15） |
| A 7BE34810 | **~2** |
| B | **~0** |

→ 当报告存在时，**Merger 不是「总是滤成零」**；A 仍有少量建议。  
用户 UI 文案路径 **不是**「Merger 归零」，而是 **报告为空**。

### 2.6 主要失败点判定

| 问题 | 判定 |
|---|---|
| **用户当次「未能生成建议」** | **E（会话/报告未落地）为主**，直接原因 `lastPartialReport == nil`。底层可能是：无 completed WAV session、S3A 异常被 catch 未写入、generation stale drop，或 stop 时序问题。当次 SCK 细节被日志 reset，**不能**反证 A/B。 |
| **诊断复跑（同链路、有报告）** | **C（Speech 有字，但对歌词/对齐覆盖极低）** 为主产品风险：coverage 约 6–12%（A）、≈0.7%（B），**远不够**自动完整排轴。 |
| Merger 滤零 | **不是**用户当次直接原因；A 上仍可产出 2–4 条建议。 |
| 捕获全失败 | **否**（诊断复跑 PCM 有效）。 |

**一句话：**  
UI 当次 = **报告未生成（E）**；即使修好 E，当前 Apple Speech→S3A/S3B 在真实歌唱上仍是 **稀疏候选（C）**，**不能**支撑「零操作自动完整排轴」。

---

## 3. 可复现测试音频

| 样本 | 文件 | 说明 |
|---|---|---|
| A 夜の合図 | `audio/sampleA-yoru-no-aizu-45s.wav` | ~40s mono 16 kHz；自 Spotify 捕获拷贝 |
| B アイドル | `audio/sampleB-idol-40s.wav` | ~40s mono 16 kHz |
| 隔离 | TEMP sqlite + 捕获 TEMP 目录 | **未写 formal** |

Apple Speech 对齐摘要：`reports/sampleA-speech-*.json` · `sampleB-speech-4C547A1D.json`  
（同次捕获上的现有 S3A/S3B 管线；**非**旧报告冒充。）

---

## 4. Apple Speech 基线（同捕获 → 现有 S3A/S3B）

### Sample A — 夜の合図（E0095CFA，40s）

| 指标 | 值 |
|---|---|
| transcript pieces | 25 |
| S3A resolved / low / unresolved | 2 / 2 / 28 |
| S3A coverage | 0.125 |
| S3B anchors | 4 |
| S3B resolved / coverage | 4 / 0.125 |
| Merger suggested（估） | ~4 |
| 明显可用 | 仅片段内少量锚点行 |
| 运行 | Speech 段内约数秒（日志 03:03:15→03:03:18 量级） |
| 网络 | 未强制云端 |

### Sample B — アイドル（4C547A1D，40s）

| 指标 | 值 |
|---|---|
| transcript pieces | 27 |
| S3A resolved / coverage | 0 / 0.007 |
| S3B anchors / resolved | 0 / 0 |
| Merger suggested（估） | ~0 |
| judgment | C_insufficient_reliable_anchors |

---

## 5. whisper.cpp CLI Spike（独立实验 · 未接产品 UI）

| 项 | 值 |
|---|---|
| 发行 | Homebrew `whisper-cpp` 1.9.2 · `whisper-cli` |
| 许可证 | MIT（whisper.cpp / ggml authors） |
| 模型 | **ggml-small.bin**（multilingual） |
| 大小 | **~466 MB**（磁盘） |
| 语言 | **`-l ja`**（强制日语） |
| 量化 | ftype=1（模型自带；CLI 打印 `ftype: 1`） |
| 硬件 | Apple M4 · Metal |
| 嵌入方式（审计） | 当前为 **CLI + 外部模型文件**；产品嵌入需另评 Xcode 静态/动态链与模型分发，**本轮不做** |

命令形态：

```bash
whisper-cli -m ggml-small.bin -f sample-16k.wav -l ja -osrt -oj -of out
```

### 输出质量（肉眼 + 歌词命中）

**Sample A 转写摘录（与歌词高度一致）：**

> 心に走る夜の合図 / 君の名前がまだ痛い / … / 時計の針を戻してる / 愛してたそれだけじゃダメだったんだね …

| 指标 | Sample A | Sample B |
|---|---:|---:|
| transcript pieces（srt 段） | 9 | 14 |
| 非空字符量（约） | 104 | 192 |
| 歌词行命中率（粗粒度） | **12/32 ≈ 0.38** | 13/151 ≈ 0.09* |
| 估计可锚定行 thr0.35 | **19/32** | 39/151* |
| 总推理时间 | **2.30 s** | **2.07 s** |
| load time | 0.40 s | 0.15 s |
| 峰值 RSS | **~875 MB** | **~892 MB** |
| 磁盘模型 | 466 MB | 同左 |

\*B 歌词侧为 151 行对照结构（含罗马音行等），命中分母偏大；仍显示 **Speech 对齐 cov≈0 时 Whisper 已有可读日语句段**。

**说明：** 现有 S3A/S3B **未暴露**「外部 transcript 注入」离线入口；本轮 **未**复制第二套 DP。Whisper 侧用 **ASR 文本质量 + 可锚定潜力** 与 Speech 的 **pipeline coverage/anchors** 对照；完整「Whisper→同一 S3A/S3B」需后续最小 adapter（仍可不接 UI）。

---

## 6. 同表比较

### Sample A — 夜の合図（同 ~40s 捕获窗口）

| 指标 | Apple Speech → S3A/S3B | whisper.cpp (small, ja) |
|---|---:|---:|
| transcript pieces | 25–30 | **9**（更长连贯句） |
| 非空 token/字 | （片段级 25–30） | **~104 字可读歌词** |
| 歌词行命中率 | 低（对齐 cov 6–12%） | **~38% 行命中** |
| 锚点数 | **2–4** | 估 **~19** 潜在 |
| resolved | **2–4** | （未跑同一 DP；ASR 质量显著高） |
| low | 0–2 | — |
| unresolved | 28–30 | — |
| coverage | **0.06–0.125** | （若接入同 DP，预期显著高于 Speech） |
| 明显错行 | 大量未对齐 | 本段听感错字少 |
| 运行时间 | Speech+对齐 ~数秒 | **~2.3 s**（+模型已加载） |
| 内存 | App 进程内 | **~0.88 GB** RSS |
| 磁盘额外占用 | 0 | **~466 MB** 模型 |

### Sample B — アイドル（同 ~40s）

| 指标 | Apple Speech → S3A/S3B | whisper.cpp (small, ja) |
|---|---:|---:|
| transcript pieces | 27 | **14** |
| 锚点数 | **0** | 估潜在 >0（句段可读） |
| resolved | **0** | — |
| coverage | **0.007** | ASR 有日语内容；混有误听 |
| 运行时间 | ~数秒 | **~2.1 s** |
| 内存 | — | **~0.89 GB** |
| 磁盘 | 0 | **466 MB** |

**客观结论：** 在相同真实捕获音频上，**whisper.cpp small 的日语歌唱转写可用性明显优于当前 Apple Speech→对齐链路的有效覆盖**（尤其 Sample A）。Speech 链路 **不是零音频**，而是 **有效歌词对齐覆盖过低**。

---

## 7. Demucs Gate

| 条件 | 本轮 |
|---|---|
| Whisper 相对 Speech 有改善？ | **是**（A 明确） |
| 剩余错误是否主要来自伴奏/鼓点？ | **未证明** — A 上 Whisper 已较干净；B 有误听，**不能**断定主因是伴奏而非发音/副歌 |
| 建议 | **暂不**开 Demucs→Whisper 正式 Spike；若 B 类高能曲仍糊，再单列 A/B |
| Spleeter | **不进入** |

---

## 8. Phase 2.11C-S1 路线决定

### 选定：**路线 2**（为主）+ 路线 4 的有限修复

| 路线 | 是否 | 理由 |
|---|---|---|
| 1 先做 AutomaticAlignmentJob 调度 | **否作为 S1 主目标** | 自动跑 Speech 链路 ≈ 自动产出 **接近零可用覆盖**；不等于零操作产品 |
| **2 SpeechEngine 抽象 + whisper 实验引擎 + 模型底座** | **是 · S1 主路径** | 数据支持 Whisper 显著改善 A；先验证「换引擎能否变成可合并候选」 |
| 3 两者都不足则停 | 部分保留为 B 风险 | 若 Whisper→同一 S3A/S3B 后 cov 仍 < 产品线，再评估 Demucs/策略 |
| **4 先修 bug 再 A/B** | **并行小修复** | UI `lastPartialReport==nil` 导致「未能生成建议」；应修日志保留 + nil 根因，**再**用同一 UI 路径复测 |

### S1 建议范围（实施时 · 本轮不做）

1. 调查并修 `lastPartialReport` 为空（日志不 reset 关键路径 / WAV 生命周期 / generation）  
2. `SpeechEngine` 协议：`transcribe(wav) -> timedPieces`  
3. Apple Speech 适配器（现有）  
4. whisper.cpp **实验适配器**（进程外 CLI 或后续库；模型下载/校验/体积提示）  
5. 将 Whisper pieces **注入现有** `SegmentPartialAlignmentPipeline` 输入面（最小 adapter，**不**新 DP）  
6. **不做**全局自动开关 / 自动 adopt  

独立验收：同两段 wav，Speech vs Whisper 的 S3A/S3B coverage/anchors **同表**，且 UI 路径不再误报「未能生成建议」当报告本可存在。

---

## 9. 对 S0 建议的修订

已修订 `S0_ARCHITECTURE_AUDIT.md` §0 / §11.4：

- **撤销**「先做 Apple Speech 自动调度 MVP」作为默认 S1  
- **改为**「先引擎可行性与 SpeechEngine；自动调度 S 阶段后移」  

---

## 10. 数据库与 App 未受影响

| 检查 | 结果 |
|---|---|
| formal SHA | `d6d5f121…` **前后相同**（`freeze.txt` / `formal-db-after.sha`） |
| 诊断库 | 仅 `/tmp/spotifylyrics-s05-*.sqlite3` |
| 产品 UI | **未**接 whisper |
| schema | **未**改 |
| rebuild | **未**（沿用 CDHash `9b32bab1…`） |

---

## 11. 产物索引

| 路径 | 内容 |
|---|---|
| `freeze.txt` | HEAD / CDHash / formal |
| `logs/e2e-ui-failure.txt` | 用户 UI 失败 e2e |
| `logs/diag-sck-key.txt` | 诊断 SCK 关键行 |
| `audio/sampleA-*.wav` · `sampleB-*.wav` | 复现音频 |
| `reports/sampleA-speech-*.json` · `sampleB-speech-*.json` | Speech+S3 报告 |
| `whisper/sampleA|B/out.json` | Whisper 输出 |
| `whisper-models/ggml-small.bin` | 实验模型（大文件，可 gitignore） |

建议将 `whisper-models/*.bin` **不要**提交进 git（体积 466MB）；文档与小结果文件可 commit。

---

**S0.5 完成。暂停。不实施自动调度，不接 Demucs，不改 schema。**

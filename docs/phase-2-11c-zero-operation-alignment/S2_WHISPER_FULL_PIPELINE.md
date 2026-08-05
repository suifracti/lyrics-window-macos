# Phase 2.11C-S2 — Whisper Full-Pipeline Evaluation

| 项 | 值 |
|---|---|
| 产品 | Lyric Island |
| 日期 | 2026-08-05 |
| 分支 | `codex/phase-2-11c-s2-whisper-evaluation` |
| 基线 | `eb5b8b4` (S1 Speech Engine Foundation) |
| 方式 | **离线 harness**（不 rebuild App UI） |
| formal DB SHA | `d6d5f121…420b` before = after |
| formal opened | **NO** |
| 证据 | `docs/phase-2-11c-zero-operation-alignment/s2-whisper-full-pipeline/` |

---

## 1. 目标与非目标

### 完成

在**完全相同**的真实 WAV + 纯文本歌词 + 现有对齐链上，对：

1. AppleSpeechEngine  
2. WhisperCLISpeechEngine + `ggml-small`  
3. WhisperCLISpeechEngine + `ggml-medium`  

跑完整：

`SpeechEngineResult → S3A → S3B → AssistedCandidateMerger`

并量化比较（不是只看 transcript 可读性）。

### 明确不做

全局自动开关 · 自动保存/adopt · 普通 UI 设置 · Demucs 接入 · Spleeter · 新 DP/Merger · schema · Phase 2.7/2.8/3

---

## 2. 实验输入（固定）

| ID | 曲目 | 音频 | 时长 | 歌词行 | 语言 | 来源 |
|---|---|---|---:|---:|---|---|
| **A** | 夜の合図 / Kawasaki.Rio | S0.5/S1 同 WAV 16 kHz mono | 40.1 s | 32 | ja | 真实 ScreenCaptureKit |
| **B** | アイドル | S0.5/S1 同 WAV 16 kHz mono | 40.2 s | 151 | ja | 真实捕获；歌词含罗马字+日文交错 |
| **C** | 水曜日の約束 / Kawasaki.Rio | `kawasaki_tts` 转 16 kHz | 79.8 s | 32 | ja | **清晰人声 TTS**（非商业捕获） |
| **D** | JFK inaugural excerpt | whisper-cpp `jfk.wav` | 11.0 s | 6 | en | 英文清晰语音（非歌曲，作对照） |

约束：同 WAV · 同起止 · 同歌词 · 同 S3A/S3B/Merger 阈值 · 本轮全部重跑 · TEMP · 不写 formal。

WAV / 模型路径 gitignored；不进 App bundle。

---

## 3. 模型元数据

| 模型 | 字节 | SHA-256 | 格式 | Git / Bundle |
|---|---:|---|---|---|
| `ggml-small.bin` | 487,601,967 (~465 MB) | `1be3a9b2063867b9…` | ggml (HF stock) | **否** |
| `ggml-medium.bin` | 1,533,763,059 (~1.43 GB) | `6c14d5adee5f8639…` | ggml (HF stock) | **否** |

- CLI: `/opt/homebrew/bin/whisper-cli`  
- 语言：日语 `ja` · 英文 `en` · **无翻译模式** · 不自动下载进仓库（medium 本机下载到 gitignored 目录）  
- 详见 `s2-whisper-full-pipeline/models/model_meta.json`

---

## 4. 工具链

| 组件 | 路径 |
|---|---|
| 离线入口 | `Tools/s2_full_pipeline/main.swift` |
| 矩阵脚本 | `Tools/s2_full_pipeline/run_matrix.py` |
| 构建 | `Tools/s2_full_pipeline/build.sh` |
| 生产链复用 | `SegmentPartialAlignmentPipeline.alignFromTimedTranscript` → 同一 `finalizeFromBundles`（S3A/S3B）→ `AssistedCandidateMerger.merge` |

生产 App UI / schema **未改**。仅增加 DEBUG 可调用的 `alignFromTimedTranscript`（与 live speech 路径共享 post-speech 逻辑）。

---

## 5. 逐样本表

### sampleA — 夜の合図（真实捕获）

| 指标 | Apple | Whisper small | Whisper medium |
|---|---:|---:|---:|
| transcript pieces | 25 | 9 | 10 |
| token 命中率 | 0.188 | **0.406** | **0.406** |
| S3A coverage | 0.188 | **0.312** | **0.312** |
| S3A resolved | 4 | 9 | 10 |
| S3B anchors | 4 | 7 | **9** |
| S3B coverage | 0.188 | 0.281 | **0.312** |
| median error | n/a | n/a | n/a |
| >3s mismatch | 0 | 0 | 0 |
| merger suggestions | 4 | **8** | **10** |
| wrong suggestions† | 0 | 0 | 0 |
| elapsed (speech) | 1.13 s | 1.73 s | 5.01 s |
| peak RSS | 27 MB | 859 MB | **2217 MB** |
| model size | 0 | 488 MB | 1534 MB |

†启发式（无 held-out GT）：越界 / 非单调 / 局部重叠过低。

### sampleB — アイドル（真实捕获）

| 指标 | Apple | Whisper small | Whisper medium |
|---|---:|---:|---:|
| transcript pieces | 27 | 14 | 15 |
| token 命中率 | 0.026 | **0.146** | **0.152** |
| S3A coverage | **0.252** | 0.185 | 0.185 |
| S3A resolved | 35 | 23 | 25 |
| S3B anchors | 0 | 5 | **9** |
| S3B coverage | **0.252** | 0.106 | 0.093 |
| merger suggestions | **0** | **7** | **10** |
| wrong suggestions | 0 | 0 | 0 |
| elapsed | 2.30 s | 2.13 s | 5.23 s |
| peak RSS | 30 MB | 891 MB | 2253 MB |

说明：歌词源含罗马字与日文交错行 → 全引擎 token 命中偏低；Apple 虽有 S3A coverage 但 **Merger 为 0**；Whisper 锚点更强 → 有建议。

### sampleC — 水曜日の約束 TTS（清晰人声）

| 指标 | Apple | Whisper small | Whisper medium |
|---|---:|---:|---:|
| transcript pieces | 161 | 16 | 16 |
| token 命中率 | **1.000** | **1.000** | **1.000** |
| S3A coverage | **1.000** | 0.969 | 0.938 |
| S3A resolved | 28 | 15 | 14 |
| S3B anchors | **29** | **0** | **0** |
| S3B coverage | 1.000 | 0.969 | 0.938 |
| merger suggestions | **29** | **0** | **0** |
| wrong suggestions | 0 | 0 | 0 |
| elapsed | 2.10 s | 3.89 s | 8.98 s |
| peak RSS | 31 MB | 917 MB | 2239 MB |

**关键诊断：** Whisper 文本高度接近歌词（hit=1.0、coverage≈0.94），但 **全部 S3A conf ∈ ≈0.54–0.70**（无一行 ≥0.72），锚点 0 → Merger 0。  
Apple 短片段对齐到行级 → conf 高 → 29 条建议。  
→ 问题已从「识别」转移到 **长句切分 / 行对齐 / 置信度标定 / 锚点策略 / Merger 门槛**。

### sampleD — 英文清晰语音

| 指标 | Apple | Whisper small | Whisper medium |
|---|---:|---:|---:|
| transcript pieces | 21 | 1 | 1 |
| token 命中率 | 1.000 | 1.000 | 1.000 |
| S3A coverage | **0.833** | 0.167 | 0.167 |
| S3B anchors | **3** | 0 | 0 |
| merger suggestions | **3** | 0 | 0 |
| elapsed | 0.68 s | 0.71 s | 1.79 s |
| peak RSS | 27 MB | 858 MB | 2252 MB |

Whisper 输出 **单段长句**，行级对齐失效；Apple 词级片段更适配当前 S3A。

---

## 6. 汇总

| 指标 | Apple | Whisper small | Whisper medium |
|---|---:|---:|---:|
| 平均 suggestions | 9.0 | 3.75 | 5.0 |
| 平均建议覆盖率 | 0.383 | 0.074 | 0.095 |
| 平均错误建议数（启发式） | 0 | 0 | 0 |
| 平均 token 命中率 | 0.553 | 0.638 | 0.640 |
| 平均 S3A coverage | 0.568 | 0.408 | 0.401 |
| 平均 S3B anchors | 9.0 | 3.0 | 4.5 |
| 非零建议歌曲数 | **3/4** | **2/4** | **2/4** |
| 零建议歌曲数 | 1 | 2 | 2 |
| 平均 speech 耗时 | 1.55 s | 2.12 s | 5.25 s |
| 峰值内存（最大） | 31 MB | 917 MB | **2253 MB** |
| 模型磁盘 | 0 | 465 MB | 1.43 GB |

原始行：`s2-whisper-full-pipeline/metrics/rows.json`  
表：`metrics/comparison_tables.md`

---

## 7. small vs medium 决策

**选择：C. small 默认、medium 作为高精度可选模型**

| 维度 | 观察 |
|---|---|
| 建议数 | medium 在 A/B 上 +2–3 条建议、锚点更多 |
| 错误建议 | 启发式均为 0（无 GT 下不保证） |
| 时间 | medium ≈ small × 2.5 |
| 内存 | medium ≈ 2.2 GB RSS vs small ≈ 0.9 GB |
| 磁盘 | 1.43 GB vs 0.47 GB |
| C/D 清晰语音 | medium **不能**修复 Merger 零建议（切分/对齐问题） |

small 已能在真实日语捕获 A/B 上超过 Apple 的建议数；medium 有增益但不足以单独承担默认负载。

---

## 8. 自动排轴可行性（实验级）

**不可进入自动调度 / 自动质量门控研究（产品向）。**

否决条件命中：

- Whisper 仅在 **2/4** 样本产生非零建议（多数样本仍可零建议）  
- 清晰人声 C 上 hit=1.0 却 **0 建议** → 高覆盖≠可用建议  
- medium 对 C/D 无对齐收益，资源翻倍  

因此 **不能** 因 A/B 成功就宣布可自动排轴。

---

## 9. Demucs Gate

**Demucs 暂不值得进入。**

理由：

1. 失败主因在 C 上已证明：**文本足够好仍无建议** → 非伴奏污染主导。  
2. medium 未改善 C/D。  
3. A/B 上 Whisper 已明显改善识别与锚点；残余问题更像 **歌词版本/罗马字交错、长句切分、置信度与 Merger**。  
4. 清晰 TTS（C）优于复杂伴奏（A/B）在 Apple 上成立，但 Whisper 在 C 上反而 Merger 失败 → 不符合「人声清晰样本对齐链必然更好」的 Demucs 前提。

若未来进入 Demucs，协议仍应为：  
`同一 WAV → Demucs vocals → 同一 Whisper → 同一 S3A/S3B/Merger`（本阶段不实施）。

---

## 10. 瓶颈排序（本轮诊断，不改算法）

当 Whisper transcript 已高度接近歌词（样本 C）时，主瓶颈排序：

1. **行切分** — Whisper 长句 vs 歌词单行；词级时间缺失  
2. **S3A tokenization / 置信度** — 全线 conf 卡在 0.54–0.70，无 ≥0.72  
3. **S3B 锚点** — 长窗口唯一性/相似度过严 → accepted=0  
4. **Merger 过滤** — 门槛 0.72/0.78 滤掉全部低 conf  
5. **规范化 / 分词** — 汉字假名差异、促音等次要（C 上 hit=1.0）  
6. **识别** — 在清晰 TTS 上已不是主因；在真实唱歌 A/B 仍重要  
7. **重复段落消歧** — 本批样本未成为主因  

真实唱歌 A/B：**识别仍重要**，但 B 的歌词交错结构放大规范化问题。

---

## 11. 合同

新增（PASS）：

1. `whisper_full_pipeline_contract`  
2. `same_input_engine_comparison_contract`  
3. `model_path_not_tracked_contract`  
4. `engine_result_to_s3_contract`  
5. `merger_metrics_contract`  
6. `formal_db_isolation_contract`  

既有 SpeechEngine / Assist / S3 合同继续适用（S1 基线未破坏）。

---

## 12. TEMP / formal DB

| 项 | 证明 |
|---|---|
| formal before | `d6d5f121152057908ccd70cf4b83d8c76d86b9f4b9c9929326c45a60eb5f420b` |
| formal after | 相同 |
| formal opened | false（harness 无 SQLite repository） |
| TEMP | 输出在 `s2-whisper-full-pipeline/runs/`（gitignored） |

---

## 13. 下一阶段建议（不自动实施）

1. **优先修对齐适配 Whisper 长句**：句→行切分、置信度重标定、锚点窗口、或 Merger 对「高文本相似+低 conf」的分层策略（仍保持人工确认）。  
2. 歌词输入净化：去除 B 类罗马字交错行。  
3. small 默认；DEBUG 可选 medium。  
4. **不做** Demucs，直到对齐层在清晰人声上能把 hit≈1.0 变成非零可靠建议。  
5. 补 held-out GT 时间轴后重算 wrong-suggestion / median error。

---

## 14. 最终路线（唯一）

# **B. 先修歌词规范化 / 行切分 / 对齐**

**不是 A**（自动质量门控）— Whisper 零建议样本过多，C 上质量语义矛盾。  
**不是 C**（Demucs）— 主瓶颈不在伴奏分离。  
**不是 D**（停止 Whisper 主线）— A/B 真实捕获上 Whisper 相对 Apple **明确提升**建议与锚点。

**暂停。** 不自动实施选择结果。

# Phase 2.11C-S3 — Transcript Normalization, Segmentation and Alignment Recovery

| 项 | 值 |
|---|---|
| 产品 | Lyric Island |
| 日期 | 2026-08-05 |
| 分支 | `codex/phase-2-11c-s3-transcript-alignment` |
| 基线 | `9bfaf60` (S2 full-pipeline evaluation) |
| 方式 | 离线 harness + Capture 路径适配（不改 schema / 普通 UI） |
| formal DB | `d6d5f121…420b` before = after · **未打开** |
| 证据 | `docs/phase-2-11c-zero-operation-alignment/s3-transcript-alignment/` |

---

## 1. 目标与非目标

### 完成

修复 S2 主瓶颈：

Whisper 文本接近歌词 → 长句未切行 → confidence 语义不适合门控 → anchors=0 → Merger 滤成 0 建议。

实现：

1. `TranscriptNormalizer`（匹配视图，不改展示/歌词存储）  
2. `TranscriptSegmentSplitter`（长句切分，时间仅在 observed 段内）  
3. ASR confidence 语义（缺失 = `-1`，中性 prior，不伪造 1.0）  
4. S3A/S3B 输入适配（prepare → 同一 DP）  
5. Anchor 恢复（引擎无关）  
6. Merger 解释 + lexical recovery  

### 不做

自动开关 · 自动保存/adopt · Demucs · 新 ASR · schema · UI 重构 · Phase 2.7+

---

## 2. 固定输入与 S2 before

同 S2 四样本、同 WAV、同歌词、同引擎矩阵。

| 样本 | Apple | small | medium |
|---|---:|---:|---:|
| A 夜の合図 | 4 | 8 | 10 |
| B アイドル | 0 | 7 | 10 |
| C 水曜日の約束 TTS | 29 | **0** | **0** |
| D JFK 英文 | 3 | **0** | **0** |

---

## 3. 架构改动

```
SpeechEngineResult
  → TranscriptNormalizer (match view)
  → TranscriptSegmentSplitter (subsegments + time provenance)
  → TimedTranscript (ASR conf: observed or -1)
  → LineForcedAligner (S3A) / AnchorConstrainedAligner (S3B)
  → AssistedCandidateMerger.mergeWithExplanation
  → AssistedAlignmentDraft
```

### 时间 provenance

| 值 | 含义 |
|---|---|
| `observed` | 未切分，整段使用引擎时间 |
| `interpolatedWithinObservedSegment` | 仅在父 segment [start,end] 内按 token 权重分配 |
| `unresolved` | 未使用（无证据） |

禁止：按全曲时长均分虚假时间。

### Confidence 分层

| 层 | 来源 |
|---|---|
| ASR confidence | Apple 有；Whisper CLI 常缺失 → `-1` / `missing_asr` |
| Lexical match | LineForcedAligner similarity / score |
| Temporal | segment 时间窗 + 单调约束 |
| Anchor overall | textWeight×sim + speechWeight×(observed\|neutral 0.85) |
| Merger gate | 0.72/0.78 或 lexical recovery（direct + ≥0.72） |

---

## 4. Before / After 矩阵（最终）

完整表：`s3-transcript-alignment/metrics/before_after.md`

| sample | engine | sug Before→After | anchors Before→After | wrong After |
|---|---|---:|---:|---:|
| A | apple | 4→**4** | 4→4 | 0 |
| A | small | 8→**5** | 7→5 | 0 |
| A | medium | 10→**9** | 9→9 | 0 |
| B | apple | 0→**0** | 0→0 | 0 |
| B | small | 7→**3** | 5→3 | 0 |
| B | medium | 10→**5** | 9→5 | 0 |
| C | apple | 29→**29** | 29→29 | 0 |
| C | small | **0→21** | **0→21** | 6† |
| C | medium | **0→23** | **0→23** | 6† |
| D | apple | 3→**3** | 3→3 | 0 |
| D | small | **0→3** | **0→3** | 0 |
| D | medium | **0→3** | **0→3** | 0 |

†启发式 wrong（局部重叠过低 / 段内插值边界）；C 上 Whisper 切分后仍有若干行需人工复核，**不再**出现「hit≈1、coverage≈0.94、0 建议且无解释」。

### 非零建议歌曲数

| 引擎 | Before | After |
|---|---:|---:|
| Apple | 3/4 | 3/4 |
| Whisper small | 2/4 | **4/4** |
| Whisper medium | 2/4 | **4/4** |

### C 解释（主修复）

| 项 | Before | After |
|---|---|---|
| raw pieces | 16 | 16 |
| prepared pieces | 16 | **30**（标点/歌词 token 切分） |
| S3A conf 形态 | 全 low ~0.54–0.70 | 多数 resolved ≥0.72 |
| anchors | 0 | 21–23 |
| suggestions | 0 | 21–23 |
| Merger decisions | n/a | `merger_decisions.json` 逐行 accepted/rejected |

### A/B 说明

真实混音上 Whisper 建议数 **略降**（small A 8→5、B 7→3），来自：

1. 缺失 ASR 时不再伪造 conf=1.0（neutral prior 0.85）  
2. 更严格的 evidence 记录与单调过滤  

**未**通过全局降阈值换数量。medium 仍保持较强（A=9、B=5）。Apple 路径 **完全恢复** S2 数字。

---

## 5. 真实歌曲扩展

| ID | 类型 | 状态 |
|---|---|---|
| A | 日语真实捕获（中速） | 已有 |
| B | 日语真实捕获（快/重复副歌结构） | 已有；罗马字交错歌词仍是主噪声 |
| C | TTS 清晰人声 | 诊断样本，不并入自动门控统计 |
| D | 英文清晰语音 | 诊断样本，非歌曲 |

**中文商业曲 / 英文歌曲 + 可信参考轴：** 本机无授权可复现 WAV+LRC fixture，**未编造**。  
自动模式判断 **仅** 以 A/B 真实捕获 + C/D 诊断对照为依据，不把 TTS 成功当作产品可自动。

若下一阶段补齐：日语慢歌、日语快歌、中文歌、英文歌各一首真实混合音频 + held-out 时间轴，再重新门控评估。

---

## 6. 模型决策

保持 S2：

- **small** 默认实验  
- **medium** 高精度对照  
- **Apple** 低资源路径  
- **Demucs：不接入**

---

## 7. 合同

新增 10 项（PASS）：见 `s3-transcript-alignment/contracts.log`。

既有 S1/S2/Assist/S3 合同保持 PASS。

---

## 8. formal DB

| before | after | opened |
|---|---|---|
| `d6d5f121…420b` | `d6d5f121…420b` | **NO** |

---

## 9. 提交拆分

1. `feat(alignment): normalize and split speech transcripts`  
2. `fix(alignment): calibrate evidence and recover anchors`  
3. `fix(alignment): explain and preserve valid merger candidates`  

---

## 10. 最终路线

# **B. 继续优化重复段落与行级对齐**

### 不选 A（自动质量门控）

- 真实歌唱 A/B 上 Whisper 建议覆盖仍有限，且 small 相对 S2 略降  
- B 仍可能 0（Apple）或低覆盖  
- 无完整中文/英文真实歌曲 held-out 集  
- C 的 6 条启发式 wrong 说明切分插值仍需人工复核  

### 不选 C（Demucs）

- C 清晰人声路径已恢复建议；主瓶颈曾是切分/evidence，不是伴奏  

### 不选 D（停主线）

- C/D 零建议已修复；Whisper 全样本非零；方向正确  

### 下一阶段建议（不实施）

1. 重复副歌消歧（B）与歌词源净化（去罗马字交错）  
2. 段内插值时间标定（降 C wrong）  
3. 补 4 首真实歌曲 + held-out 再评估是否进 A  

**暂停。** 不自动实施全局开关。

# Phase 2.11C-S4 — Repeated Sections, Timeline Constraints and Real-Song Validation

| 项 | 值 |
|---|---|
| 产品 | Lyric Island |
| 日期 | 2026-08-05 |
| 分支 | `codex/phase-2-11c-s4-repeated-sections` |
| 基线 | `ed1e97f` (S3 transcript alignment recovery) |
| formal DB | `d6d5f121…420b` before = after · **未打开** |
| 证据 | `docs/phase-2-11c-zero-operation-alignment/s4-repeated-sections/` |

---

## 1. 目标与非目标

### 完成

1. 重复副歌 / 重复行 occurrence 建模与消歧  
2. CapturedSegment **绝对时间窗**约束进入候选与过滤  
3. 段内时间 evidence 分层（observed / constrainedInterpolated / weakInterpolated）  
4. 锚点间局部 `LocalAlignmentWindow`（复用 LineForcedAligner，无第二套 DP）  
5. Merger 拒绝 weak interpolation 与错 occurrence  
6. S3→S4 12 格回归 + 真实歌曲评估协议  

### 不做

自动开关 · 自动保存/adopt · Demucs · 新 ASR · schema · UI 重构

---

## 2. 算法说明

### RepeatedLyricsSectionResolver

- 按 match-view 文本分组成 `RepeatedGroup`  
- 对每个 timed 候选：  
  - **outside_capture_window** → reject  
  - **wrong_occurrence_order_conflict** → reject  
  - **ambiguous_repeated_section_no_neighbor_support** → unresolved  
  - 否则 accept  

原则：**宁可 unresolved，不猜第一次/第二次副歌。**

### Capture window

`absoluteTime = positionStart + wavRelativeTime`  
Harness 支持 `--position-start` / `--position-end` / `--track-duration`。  
单元测试：capture 120–160 时，无任何建议落在 119 之外。

### Evidence types

| type | 含义 | Merger |
|---|---|---|
| observed | 引擎原边界 | 可接受 |
| constrainedInterpolated | 段内 + 歌词 token 对齐 | 可接受（resolved） |
| weakInterpolated | 仅标点切分 | **拒绝** |
| localWindow:constrainedInterpolated | 锚点夹窗局部对齐 | 可接受（上限 conf） |
| s4:outside_capture_window 等 | 消歧拒绝 | 拒绝 |

### LocalAlignmentWindow

仅在两 anchors 之间的歌词缺口运行 LineForcedAligner，transcript 裁剪到绝对时间窗。不覆盖已 resolved 行。

---

## 3. S3 → S4 12 格

完整表：`metrics/s3_to_s4.md`

| 样本 | 引擎 | S3 sug | S4 sug | wrong | 备注 |
|---|---|---:|---:|---:|---|
| A | apple/small/medium | 4/5/9 | **4/5/9** | 0 | 无重复；零回归 |
| B | apple/small/medium | 0/3/5 | **0/3/5** | 0 | groups=2；无 wrong_occurrence |
| C | apple/small/medium | 29/21/23 | **29/21/23** | 0/6/6 | 不回 0 建议 |
| D | apple/small/medium | 3/3/3 | **3/3/3** | 0 | 不回 0 建议 |

**结论：** 无重复样本与 C/D 均无退化；错误建议未增加。

---

## 4. 真实歌曲扩展

### 本机可用性

| 槽位 | 状态 |
|---|---|
| 日语慢 / 快 / 重复副歌 | **部分**：sampleA/B 真实捕获 |
| 日语短句 / 中文 / 英文商业歌 | **缺失** 本机授权 WAV+GT |

见 `real-songs/inventory.json`、`PROTOCOL.md`。

**未**提交商业音频或完整版权歌词。  
**auto_gate_eligible = false**（不足 6/8 首真实歌）。

### 人工核对

- 模板：`real-songs/human_review_template.json`  
- 本轮 12 格：`real-songs/assisted_review_s12.json`（助手启发式，非商业真值替代）  
- 捕获窗单元测试：PASS  

---

## 5. 自动模式门槛判断

| 条件 | 状态 |
|---|---|
| ≥6/8 真实歌非零建议 | **未满足**（fixture 不足） |
| wrong occurrence ≈ 0 | 本轮 12 格 **0** |
| 重复副歌无错配 | B 检出 groups；无 wrong_occurrence 标志 |
| C 残余 wrong 启发式 | 仍有 6（段内插值重叠） |
| small 资源可接受 | 是（~0.9GB RSS） |

**不具备进入自动质量门控设计的资格。**

---

## 6. 合同

新增 10 项（`Tests/*_contract.sh`）全部 PASS。  
S1–S3 / Assist 相关合同保持 PASS。

---

## 7. formal DB

| before | after | opened |
|---|---|---|
| `d6d5f121…420b` | 相同 | **NO** |

---

## 8. 提交

1. `feat(alignment): constrain repeated lyric occurrences`  
2. `fix(alignment): classify and bound interpolated timings`  
3. `test(alignment): validate real-song repeated sections`  

---

## 9. 最终路线

# **B. 继续优化真实歌曲行级对齐**

### 不选 A

真实 8 歌矩阵未齐；C 仍有启发式错误；覆盖仍不足以自动门控。

### 不选 C（Demucs）

本阶段瓶颈是 occurrence / 插值 / 样本规模，不是伴奏分离。

### 不选 D

S3 收益保持；S4 增加可解释约束与捕获窗安全网；主线继续。

### 下一阶段建议（不实施）

1. 本机补齐 8 首授权真实歌曲 + GT，按 PROTOCOL 跑 small  
2. 降低 C 类 constrained 插值 wrong（更好 token 时间边界）  
3. B 类歌词源净化（罗马字交错）  
4. 达标后再评估 A  

**暂停。** 不实施全局开关 / 自动保存 / 自动采用。

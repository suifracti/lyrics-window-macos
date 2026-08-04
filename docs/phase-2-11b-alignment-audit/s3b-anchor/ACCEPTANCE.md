# Phase 2.11B-S3B — 锚点约束 Partial 对齐验收

| 项 | 值 |
|---|---|
| 日期 | 2026-08-04 |
| 工作目录 | `/Users/apple/backup/sptifylyrics` |
| 分支 | `codex/phase-2-11a-lyrics-retrieval` |
| 基线 | `6281804` |
| 本阶段 | **S3B only**（完成后暂停，不进入 S3C） |

## 实现摘要

| 文件 | 作用 |
|---|---|
| `Capture/AnchorAlignmentPolicy.swift` | 锚点阈值集中（相似度 / 长度 / 唯一性 / 最少锚点数） |
| `Capture/AlignmentAnchor.swift` | 锚点与 A/B 对比模型；`SegmentSpeechBundle` |
| `Capture/AnchorConstrainedAligner.swift` | `selectAnchors` + 区间 `LineForcedAligner` |
| `Capture/SegmentPartialAlignmentPipeline.swift` | 同一次 Speech：S3A 全局 DP + S3B 锚点约束；A/B 报告 |
| `Capture/PartialAlignmentModels.swift` | `s3aCandidate` / anchors / held-out ≤0.5/1/2s 计数 |
| `Capture/LiveCaptureCoordinator.swift` | S3B A/B 日志（仍复用 S3A 触发入口） |
| `Tests/s3b_anchor_alignment_contract.sh` | 合同 |

**复用：** ScreenCaptureKit 链、CapturedSession/Segment、SegmentWAVWriter、SpeechTimedTranscriptProvider、LineForcedAligner、AlignmentSessionGuard、语言规范化。  
**禁止项遵守：** 无 Whisper / 人声分离 / 新 DB schema / 正式产品入口 / 用 GT 反推锚点 / 降阈值刷 PASS。

## 关键行为

1. 每个连续 segment → WAV → Speech（一次）→ 同时跑 **S3A 全局 Partial DP** 与 **S3B 锚点筛选**。  
2. 锚点仅来自 Speech 文本 + 纯文本歌词（规范化后相似度、唯一性、单调时间/行序）；**不读** held-out 时间戳。  
3. 接受锚点 ≥2 时：区间内仅允许对应歌词行 + 对应时间窗 Speech；区间 DP 仍用 `LineForcedAligner`。  
4. 锚点 <2：`insufficientAnchors_*` 回退 S3A。  
5. held-out 仅在对齐完成后比较 start 误差。  
6. 报告：`spotifylyrics-s3a-reports/partial-*.{json,md}`（含 A/B 表与 accepted/rejected anchors）。

---

## 样本 A — 《夜の合図 / Kawasaki.Rio》

| 项 | 值 |
|---|---|
| 歌词 | QQ Experimental 纯文本 32 行（无同步 → held-out n/a） |
| 捕获 | ~48.4 s，2 segments（短 seek 段 5.2s + 连续 43.8s） |
| Speech 片段 | 36（3 + 33） |
| locale | ja-JP |
| 报告 | `sample-a/partial-FCE4FF7E.*` |

### A/B 对比（同捕获 + 纯文本）

| metric | S3A | S3B |
|---|---:|---:|
| resolved | 2 | **4** |
| lowConfidence | 2 | 1 |
| unresolved | 28 | 27 |
| outsideCapturedRange | 0 | 0 |
| coverageRatio | **0.125** | **0.156** |
| overallConfidence（有时间行） | 0.634 | 0.802 |
| acceptedAnchors | n/a | **4** |
| rejectedAnchors | n/a | 26 |
| usedConstrained | n/a | true |
| held-out median / P90 / P95 | n/a | n/a |
| 明显错行（人工） | — | 锚点 4 条文字高度吻合，未见错行 |

### Accepted anchors（文字证据）

| line | conf | abs t | lyric（前缀） | speech（前缀） |
|---:|---:|---:|---|---|
| 13 | 0.958 | 76.94 | 時計の針を戻してる | 時計の針を戻してる |
| 14 | 0.934 | 79.61 | 愛してた　それだけじゃ | 愛してたそれだけじゃ |
| 15 | 0.813 | 82.79 | ダメだったんだね | だめだったんだな |
| 16 | 0.859 | 85.01 | すれ違った言葉たちが | それ違った言葉たちが |

顺序单调；拒绝原因主要为 `text_similarity_below_threshold` / `duplicate_lyric_line` / 低 overall。

相对 S3A 历史 9.4% coverage，本次 S3A 基线 12.5%（同曲不同捕获），S3B **+3.1 pp**（主要由 4 个锚点 resolved 贡献；区间 DP 几乎未填出新行）。

---

## 样本 B — 《アイドル / YOASOBI》（held-out 同步）

| 项 | 值 |
|---|---|
| 歌词 | LRCLIB **synced** 151 行（算法输入剥离时间戳；GT 仅 post-hoc） |
| 捕获 | **75.4 s** 连续 1 segment，pos ≈ 10.1→85.5 |
| Speech 片段 | 83 |
| locale | ja-JP |
| 报告 | `sample-b/partial-404F9F32.*` |

### A/B 对比

| metric | S3A | S3B |
|---|---:|---:|
| resolved | 45 | 16 |
| lowConfidence | 5 | 4 |
| unresolved | 13 | 44 |
| outsideCapturedRange | 88 | 87 |
| coverageRatio | **0.331** | **0.132** |
| overallConfidence | 0.067 | 0.422 |
| acceptedAnchors | n/a | **8** |
| rejectedAnchors | n/a | 39 |
| usedConstrained | n/a | true |

说明：S3A 大量 `boundedInterpolation`（44）抬高了 timed/coverage；S3B 区间更保守，未跨锚点插值。

### Held-out 时间误差（仅 post-hoc）

| metric | S3A | S3B |
|---|---:|---:|
| comparedLineCount | 50 | 20 |
| medianAbsErr | **1.62 s** | **0.78 s** |
| P90 | 4.52 s | 4.46 s |
| P95 | 4.85 s | 5.45 s |
| mean | 1.90 s | 1.75 s |
| ≤0.5 s | 8 | 5 |
| ≤1 s | 20 | 12 |
| ≤2 s | 30 | 14 |
| obviousMismatch (>3s) | **11** | **5** |

S3B 在 **更少** 的 timed 行上 median 更优、严重错时更少；但 coverage 明显下降。

### Accepted anchors（节选证据）

| line | conf | abs t | 文字证据 |
|---:|---:|---:|---|
| 7 | 0.759 | 10.11 | speech 含「嘘つきな君は」↔ 歌词行 |
| 13 | 0.800 | 13.23 | 「今日何食べた」精确 |
| 14 | 0.800 | 17.40 | 「好きな本は」精确 |
| 19–24 | 0.800 | 19.6–21.9 | 短句精确簇 |
| 50 | 0.754 | 54.63 | 「誰も…目を奪われて」部分匹配 |

锚点时间/行序 **单调无冲突**。早期短句簇导致中间区间很窄，区间 DP 难以补全。

---

## 判断（产品价值）

> **结论 B：`B_coverage_up_but_errors_remain`（实验有价值，但不足以作为产品主路径）**

依据（不为 PASS 改口径）：

1. **锚点本身有效：** 两样本均能从真实 Speech 抽出可解释文字锚点，顺序无冲突，阈值保持保守。  
2. **样本 A：** coverage 12.5%→15.6%（+3.1 pp），无 held-out；改进主要来自锚点 pin，未显著增加错行。  
3. **样本 B：** coverage 33%→13%（变差），但 held-out median 1.62s→0.78s、>3s 错时 11→5；说明锚点时间更准，而 **锚点间区域 DP 弱于 S3A 全局插值**。  
4. **不足以进入产品自动采用；** 值得保留实验实现，后续评估 S3C/更好识别或改进区间填充策略。

**不判定 A**（未达到安全提升 coverage 且错误不增的统一优势）。  
**不判定 C**（两样本均形成 ≥2 可靠锚点，并非“无法成锚”）。

---

## 安全与清理

| 检查 | 结果 |
|---|---|
| 正式库路径 | `~/Library/Application Support/SpotifyLyrics/SpotifyLyrics.sqlite3` |
| formal-db-before SHA | `5c51310df85f140f5cb8488deb6f941fdd67401f831ae3d4bf548c0b53368863` |
| formal-db-after SHA | **相同**（样本 A/B 窗口内未改） |
| spike `formal_db_opened` | **NO** |
| 临时 WAV / session 目录 | CLEANUP `exists_after=false`；验收后 `wav_remaining=0` |
| 证据保留 | 仅 JSON/MD 报告 + 脱敏日志统计（无完整音频） |
| 自动采用时间轴 | **无** |
| SQLite schema | **未改** |

App 路径：

```text
/Users/apple/backup/sptifylyrics/DerivedData/Build/Products/Debug/SpotifyLyrics.app
```

合同：

```text
Tests/s3b_anchor_alignment_contract.sh → PASS
Tests/s3a_partial_alignment_contract.sh → PASS
```

Debug xcodebuild：**BUILD SUCCEEDED**

---

## 暂停

**S3B 完成。不进入 S3C / S4 / S5。**

# Phase 2.11B-S3A — Speech + Partial 行级对齐验收

| 项 | 值 |
|---|---|
| 日期 | 2026-08-04 |
| 工作目录 | `/Users/apple/backup/sptifylyrics` |
| 分支 | `codex/phase-2-11a-lyrics-retrieval` |
| 基线 | `b3eca81` |
| 样本曲 | 夜の合図 / Kawasaki.Rio |
| 歌词来源 | QQ Experimental 纯文本 32 行（**无同步时间** → held-out 不可用） |

## 实现摘要

| 文件 | 作用 |
|---|---|
| `Capture/SegmentWAVWriter.swift` | 连续 segment → 16 kHz mono WAV |
| `Capture/PartialAlignmentModels.swift` | Partial 候选 / held-out 统计 |
| `Capture/AlignmentLocaleRecommender.swift` | ja-JP / zh-CN / en-US 最小推荐 |
| `Capture/SegmentPartialAlignmentPipeline.swift` | Speech + DP + 绝对时间映射 + 报告 |
| `Capture/LiveCaptureCoordinator.swift` | WAV 写入；stop 后跑 S3A；切歌 cancel gen |
| `Main.swift` | Debug 菜单「Partial 对齐 (S3A)」 |
| `Tests/s3a_partial_alignment_contract.sh` | 合同 |

**不写正式 SQLite 歌词版本；不打开正式库。**

## 关键行为

1. 每 `CapturedAudioSegment` 单独 WAV；pause/seek/切歌结束当前 WAV。  
2. `SpeechTimedTranscriptProvider` + `LineForcedAligner`（**不**要求 `isComplete`）。  
3. `absoluteTime = segment.spotifyPositionStart + speechRelativeTime`。  
4. Partial 状态：`resolved` / `lowConfidence` / `unresolved` / `outsideCapturedRange` / `interpolated`。  
5. held-out：仅当当前歌词 **已同步** 时比较 start 误差；本跑因纯文本 **n/a**。  
6. 报告：`/tmp/.../spotifylyrics-s3a-reports/partial-*.{json,md}`  

## 场景结果

### A + B（连续 + pause/resume 两段）— `s3a-run.log` / `partial-9817ABB2.*`

| 指标 | 值 |
|---|---|
| 捕获总时长 | **45.694 s**（两段：27.06 + 18.72） |
| 捕获范围 | pos ≈ 44.9→71.9 与 71.2→89.9（中间 pause 不拼接） |
| Speech transcript 片段 | **22**（段1=2，段2=20） |
| 歌词总行数 | **32** |
| resolved | **1** |
| lowConfidence | **2** |
| unresolved | **29** |
| outsideCapturedRange | **0**（无 held-out 同步轴，无法按 GT 标 outside） |
| coverageRatio | **0.094** |
| overallConfidence（有时间行） | **0.624** |
| held-out median/P90/P95 | **n/a**（`no_held_out_synced_lyrics`） |
| judgment | **`C_speech_weak_on_singing`** |

两段分别识别：`S3A speech ok segmentID=C58808B7 …` 与 `…209CFDF5 …`；**未跨 pause 拼接 WAV**。

### C（切歌取消）— `s3a-scenario-c.log`

```text
S2 IDENTITY previous=…夜の合図… next=…bitte…
S3A cancel gen=2 reason=trackChanged
SESSION end … reason=trackChanged
SESSION start … (new identity)
```

旧 gen 作废；迟到 buffer `DROP`；**未**把旧候选写入新曲。

### 清理

- `CLEANUP sessionDir=… exists_after=false`  
- 正式库 SHA 不变；`formal_database_opened=NO`  

## 判断（S3A 目标）

> **C：歌唱场景下现有 SFSpeechRecognizer + 行级 DP 几乎不可用作为完整排轴方案。**

依据（不调低阈值）：

- 覆盖率仅 ~9%（1 resolved + 2 low / 32）  
- 第一段 27s 音频仅 2 个 transcript 片段  
- 第二段 18s 有 20 个片段，但仍难匹配多数歌词行  

**建议：** 进入 **S3B（可靠锚点 + 锚点间对齐）** 之前应接受「识别弱」的事实；S3C 人声分离 **仅当** S3B 仍不足时再议。本地文件完整曲 + 同一引擎的对照可在 S5 补做。

**非失败：** 管线闭环已证明（捕获 → WAV → Speech → DP → Partial 报告 → 清理）。

## 合同与构建

```text
s3a_partial_alignment_contract: PASS
Debug xcodebuild: BUILD SUCCEEDED
App: DerivedData/Build/Products/Debug/SpotifyLyrics.app
```

## 暂停

**S3A 完成，不进入 S3B。**

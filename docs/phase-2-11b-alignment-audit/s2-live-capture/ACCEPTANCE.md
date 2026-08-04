# Phase 2.11B-S2 — Live Capture Continuity 验收

| 项 | 值 |
|---|---|
| 日期 | 2026-08-04 |
| 工作目录 | `/Users/apple/backup/sptifylyrics` |
| 分支 | `codex/phase-2-11a-lyrics-retrieval` |
| 基线 | `570fa0c` |
| 范围 | Session/Segment 模型 + Spotify position 连续性；**无 ASR/对齐/正式库写入** |

## 实现文件

| 文件 | 作用 |
|---|---|
| `Capture/CaptureContinuityPolicy.swift` | 集中阈值（seek 1.5s、gap 1.75s、anchor 2s…） |
| `Capture/CapturedAudioModels.swift` | `CapturedAudioSession` / `CapturedAudioSegment`（仅内存） |
| `Capture/LiveCaptureCoordinator.swift` | 会话/段拆分、观察 PlaybackState、结构化日志 |
| `Capture/SpotifyScreenCaptureAudioSpike.swift` | 增加 `audioSampleHandler` 转发给 S2 |
| `Services/PlaybackState.swift` | DEBUG：seek / Desktop 位置大跳变通知 coordinator |
| `Main.swift` | Debug 菜单 S2 开始/停止；bind playback |
| `Tests/s2_live_capture_contract.sh` | 合同 |

## 临时音频策略（选择与理由）

- **选择：** 每 segment 写入 **JSON sidecar 元数据**（sampleCount/rate/position/PTS…），**不写 PCM 正文**。
- **理由：** S2 验收关注连续性与 identity，不需要 ASR；sidecar 可审计且无音频落盘风险；S3 再按需写 PCM。
- 路径：`NSTemporaryDirectory()/SpotifyLyricsCapture/s2-sessions/<sessionID>/seg-XXXXXXXX.json`
- 停止时 `CLEANUP … exists_after=false`；启动 scavenger 清理孤儿。

## 连续性阈值

| 常量 | 值 | 含义 |
|---|---|---|
| `seekJumpThreshold` | 1.5 s | 位置跳变视为 seek |
| `positionJitterTolerance` | 0.40 s | 忽略轮询抖动 |
| `audioGapTimeout` | 1.75 s | 无 buffer 则 gap 关段 |
| `anchorLogInterval` | 2.0 s | 周期性 ANCHOR |
| pause | — | 暂停不因静音 buffer 开新段；resume 新 continuity |

## 真实验收场景

### 场景 A：综合剧本（`s2-capture.log` / `s2-summary-extract.log`）

Spotify 真实播放 + AppleScript：连续播 → pause 3s → resume → seek → next → previous。

| 场景 | 结果 | 证据 |
|---|---|---|
| 连续播放 + ANCHOR | PASS | 多条 `ANCHOR … playing=true`，position 单调前进 |
| 暂停 / 恢复 | PASS | `reason=pause` 后 `reason=resume` 新 `continuityID` |
| 切歌关 session | PASS | `SESSION end reason=trackChanged` + 新 `SESSION start` |
| A→B→A 不合并 | PASS | 同一 identity `夜の合図` 出现两次不同 sessionID：`66E1CF23` 与 `5D6DE4A2` |
| 迟到 buffer 丢弃 | PASS | `S2 DROP late buffer identity mismatch` |
| 停止清理 | PASS | `CLEANUP … exists_after=false` |
| 正式库 | PASS | `formal_database_opened=NO`；SHA 前后 `73a26067…` |

### 场景 B：Seek 专项（`s2-seek-focus.log`）

| 场景 | 结果 | 证据 |
|---|---|---|
| 向前 seek | PASS | `reason=seekForward` + `S2 SEEK … source=playbackNotify` from 37.280 → 52.333 |
| 向后 seek | PASS | `reason=seekBackward` from 57.202 → 47.280 |
| 同一 session 多段 | PASS | `SUMMARY … segments=3` 不拼接 |

## Segment/Session 汇总（Seek 专项）

| i | start | end | pos | dur | samples |
|---|---|---|---|---|---|
| 0 | initial | seekForward | 32.07→37.28 | 5.22 | 250560 |
| 1 | seekForward | seekBackward | 52.33→57.20 | 4.98 | 239040 |
| 2 | seekBackward | autoStop | 47.28→62.94 | 15.86 | 761280 |

## 合同与构建

```text
bash Tests/s2_live_capture_contract.sh  → PASS
bash Tests/sck_spike_contract.sh        → PASS
xcodebuild Debug                        → BUILD SUCCEEDED
```

App：`/Users/apple/backup/sptifylyrics/DerivedData/Build/Products/Debug/SpotifyLyrics.app`

## 法律边界（重申）

技术可行 · 本地实验可行 · 正式发布需条款／审核核验。未接 ASR，未生成时间轴。

## 状态

**S2 完成，暂停。不进入 S3A。**

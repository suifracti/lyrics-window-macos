# Phase 2.11B-S1 — ScreenCaptureKit Spotify Audio Spike 验收

| 项 | 值 |
|---|---|
| 日期 | 2026-08-04 |
| 工作目录 | `/Users/apple/backup/sptifylyrics` |
| 分支 | `codex/phase-2-11a-lyrics-retrieval` |
| 基线 | `c8e4fce` |
| HEAD（本提交后） | 见 git log |
| 范围 | **仅** Spotify App 音频捕获 + PCM 统计；无 ASR / 对齐 / 歌词版本 / 正式库 |

## 产物路径

| 项 | 路径 |
|---|---|
| App | `/Users/apple/backup/sptifylyrics/DerivedData/Build/Products/Debug/SpotifyLyrics.app` |
| Spike 日志 | `/tmp/spotifylyrics-sck-spike.log` → `sck-spike.log` |
| 临时库 | 见 `temp-db-path.txt`（`SPOTIFYLYRICS_DATABASE_PATH`） |
| 正式库 SHA | `formal-db-before.sha` / `formal-db-after.sha`（一致） |

## 实现摘要

- 新文件：`SpotifyLyrics/Capture/SpotifyScreenCaptureAudioSpike.swift`（`#if DEBUG`，可整文件删除）
- Debug 菜单：`排轴捕获 Spike（调试）` → 开始 / 停止
- Env：`SPOTIFYLYRICS_SCK_SPIKE=1`，可选 `SPOTIFYLYRICS_SCK_SPIKE_SECONDS`（默认 20）
- Info.plist：`NSScreenCaptureUsageDescription`（诚实说明仅 Spotify 音频、不录麦、不存音频）
- 合同：`Tests/sck_spike_contract.sh`

## 实测结果（2026-08-04 运行）

### 正式库

- `formal_database_opened=NO`
- 临时库路径：`/tmp/spotifylyrics-sck-s1-*.sqlite3`
- 正式库 SHA 前后均为  
  `73a260676cc61dd8aa70b4afe6eab6be1dbcf83c3c7541138f0b10a300055a64`

### Spotify 进程关系（SCShareableContent + ps）

- **捕获目标：** `com.spotify.client` pid=`18752` name=`Spotify`（`captureTarget=true`）
- 系统进程树中另有 Helper（Renderer / GPU / network / media 等），但 **SCShareableContent 未将 Helper 暴露为独立可捕获应用**；本 Spike **只把 `com.spotify.client` 列入 filter**，未硬编码 Helper。
- 首次宽松 name 匹配曾误列出 Safari 自动填充等，已收紧为 `com.spotify.*` 且排除 `com.spotifylyrics.*`。

### PCM 统计（播放中 ~18s）

摘自 `sck-spike.log`：

```text
STREAM configured capturesAudio=1 screenOutput=0 mic=0 sampleRate=48000 channels=2
STREAM started
PCM ... buffers=49  samples=47040  duration_s=0.980 inRate=48000.0 ch=2 peak=0.5664 rms=0.1968 active=true videoBuffers=0
...
PCM reason=final buffers=902 samples=865920 duration_s=18.040 inRate=48000.0 ch=2 peak=0.5685 rms=0.2572 active=true videoBuffers=0
STREAM stopCapture ok
TEMP cleanup ... exists_after=false
SPIKE stopped idle
```

### 验收勾选

| # | 要求 | 结果 |
|---|---|---|
| 1 | 播放时收到有效 audio buffer | **PASS**（peak≈0.57, rms≈0.25, active=true） |
| 2 | 来源限定 Spotify | **PASS**（filter 仅 `com.spotify.client`；DISCOVER 日志） |
| 3 | 无视频 output | **PASS**（`screenOutput=0`, `videoBuffers=0`） |
| 4 | 停止后不再增长 | **PASS**（auto-stop → final → stopped idle） |
| 5 | 不生成/保留音频文件 | **PASS**（仅 README marker，cleanup 后不存在） |
| 6 | App 可退出 | **PASS** |
| 7 | 未打开正式库 | **PASS** |

### 未在本轮自动化的场景（S1 部分手工/后续）

播放中自动 spike 已证明有有效音频。以下建议在本地再点一次 Debug 菜单做定性确认（不阻塞 S1 关闭）：

- 暂停 → active/peak 下降  
- 恢复 → 再次 active  
- 切歌 → 仍能收到 buffer（仍同一 client 进程）

## 法律与发布边界（重申）

- **技术可行 · 本地实验可行 · 正式发布需进一步条款／审核核验**
- 不宣称 Spotify ToS 或 App Store 已许可

## 规划更新（2.11B 路线）

| 阶段 | 内容 | 状态 |
|---|---|---|
| S0 | SCK 入口只读审计 | 完成 |
| **S1** | **ScreenCaptureKit PCM Spike** | **完成** |
| S2 | Spotify position + CapturedSegment + 不连续 | 未开始 |
| S3A | Speech + Partial 行级对齐 | 未开始 |
| S3B | 可靠识别锚点 + 锚点间强制对齐 | 未开始 |
| S3C | 仅当实测需要时再考虑人声分离实验 | 未开始 |
| S4 | 权限、状态、按需入口 | 未开始 |
| S5 | 日语 / 中英 / 纯音乐真实验收 | 未开始 |

**S1 完成后暂停，不自动进入 S2。**

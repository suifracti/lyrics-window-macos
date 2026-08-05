# MVP1 Final Live Acceptance

| 项 | 值 |
|---|---|
| 日期 | 2026-08-05 |
| 产品 | Lyric Island |
| 分支 | `codex/phase-2-11c-mvp1-auto-alignment` |
| 基线 HEAD（进场） | `984ec4a` |
| 出场 HEAD | `c2f6890` |
| App | `/Users/apple/backup/sptifylyrics/DerivedDataMVP1/Build/Products/Debug/SpotifyLyrics.app` |
| 进场 CDHash | `f3059984037e26abc6d0c673a5f5b3405e2f0382` |
| 出场 CDHash | `cd4981e02d74169b496b73daa3e16be3343deccd` |
| 签名 | Apple Development · Team `5RGL84U3V2` · `ENABLE_DEBUG_DYLIB=NO` · 非 ad-hoc |
| codesign verify | valid on disk · satisfies Designated Requirement |

## 最终准确状态

**A + B 均已获得真实证据 → MVP1 可标为完全验收。**

| 路径 | 状态 |
|---|---|
| **A. 真实 Spotify 产品路径：自动触发 → SCK 捕获 → 对齐 → accumulate → 部分进度** | **PASS** |
| **B. 受控短 fixture 产品路径：JobController → QualityGate completeAndAdopt → 子版本 → adopt → 同步跟播数据** | **PASS** |

未使用 `SPOTIFYLYRICS_AUTO_ALIGN_FORCE_COMPLETE=1`。  
未调用 `assist_start` / 验收 harness 代替产品触发。

---

## 1. 冻结构建与权限

- 优先使用既有 Development App；仅在确认产品 bug 后 rebuild 两次。
- TCC（`com.spotifylyrics.app`）：
  - `kTCCServiceAppleEvents` = allowed (2)
  - `kTCCServiceScreenCapture` = allowed (2)
  - `kTCCServiceAudioCapture` = allowed (2)
  - `kTCCServiceSpeechRecognition` = allowed (2)
- Whisper：
  - CLI `/opt/homebrew/bin/whisper-cli` 可用
  - 模型 `…/s0-5-engine-viability/whisper-models/ggml-small.bin`（ggml-small）可用
- 环境变量：`SPOTIFYLYRICS_WHISPER_CLI` · `SPOTIFYLYRICS_WHISPER_MODEL` · `SPOTIFYLYRICS_DATABASE_PATH`

## 2. TEMP / formal DB

| 项 | 值 |
|---|---|
| TEMP | `/tmp/spotifylyrics-mvp1-live/SpotifyLyrics.sqlite3` |
| temporary_copy | **YES** |
| formal_database_opened | **NO** |
| 正式库 SHA | `d6d5f121152057908ccd70cf4b83d8c76d86b9f4b9c9929326c45a60eb5f420b`（before = after） |

## 3. 当前歌曲（真实 Spotify）

| 字段 | 值 |
|---|---|
| Track | Knights of Cydonia · Muse |
| Spotify ID | `spotify:track:7ouMYWpwJ422jRcDASZB7P` |
| TrackIdentity | `spotify-id:7oumywpwj422jrcdaszb7p\|metadata:knightsofcydonia\|muse\|blackholesandrevelations\|366` |
| duration | 366.213 s |
| player | **playing**（产品路径期间） |

### 路径 A 歌词

- 初始 LRCLIB 返回 **sync=true** → gate `no_plain_or_already_synced`（正确拒绝）
- TEMP 改为 **20 行纯文本** `sync=false` → 满足自动触发
- `activeLyricsVersionID` 有值 · `isSynchronized == false` · 开关 `automaticAlignment.enabled.v1 == true`

### 路径 B 歌词（受控短 fixture）

- 同 TrackIdentity，**3 行纯文本副歌**（与真实捕获可对齐的句子）
- 仍经 **JobController + QualityGate + LiveCapture + Whisper**；非 repository 直写

---

## 4. Gate 条件（自动触发）

| # | 条件 | 路径 A 实测 |
|---|---|---|
| 1 | TrackIdentity 可靠 | true |
| 2 | isPlaying | true |
| 3 | 纯文本歌词已加载 | true（改 plain 后） |
| 4 | isSynchronized == false | true |
| 5 | automaticAlignment.enabled.v1 | true |
| 6 | evaluateTrigger 通过 | `AUTO_ALIGN gate=true` |
| 7 | AUTO_ALIGN start | logged |
| 8 | capturing | LiveCapture + SPIKE start |
| 9 | STREAM started | logged |
| 10 | 有效 PCM | 见下 |
| 11 | aligning | pipeline S3/S4 + Whisper |
| 12 | Whisper | `engineID=speechEngine.whisperCLI.experimental.v1` |
| 13 | S3/S4 report | draft + evidence `s3b:directSpeech` / `anchor:…` |
| 14 | quality gate | `accumulate`（A）/ `completeAndAdopt`（B） |

### 首次未触发时的真实 gate（禁止写“环境未就绪”）

| 现象 | 根因 |
|---|---|
| 有曲目但 LRCLIB 已同步 | `gate=false reason=no_plain_or_already_synced` |
| 开关已 write 但仍不跑 | **bug**：`evaluateTrigger` debounce 被 `currentTime` ~5Hz `objectWillChange` 永久重置 |
| 修复前无任何 AUTO_ALIGN 日志 | evaluate 从未执行 |

---

## 5. AUTO_ALIGN 状态轨迹

### 路径 A（部分）

```
gate=true → start → capturing (SCK)
→ aligning/evaluating
→ gate=accumulate timed=4/20 reason=partial_reliable_progress
→ AUTO_ALIGN accumulate timed=4
→ 无 adopt / 无 automaticAlignment 正式子版本
```

### 生命周期（真实产品路径）

| 操作 | 证据 |
|---|---|
| pause | `gate=false reason=not_playing state=capturing` → `state=paused`；`S2 PLAYBACK paused` |
| resume | 恢复后 `gate=true` → 新 `AUTO_ALIGN start` |
| seek | `SEGMENT end reason=seekBackward` + 新 `SEGMENT start`；`S2 SEEK … source=playbackNotify`；绝对 position 记录 |
| 关闭开关 | `gate=false reason=switch_off` + `AUTO_ALIGN cancel`；进度文件仍在 |
| 已同步后 | `gate=false reason=no_plain_or_already_synced`（B 采用后） |

### 路径 B（完整）

```
persistence hit plain 3 lines sync=false
→ gate=true → start
→ gate=completeAndAdopt reason=full_reliable_coverage timed=3/3
→ SESSION apply loaded source=automaticAlignment
→ SESSION adopt persisted version=159FF9BA…
→ AUTO_ALIGN completeAndAdopt version=159FF9BA
```

---

## 6. SCK 指标（路径 A 摘录）

| 指标 | 样本 |
|---|---|
| STREAM | started · capturesAudio=1 · 48000 Hz · 2 ch |
| PCM tick | buffers=649 · samples=623040 · duration_s≈12.98 |
| peak | ≈0.3878 |
| rms | ≈0.1669 |
| active | true |
| Spotify discover | `com.spotify.client` captureTarget=true |
| formal in spike | formal_db_opened=NO |

证据：`evidence/sck-partial-pcm-excerpt.txt`

## 7. Whisper / S4 指标

| 项 | 值 |
|---|---|
| Engine | `speechEngine.whisperCLI.experimental.v1` |
| 进度证据 | `s3b:directSpeech;s4:capture_ok` / `anchor:textSim=1.000;…;asr=observed` |
| quality | 0.75（medium class）写入 ProgressStore |

## 8. Progress 证明（A）

- 文件：`AutomaticAlignmentProgress` / `SPOTIFYLYRICS_AUTO_ALIGN_PROGRESS_DIR`
- key：identity + sourceContentHash 前缀
- `lastDecision=accumulate` · `timedLines` ≥ 4（20 行版）
- TEMP `lyrics_versions`：**无** `is_synced=1` 的 automaticAlignment 子版本（A 阶段）
- e2e：**无** `SESSION adopt` / `completeAndAdopt`
- 关开关后进度文件保留

## 9. completeAndAdopt 证明（B）

| 检查 | 结果 |
|---|---|
| gate | `completeAndAdopt` · `full_reliable_coverage` · timed=3/3 |
| 子版本 | `159FF9BA-…` · `source=automaticAlignment` · `is_synced=1` |
| 父版本 | `B42A528B-…` · `manualImport` · `is_synced=0` 保留 |
| parent_version_id | 指向父纯文本 |
| adoptPersisted | e2e `SESSION adopt persisted … source=automaticAlignment` |
| 重投影 | `SESSION apply loaded source=automaticAlignment lines=3` |
| FORCE_COMPLETE | **未使用** |

采用后时间轴（秒）：

| idx | start | text |
|---|---|---|
| 0 | 205.257 | Time has come to make things right |
| 1 | 212.257 | You and I must fight for our rights |
| 2 | 219.217 | You and I must fight to survive |

## 10. 跟播证明（B）

- Session 采用后 `isSynchronized=true`；auto-align 停止（gate=already_synced）
- Spotify 在 210→212→218→220 区间播放/暂停/seek 正常
- 时间轴落在 205–226 s，与 seek 区间重叠；主歌词使用现有同步投影路径
- 未录屏时：以 e2e 采用日志 + TEMP 行时间轴 + 播放位置为证据（见 `evidence/adopted-lines.txt`）

## 11. 修复提交

| Commit | 说明 |
|---|---|
| `c180cb6` | 门控失败日志；歌词 settle / 播放态变化后 `notePlaybackContextChanged`；UserDefaults 开关重同步 |
| `c2f6890` | **关键 bug**：将 evaluate debounce 改为 throttle，避免 `currentTime` 发布导致永不触发 |

Rebuild 后 CDHash：`cd4981e02d74169b496b73daa3e16be3343deccd`（仍 Team 5RGL84U3V2 · Apple Development）

## 12. 证据目录

`docs/phase-2-11c-zero-operation-alignment/mvp1-live-acceptance/`

- `ACCEPTANCE.md`（本文件）
- `evidence/e2e-complete.log`
- `evidence/e2e-partial-path-excerpt.txt`
- `evidence/sck-partial-pcm-excerpt.txt`
- `evidence/versions.txt` · `adopted-lines.txt`
- `evidence/formal-db.sha` · `temp-db.txt` · `whisper.txt` · `codesign.txt` · `commits.txt`

## 13. 限制（诚实）

1. 路径 B 使用**同曲 3 行受控纯文本 fixture**（仍真实 Spotify 音频 + 产品 JobController），非整首 20 行一次达 98%。
2. 连续 `accumulate` 后同一播放中会再次 start（补缺）；日志有 `job_already_running` 噪声，可在后续小修中降采样（非本验收阻塞）。
3. A→B→A 切歌串歌：本轮以 seek / pause / 关开关为主；切歌逻辑代码路径已在产品中接线（`notifyTrackChanged`），未单独长时间录 A→B→A 录像。

## 14. 结论

- **真实自动触发与部分续排：已验收**
- **完整自动采用（产品门控 + 子版本 + adopt + 同步数据）：已验收**
- **MVP1 完全验收：PASS**

完成后暂停。不进入 MVP2。

# Phase 2.11B-TCC Identity Fix — 最小探针成功

| 项 | 值 |
|---|---|
| 时间 | 2026-08-04T14:11:20Z |
| 结果 | **SUCCESS** |
| 规则 | 无 rebuild / 无重签名 / 无改 bundle |

## App（冻结）

| 项 | 值 |
|---|---|
| 路径 | `/Users/apple/backup/sptifylyrics/DerivedData/Build/Products/Debug/SpotifyLyrics.app` |
| Identifier | `com.spotifylyrics.app` |
| Authority | Apple Development → WWDR → Apple Root CA |
| TeamIdentifier | `5RGL84U3V2` |
| CDHash | `8c1a17a96ddf624616869ab89ec3374e41d6cdda` |
| adhoc | **否** |
| debug dylib | **ABSENT** |

## 探针结果

| 检查 | 结果 |
|---|---|
| DISCOVER | **YES** — `primary=1 captureTargets=1` Spotify `com.spotify.client` |
| STREAM started | **YES** |
| SPIKE failed | **NO** |
| 捕获时长 | **12.06 s**（`SPOTIFYLYRICS_SCK_SPIKE_SECONDS=12`） |
| PCM | **VALID** — buffers=603 samples=578880 peak=0.7838 rms=0.2626 active=true ch=2 48kHz |
| videoBuffers | 0（仅音频） |
| 麦克风 | 未开（policy: no-mic） |
| TEMP cleanup | `exists_after=false` |
| wav_remaining | **0** |
| formal_db_opened | **NO** |

## 日志摘录

```text
DISCOVER related=1 primary=1 captureTargets=1
DISCOVER_APP pid=18752 bundle=com.spotify.client name=Spotify captureTarget=true
STREAM configured capturesAudio=1 screenOutput=0 mic=0 sampleRate=48000 channels=2
STREAM started
PCM reason=final … duration_s=12.060 … peak=0.7838 … active=true videoBuffers=0
STREAM stopCapture ok reason=auto-stop
TEMP cleanup … exists_after=false
SPIKE stopped idle
```

## 本阶段状态

- TCC Identity Fix：**稳定签名 + 最小探针通过**
- **暂停** — 不自动进入完整 A/B Acceptance Closure

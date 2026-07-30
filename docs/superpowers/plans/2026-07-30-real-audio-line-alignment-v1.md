# Real Audio Line Alignment V1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将“已知纯文本歌词 + 用户选择的完整本地音频”转换为有真实语音证据的逐行时间轴，并通过预览、编辑、确认、SQLite/本地 LRC 保存和重启恢复完成可验收闭环。

**Architecture:** 保留现有 `AlignmentService` 作为 SwiftUI 与识别后端之间的边界；在其后增加带时间的 transcript 抽象和确定性的动态规划行对齐器。音频只在当前任务中读取并转换为临时 PCM，结果先进入 `LyricsSessionController` 的预览状态，再由现有 LyricsEditor 修正和保存。SQLite 继续使用当前 v3 的 `parent_version_id`，不执行 migration v4；对齐引擎参数、音频 hash 和逐行 evidence 通过独立的应用支持目录 provenance sidecar 与 LRC 注释保存。

**Tech Stack:** Swift 5/Swift Concurrency、SwiftUI/AppKit、AVFoundation/CoreMedia、Speech framework、Foundation、SQLite3 actor repository、现有 LyricsEditor/LRC parser。

## Global Constraints

- 只处理用户主动选择的本地 `mp3`、`m4a`、`wav`、`flac`、`aiff` 音频；不下载歌曲、歌词或 Spotify 音频，不读取 DRM 流。
- 旧的 TTS fixture 不得进入真实 App 排轴路径；synthetic transcript/audio 只能用于标明为 `TEST` 的合同测试。
- 不生成逐字、音节或音素级时间轴；V1 只生成逐行 `startTime`、`endTime`、confidence、status 和 evidence。
- 不使用歌曲总时长平均铺开歌词；没有直接证据且没有两侧真实 anchor 的行不能被伪造计时。
- 原始歌词、kana、romaji、translation 保持独立；对齐只写时间层，不改写原文和读音层。
- Spotify Desktop 播放、播放位置和既有 Provider/UI 架构不重做；所有 seek 必须来自用户明确的试听或编辑操作。
- 低置信结果只能进入预览或未锁定版本；不得无提示自动锁定。
- 原始音频不复制到 App 数据目录、不修改；临时 PCM 和中间文件在成功、失败、取消和 App 退出路径清理。
- 现有 locked 纯文本/Provider 版本不被覆盖；对齐结果必须是新的子版本，且记录 parent version 与 source content hash。
- 本轮不执行 SQLite migration v4。若以后要求把 alignment engine、parameters、audio hash 全部变成 SQLite 列，必须另开 migration v4 设计，不能把 JSON 塞进 `raw_text` 或伪装成歌词正文。

---

## 当前代码审计结论

| 组件 | 当前状态 | 本轮处理 |
|---|---|---|
| `AlignmentService` / `AlignmentRequest` / `AlignmentReport` | 已写源码、已进入 App target、已接入 `PlaybackState` | 保留协议；增加源版本指纹、音频元数据、参数和逐行 evidence |
| `AudioPCMConverter` | 已写源码、已进入 target；支持 hash、临时 16 kHz mono WAV、ffmpeg/AVFoundation fallback | 保留能力；补充 streaming hash、采样率/声道读取、取消终止、扩展名/UTType 和安全清理 |
| `SpeechForcedAlignmentService` | 已写源码、已进入 target；使用 `SFSpeechRecognizer` segment | 拆出 timed transcript 后端；保留 Speech 取消桥接，禁止把无证据结果交给平均回退 |
| `LineForcedAligner` | 已写源码、已进入 target；当前是 greedy fuzzy window + 未匹配插值 | 替换为全局单调 DP；删除 `spreadLowConfidence` 和全局/尾部平均铺开 |
| `LyricsSessionController` | 已接入 running/preview/confirm 状态 | 增加 source version/revision guard；确认时创建子版本，不调用会被 locked 版本拦截的通用 save |
| `LocalAlignedLyricsStore` | 已能写带 hash/model/confidence/lock 注释的 `.aligned.lrc` | 改为唯一版本文件名，补齐参数/evidence 注释和原版本保护 |
| SQLite | 当前 schema v3，已有 `parent_version_id`、`is_synced`、`is_manually_edited`、`is_locked` | 不迁移；新增对齐专用事务保存方法，provenance 由 sidecar 保存 |
| `LyricsEditorSessionController` / `LyricsEditorWindowView` | 已有时间编辑、试听 seek、校验、另存和锁定 | 复用编辑器承载对齐修正；增加对齐上下文、confidence/evidence 显示和“未锁定/锁定”边界 |
| `Tests/line_alignment_contract.swift` | 已覆盖匹配、重复/前置基本行为和时长 mismatch | 现有“尾部必须插值”的断言与新安全要求冲突，必须改为“无边界证据则失败/不产出时间轴” |
| `kawasaki_tts.wav` | 历史实验 fixture；79.8 秒，不匹配约 171.2 秒商业歌曲 | 保留历史审计记录但标记为 INVALID；不得用于真实 App 或成功验收 |

### 必须删除或冻结的旧路径

1. 删除 `LineForcedAligner.spreadLowConfidence` 及其所有调用；`tokens.isEmpty`、全行无匹配、leading unmatched、trailing unmatched 都不能按歌曲总时长生成时间。
2. 删除或冻结 `SPOTIFYLYRICS_AUTO_ALIGN=1` 的自动触发钩子，避免历史 fixture 或环境变量在用户未明确操作时启动排轴。`SPOTIFYLYRICS_ALIGN_AUDIO` 仅保留为 Debug 测试 override，且仍经过完整时长、身份和歌词版本预检。
3. `LocalAudioASRService` 继续作为已有“从音频生成歌词草稿”的独立实验代码，但不再作为本轮“已知歌词强制对齐”的后端，也不作为真实验收证据。
4. 历史 `kawasaki_tts.wav` 不删除历史文档，但在新的合同和运行脚本中不得引用；任何带 `tts`、`synth` 或不匹配时长的音频只允许出现在 `TEST` 夹具说明中。

## 关键数据与接口决定

### 1. Timed transcript

新增 `SpotifyLyrics/Lyrics/TimedTranscript.swift`：

```swift
public struct TimedTranscriptSegment: Equatable, Sendable {
    public let index: Int
    public let text: String
    public let startTime: TimeInterval
    public let endTime: TimeInterval
    public let confidence: Double
}

public struct TimedTranscript: Equatable, Sendable {
    public let backendID: String
    public let segments: [TimedTranscriptSegment]
    public let audioDuration: TimeInterval
}

public protocol TimedTranscriptProvider: Sendable {
    var id: String { get }
    func transcribe(
        pcmURL: URL,
        localeIdentifier: String,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> TimedTranscript
}
```

`SpeechTimedTranscriptProvider` 使用现有 `SFSpeechRecognizer`，把 `SFTranscriptionSegment` 转为上述模型；识别失败、没有 segment、取消和超时都明确分类。合同测试使用内存 `TimedTranscriptProvider`，不启动 Speech、不使用 TTS。

### 2. 行证据与报告

扩展 `AlignmentModels.swift`：

```swift
public struct AlignmentParameters: Codable, Equatable, Sendable {
    public let algorithmVersion: String
    public let recognizerID: String
    public let localeIdentifier: String
    public let sampleRate: Int
    public let channels: Int
    public let maxWindowSegments: Int
    public let minimumDirectScore: Double
}

public struct AlignmentLineEvidence: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case directSpeech, boundedInterpolation, noEvidence }
    public let kind: Kind
    public let segmentStartIndex: Int?
    public let segmentEndIndex: Int?
    public let transcriptConfidence: Double?
    public let matchScore: Double
    public let note: String
}
```

`AlignedLyricLine` 增加 `evidence`；`AlignmentReport` 增加 `sourceVersionID`、`sourceContentHash`、`parameters`、`sampleRate`、`channels` 和报告级 evidence。当前 `startTime`/`endTime` 仍只在可物化的行上为有效值；未解决的前置/尾部/全无证据情况直接返回 `AlignmentError.insufficientEvidence`，不制造零时间或平均时间。两侧 anchor 之间确实发生漏识别时允许 bounded interpolation，但 status 必须是 `interpolated`、confidence 降级并记录两侧 anchor，不得称为直接识别。

### 3. 动态规划对齐

`LineForcedAligner` 的新公开接口为：

```swift
public struct LineAlignmentResult: Equatable, Sendable {
    public let lines: [AlignedLyricLine]
    public let skippedTranscriptSegmentIndices: [Int]
    public let unresolvedLineIndices: [Int]
    public var isComplete: Bool { unresolvedLineIndices.isEmpty }
}

public static func align(
    lines: [LyricLine],
    transcript: TimedTranscript,
    audioDuration: TimeInterval,
    parameters: AlignmentParameters
) -> LineAlignmentResult
```

算法先用官方 `kanaText`，否则只使用已确认的本地 reading layer；没有可靠读音时保留原文可比部分并将该行标为低置信，不用中文猜读音。DP 状态按歌词行和 transcript segment 游标单调推进，允许跳过插入语/纯音乐对应的 transcript segment，使用连续 segment window 匹配一行，重复副歌通过全局路径而不是局部最高分决定出现次序。直接命中取首尾 segment 时间；仅在前后均有真实 anchor 的连续漏唱行上做有界插值；没有前/后 anchor 的行列入 `unresolvedLineIndices`，服务层返回失败，不进入保存。

### 4. SQLite 与 provenance（不做 migration v4）

新增 `AlignmentPersistenceRequest` 与 `LyricsRepository.saveAlignedVersion(_:)`。SQLite 事务内检查：

- `TrackIdentity` 与当前 Track 一致；
- `parentVersionID` 属于当前 stableKey；
- parent 的纯文本内容 hash 等于 `AlignmentReport.sourceContentHash`；
- 原文/kana/romaji 行集合和数量与 parent 一致；
- 所有 start/end 单调、有限、不超过音频/歌曲时长；
- 低置信可以保存为未锁定，但不能由该 API 自动锁定；
- duplicate 只按新 alignment version 的 source/provider/content hash 返回 duplicate，不因 parent locked 而跳过创建子版本。

新版本使用现有 v3 字段：`source = automaticAlignment`、`parent_version_id = 原纯文本版本`、`is_synced = 1`、`is_manually_edited = 1`（用户确认后的本地结果）、`is_locked` 只由明确的锁定动作设置，`content_hash` 使用带时间轴的新版本 hash。原纯文本版本保持不变。

新增 `SpotifyLyrics/Persistence/AlignmentProvenanceStore.swift`，写入：

`~/Library/Application Support/SpotifyLyrics/AlignmentProvenance/<lyricsVersionID>.json`

内容只包含 version/parent ID、source content hash、audio SHA-256、测得时长/采样率/声道、engine/parameters、createdAt、overall confidence 和每行 status/evidence；不保存音频路径、不复制音频、不保存整段 transcript。先写临时文件再原子 rename；SQLite 插入失败清理临时 provenance，provenance 最终写入失败则执行补偿删除并向 UI 报错，避免显示一个没有完整 provenance 的“成功”版本。LRC 注释同步写入相同的脱敏 provenance 摘要。

> 这是本计划唯一需要用户确认的边界：如果要求所有 provenance 字段必须在 SQLite 表中，而不是 sidecar，则必须解除“本轮不得执行 migration v4”的限制；本计划不会绕过该限制。

---

## Task 1: Red contracts and legacy safety freeze

**Files:** Modify `Tests/line_alignment_contract.swift`, `Tests/line_alignment_contract.sh`, `Tests/alignment_wiring_contract.sh`; create `Tests/real_audio_line_alignment_contract.swift`, `Tests/real_audio_line_alignment_contract.sh`.

- [ ] **Step 1: Add failing assertions before production changes.**
  - Empty transcript, all-unmatched lines, leading unmatched and trailing unmatched must return `isComplete == false` or throw `insufficientEvidence`; no output may contain evenly spaced timestamps.
  - A valid sequence with intro, interlude, repeated chorus, skipped transcript segment and one bounded missing line must retain monotonic times and mark the missing line `boundedInterpolation`.
  - Every direct line must carry a segment range; every line must carry a non-empty evidence kind; original text remains byte-for-byte unchanged.
  - Duration mismatch, fragment input, empty lyrics, identity mismatch, already synchronized input, and locked-save attempts must reject before persistence.
- [ ] **Step 2: Run the contracts and record the expected red failures.**
  Run: `bash Tests/line_alignment_contract.sh` and `bash Tests/real_audio_line_alignment_contract.sh`.
  Expected: the old tail-spread assertions and missing new evidence API fail; no code is changed to hide a failure.
- [ ] **Step 3: Add the synthetic transcript provider used only by the contract.**
  The fixture provider returns hard-coded timed Japanese/Latin segments and never reads a commercial audio file or calls an external service. The shell wrapper compiles only production alignment models plus the fixture provider and test main.

## Task 2: Audio input preflight and temporary PCM lifecycle

**Files:** Modify `SpotifyLyrics/Lyrics/AudioPCMConverter.swift`, `SpotifyLyrics/Lyrics/AlignmentModels.swift`, `SpotifyLyrics/Services/PlaybackState.swift`; create `SpotifyLyrics/Lyrics/AudioInputMetadata.swift` and `Tests/audio_pcm_contract.sh` / `Tests/audio_pcm_contract.swift`; update `SpotifyLyrics.xcodeproj/project.pbxproj`.

- [ ] **Step 1: Add an `AudioInputMetadata` value type.**
  It reports original URL only in memory, measured duration, sample rate, channel count, optional embedded title/artist, supported extension/UTType and SHA-256. Missing title/artist is a visible warning requiring explicit user continuation; present mismatching title/artist is a hard rejection.
- [ ] **Step 2: Make `AudioPCMConverter.prepare` cancellation-safe.**
  Hash via a streaming `FileHandle`, probe AVFoundation metadata, create a UUID temp directory, convert to 16 kHz mono WAV, and terminate a running ffmpeg process on cancellation. `defer` removes the temp directory on every exit path. Verify source hash/stat before and after conversion; never write beside the source file.
- [ ] **Step 3: Expand the picker and preflight.**
  Use dynamic UTTypes for mp3/m4a/wav/flac/aiff plus extension validation in the converter. Keep `SPOTIFYLYRICS_ALIGN_AUDIO` only as a Debug explicit-file override; remove the `SPOTIFYLYRICS_AUTO_ALIGN` auto-start hook. The user must click the existing alignment action and see measured title/artist/duration/hash prefix before recognition starts.
- [ ] **Step 4: Run audio contracts.**
  Generate a short `TEST` PCM WAV in the test temporary directory, verify conversion/hash/duration/sample rate/channels, verify the source bytes and modification time remain unchanged, verify temp files disappear, and verify invalid extension/zero-length/cancel paths leave no result.

## Task 3: Transcript backend and DP line matcher

**Files:** Create `SpotifyLyrics/Lyrics/TimedTranscript.swift`; modify `SpotifyLyrics/Lyrics/SpeechForcedAlignmentService.swift`, `SpotifyLyrics/Lyrics/LineForcedAligner.swift`, `SpotifyLyrics/Lyrics/AlignmentModels.swift`, `SpotifyLyrics/Lyrics/JapaneseKanaGenerator.swift` only if the existing confirmed-reading API needs a read-only adapter; update `SpotifyLyrics.xcodeproj/project.pbxproj`.

- [ ] **Step 1: Define the timed transcript protocol and Speech adapter.**
  Move callback-based `SFSpeechRecognizer` work behind `TimedTranscriptProvider`. Preserve one-shot continuation settlement, task cancellation, timeout, authorization and recognizer availability classification. Reject empty/invalid/non-monotonic segments instead of manufacturing tokens.
- [ ] **Step 2: Replace greedy alignment with global DP.**
  Implement line/window match scores using normalized kana/romaji/text, transcript confidence, length and version-token penalties. Add explicit skip transitions for inserted speech and a monotonic path tie-breaker for repeated lyrics. Do not use model-generated time guesses.
- [ ] **Step 3: Remove average fallback.**
  Delete `spreadLowConfidence`; never call `Double(index) * duration / count`. Return bounded interpolation only between real anchors; unresolved boundary/all-unmatched rows make the report incomplete and throw `AlignmentError.insufficientEvidence` in the service layer.
- [ ] **Step 4: Add scoring and evidence tests.**
  Run `bash Tests/line_alignment_contract.sh` and `bash Tests/real_audio_line_alignment_contract.sh`; expected output includes direct/interpolated statuses, monotonic time assertions, repeated-chorus path assertions and explicit no-average assertions.

## Task 4: Identity-bound service/session lifecycle

**Files:** Modify `SpotifyLyrics/Lyrics/AlignmentService.swift`, `SpotifyLyrics/Lyrics/SpeechForcedAlignmentService.swift`, `SpotifyLyrics/Services/PlaybackState.swift`, `SpotifyLyrics/Services/LyricsSessionController.swift`, `SpotifyLyrics/Lyrics/LyricsModels.swift`; update `Tests/alignment_wiring_contract.sh` and create `Tests/alignment_session_contract.swift` / `.sh`.

- [ ] **Step 1: Extend `AlignmentRequest`.**
  Carry `sourceVersionID`, `sourceContentHash`, source synchronized state, current TrackIdentity metadata, selected audio metadata, and duration hint. The service rejects a synchronized source or an empty/changed source before recognition.
- [ ] **Step 2: Inject `AlignmentService` into `PlaybackState`.**
  Keep `SpeechForcedAlignmentService` as production default and allow a test fake. Capture identity, lyrics-session revision, source version ID/hash and playback position before the first await. Every progress and result callback must recheck all four guards; a stale result is discarded and never persisted.
- [ ] **Step 3: Preserve plain lyrics during processing.**
  `alignmentRunning` keeps the original plain document visible. Cancel, decode failure, ASR failure, insufficient evidence, identity change, app termination or database failure returns to that exact plain document and leaves no new version.
- [ ] **Step 4: Keep all playback changes explicit.**
  Alignment start/finish/cancel never calls `seek`, never resets the playback anchor, and never changes Spotify transport. Only the existing “试听/记当前行/seek” editor actions may seek.
- [ ] **Step 5: Run lifecycle contracts.**
  Fake services cover quick A→B switching, cancellation, failure, no persistence before confirmation, unchanged playback time, and late progress/result suppression.

## Task 5: Versioned persistence and provenance

**Files:** Modify `SpotifyLyrics/Persistence/LyricsRepository.swift`, `SpotifyLyrics/Persistence/SQLiteLyricsRepository.swift`, `SpotifyLyrics/Persistence/LyricsPersistenceMapper.swift`, `SpotifyLyrics/Persistence/DatabaseModels.swift`, `SpotifyLyrics/Lyrics/LocalAlignedLyricsStore.swift`; create `SpotifyLyrics/Persistence/AlignmentProvenanceStore.swift`, `Tests/alignment_persistence_contract.swift`, `Tests/alignment_persistence_contract.sh`; do not modify `DatabaseMigrator.swift` or schema version.

- [ ] **Step 1: Add the repository DTO and protocol method.**
  `AlignmentPersistenceRequest` contains Track, identity, parent version ID, parent source hash, aligned document, full report and explicit lock flag. Add an async repository method with a default unsupported implementation for test repositories.
- [ ] **Step 2: Implement one-transaction SQLite save.**
  Validate parent identity/hash/line set, create a new automatic-alignment version with v3 parent relation, insert all timed lines, and return `inserted`/`duplicate`/`rejected`. Do not call the generic `hasLockedVersion` guard because a locked parent must remain immutable while still allowing a new child. Reject incomplete reports and never insert empty/partial versions.
- [ ] **Step 3: Implement atomic provenance sidecar.**
  Store only non-sensitive IDs, hashes, durations, model/parameters, timestamps, statuses and segment index ranges. On any database/provenance failure, remove temporary/fresh artifacts; on restart, loading a version may display provenance status as unavailable rather than guessing it.
- [ ] **Step 4: Make local LRC output version-safe.**
  Include source parent/hash, engine version, measured audio metadata, parameters, evidence summary, confidence and lock state in comments. Use an audio-hash/version suffix so a new alignment never overwrites a prior non-locked file accidentally; locked files remain immutable.
- [ ] **Step 5: Run persistence/restart contracts.**
  Use a temporary SQLite and provenance directory. Verify parent plain version survives, child points to parent, locked parent is not changed, low-confidence child is not locked, duplicate content does not duplicate, restart restores the child and sidecar, and failed writes leave no rows/files.

## Task 6: Existing LyricsEditor correction path and restrained preview UI

**Files:** Modify `SpotifyLyrics/Editor/LyricsEditorModels.swift`, `SpotifyLyrics/Editor/LyricsTimelineValidator.swift`, `SpotifyLyrics/Services/LyricsEditorSessionController.swift`, `SpotifyLyrics/Services/PlaybackState.swift`, `SpotifyLyrics/Views/Editor/LyricsEditorWindowView.swift`, `SpotifyLyrics/Views/Components/LyricsCanvasView.swift`, `SpotifyLyrics/Views/MainWindow/MainLyricsWindowView.swift`, `SpotifyLyrics/Views/MainWindow/AppleMusicImmersiveV3WindowView.swift`; create `SpotifyLyrics/Views/Components/AlignmentPreviewView.swift`; update `SpotifyLyrics.xcodeproj/project.pbxproj`.

- [ ] **Step 1: Add an alignment editor context without creating a second editor.**
  The shared editor session stores parent version ID/hash, AlignmentReport and target source. It can materialize the complete preview into the existing row draft, keeps original/kana/romaji/translation separate, and never changes the current TrackIdentity when Spotify changes.
- [ ] **Step 2: Strengthen alignment save validation.**
  For an alignment draft, every nonblank row must have finite start time, optional end time must be `>= start`, starts must be monotonic and within measured audio/track duration, and source line index/text set must still match the parent. No operation silently shifts neighboring rows or averages missing values.
- [ ] **Step 3: Render per-line preview information.**
  The existing alignment status area gets a compact `AlignmentPreviewView`: row number, original text, start/end, confidence, status and evidence range/note; low-confidence/interpolated rows are highlighted. Adjacent V2/V3 visual systems are not redesigned.
- [ ] **Step 4: Separate user actions.**
  Provide `试听当前行`, `进入编辑器`, `保存为待人工复核`, `保存并锁定`, and `放弃`. The lock action is disabled when any row is low-confidence/interpolated/unresolved or when validation fails; no result is auto-locked merely because recognition completed.
- [ ] **Step 5: Reconnect the confirmed result.**
  After a successful repository save, call `LyricsSessionController.adoptPersisted` with the new child version and source hash. Before confirmation the plain document remains the active persisted version. On A→B switch, the editor displays the existing stale warning and refuses the save.
- [ ] **Step 6: Run editor/UI contracts.**
  Extend `Tests/lyrics_editor_contract.sh` and `Tests/alignment_wiring_contract.sh` to verify row seek uses its timestamp, no alignment button performs a seek on open/confirm, low-confidence rows cannot be silently locked, and V2/V3/lyrics-focus continue to use shared playback/lyric state.

## Task 7: Real audio acceptance, build and delivery gate

**Files:** Create/update `docs/superpowers/specs/acceptance-2026-07-30-real-audio-line-alignment-v1/README.md`; update `task_plan.md`, `findings.md`, `progress.md` only after implementation and acceptance; no new Provider or visual redesign files.

- [ ] **Step 1: Collect the user-provided audio precondition.**
  The file must be the complete vocal recording corresponding to the current TrackIdentity, not TTS, spoken reading, preview clip, instrumental, remix or another release. It must be locally readable, with measured duration within the configured tolerance of the Spotify duration; embedded title/artist, when present, must match, and the app must show the file hash prefix before processing.
- [ ] **Step 2: Run one real-song acceptance only when the file is available.**
  Use the current song/lyrics version selected by the user. Record measured duration, sample rate, channels, SHA-256 prefix, source lyrics version ID/hash, transcript segment count, each line’s start/end/confidence/status/evidence and overall confidence. Do not include complete lyrics, API keys or audio contents in logs.
- [ ] **Step 3: Verify playback behavior.**
  From the beginning, check first lyric is not before the first vocal evidence, intro/interlude gaps remain quiet, repeated chorus follows the correct occurrence, there is no cumulative drift in the middle, and the last lyric ends near the final vocal evidence. Confirm alignment does not change Spotify playback position.
- [ ] **Step 4: Verify persistence and recovery.**
  Confirm once, restart the exact App, reload the child version, inspect SQLite parent/child rows and provenance sidecar, verify original plain version remains, then test an explicit manual correction and lock without overwriting the parent.
- [ ] **Step 5: Build and commit only after gates.**
  Run all alignment, editor, SQLite, reading and existing regression contracts; clean/rebuild Debug at `/Users/apple/backup/sptifylyrics/DerivedData`; run normal `xcodebuild`, `codesign --verify --deep --strict`, verify process origin from the absolute App path, inspect `git diff --check` and commit one independent change. If no matching real audio is supplied, report code/tests/build status but leave “commercial real-song acceptance” explicitly unverified and do not claim the target song is aligned.

## Acceptance Matrix

| Scenario | Expected result |
|---|---|
| Complete matching vocal audio + known plain lyrics | Preview contains 1 row per lyric, monotonic time, evidence for every row, no fake average timing |
| Intro/interlude/outro | No lyric row is created for silence; next row starts at real evidence |
| Repeated chorus | DP chooses monotonic occurrence order; duplicate text is not collapsed |
| Inserted ASR phrase / missed lyric inside anchors | Inserted segment is skipped; missed line is bounded-interpolated and low confidence |
| Missed first/last line or all transcript empty | Alignment fails safely; plain lyrics remain; no timestamp or version is written |
| Duration mismatch / fragment | Preflight rejects before Speech/DP and leaves source unchanged |
| A→B track switch / cancellation | Old task/result/provenance cannot reach B; no stale version is written |
| Low-confidence result | Preview/optional unlocked save only; explicit warning; lock disabled |
| Locked parent | Parent unchanged; child creation is allowed only through explicit alignment save and never by overwrite |
| App restart | Selected confirmed child and its provenance restore; missing provenance is reported, not guessed |
| TTS/synthetic fixture | Contract-only, visibly marked TEST; never commercial acceptance evidence |

## Real Audio Conditions Required From User

- A complete local vocal file for the exact Spotify recording currently identified by the App.
- The file path can be selected through the existing “自动排轴” picker; the path need not be sent in chat.
- File duration must be close to the Spotify duration; for `水曜日の約束 / Kawasaki.Rio`, the known target is about 171 seconds, so the historical 79.8-second TTS fixture is explicitly invalid.
- Speech recognition permission must be granted for the App, and the file must contain audible vocals rather than only instrumental audio.
- If the file’s embedded title/artist metadata is absent, the App will show a warning and require explicit user confirmation; it will not infer identity from the filename alone.

## Self-review against the request

- Current code audit, reusable components, frozen average/TTS paths, ASR/DP plan, data/provenance changes, file plan and real-audio preconditions are all covered above.
- No Provider, QueryPlanner, SafeMatcher, AI HTTP, main-window visual, migration v4, download, system capture or word-level timing work is included.
- The only unresolved product decision is whether provenance must be in SQLite; that conflicts with the explicit no-migration-v4 boundary and is surfaced before implementation.

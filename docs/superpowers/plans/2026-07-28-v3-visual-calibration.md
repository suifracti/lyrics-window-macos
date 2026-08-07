# Apple Music Immersive V3 Visual Calibration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 在现有 Apple Music Immersive V3 中完成背景空间层次、同步歌词景深、辅助读音显隐和播放器间距的最后一轮视觉校准。

**Architecture:** 保留现有 `AppleMusicImmersiveV3WindowView`、`AppleMusicImmersiveV3BackdropView`、`AppleMusicImmersiveV3BackdropCache` 和当前播放/歌词接线。仅在 V3 的 SwiftUI 图层和现有缓存背景结果的显示组合上做局部调整；无时间轴继续走独立全文阅读分支。

**Tech Stack:** SwiftUI、AppKit `NSImage`、CoreGraphics/ImageIO、Swift shell 合同测试、xcodebuild。

## Global Constraints

- 不新增 V4，不重写架构。
- 不修改 V2、歌词专注模式、Provider、搜索、设置、自动排轴、播放同步、TrackIdentity 或 Ruby/罗马音生成。
- 背景只在 Track identity/artwork 变化时通过现有异步缓存生成；播放位置不得触发背景计算。
- 无时间轴歌词不得伪造当前行、景深、自动滚动或同步状态。
- 相邻同步歌词不得使用 blur；距离两行以上才允许轻微 blur，主歌词必须保持可读。

---

### Task 1: Add failing V3 visual calibration contract

**Files:**
- Modify: `Tests/apple_music_immersive_v3_contract.sh`

- [ ] **Step 1: Add assertions for the intended visual thresholds and auxiliary-layer distance rules**

Assert the source contains the new opacity/blur bands, distance-based Ruby/romaji visibility, cached artwork layers, unchanged cache task key, and unchanged `1152×720`/`800×600` constraints.

- [ ] **Step 2: Run the contract and verify it fails for the current values**

Run: `Tests/apple_music_immersive_v3_contract.sh`
Expected: FAIL because the current V3 still uses the old neighbor opacity/blur and renders auxiliary layers for all synchronized rows.

### Task 2: Calibrate the cached V3 backdrop

**Files:**
- Keep unchanged: `SpotifyLyrics/Design/BackdropPalette.swift` (shared by V2)
- Modify: `SpotifyLyrics/Views/Components/AppleMusicImmersiveV3BackdropView.swift`

- [ ] **Step 1: Keep the shared palette sampler unchanged**

Do not change `BackdropPalette.swift`, because V2 also consumes it. Keep its existing three-color result and make the V3-specific texture, glow, veil and vignette provide the additional spatial separation.

- [ ] **Step 2: Adjust only the V3 artwork layer composition**

Keep `task(id: requestKey)`, `AppleMusicImmersiveV3BackdropCache`, `Task.detached(priority: .utility)`, the 320px thumbnail and noise cache. Make the low-resolution artwork texture and left glow more visible, keep a stable trailing lyric veil and vignette, and do not use playback position in any key or task.

- [ ] **Step 3: Run the backdrop and V3 contracts**

Run: `Tests/apple_music_immersive_v3_contract.sh && Tests/real_track_lyrics_contract.sh`
Expected: PASS, with only the repository's existing Sendable warnings if emitted by the contract compiler.

### Task 3: Calibrate synchronized lyric depth and V3 transport details

**Files:**
- Modify: `SpotifyLyrics/Views/MainWindow/AppleMusicImmersiveV3WindowView.swift`

- [ ] **Step 1: Implement explicit synchronized distance bands**

Keep the existing current-line index and `scrollTo(... y: 0.47)` path. Set adjacent rows to readable opacity with no blur, two-away rows to approximately 1pt blur, and farther rows to a capped approximately 2pt blur. Keep current-line dynamic sizing unchanged.

- [ ] **Step 2: Hide only distant auxiliary layers**

For synchronized rows, keep full Ruby and romaji on the current row, retain subdued Ruby/romaji on the adjacent row, and hide Ruby plus hide or minimize romaji at distance two or more. For unsynchronized rows, render the existing full reading surface unchanged.

- [ ] **Step 3: Make only small transport adjustments**

Preserve left-edge alignment and playback actions. Slightly enlarge the transport buttons, tune the control/time spacing, and do not add a capsule/card background.

- [ ] **Step 4: Run the V3 contract**

Run: `Tests/apple_music_immersive_v3_contract.sh`
Expected: PASS.

### Task 4: Build and run the complete regression suite

**Files:**
- No production files beyond Tasks 2–3.

- [ ] **Step 1: Run `git diff --check` and inspect the diff stat**

Run: `git diff --check && git diff --stat`
Expected: only the approved V3 files, the contract, and acceptance documentation are changed.

- [ ] **Step 2: Build the normal signed Debug App**

Run: `xcodebuild -project SpotifyLyrics.xcodeproj -scheme SpotifyLyrics -configuration Debug -derivedDataPath /Users/apple/backup/sptifylyrics/DerivedData build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Run every `Tests/*.sh` contract**

Run: `for test in Tests/*.sh; do "$test"; done`
Expected: all contracts pass.

### Task 5: Real V3 acceptance and commit

**Files:**
- Modify: `docs/archive/planning/task_plan.md`

- [ ] **Step 1: Launch only the absolute DerivedData App and record its process path**

Use `/Users/apple/backup/sptifylyrics/DerivedData/Build/Products/Debug/SpotifyLyrics.app`, verify the running executable path and keep the Spotify play position unchanged during visual checks.

- [ ] **Step 2: Capture real visual evidence**

Capture `春を告げる / yama` at beginning/middle/end, `水曜日の約束 / Kawasaki.Rio` as unsynchronized full text, purple/warm and blue/green artwork cases, default size and minimum size. Check mode switching does not reset the lyrics session and sample CPU/threads for absence of a new realtime high-radius blur loop.

- [ ] **Step 3: Update acceptance evidence and verify signing**

Record the absolute App path, `git diff --stat`, key diff summary, build result, `codesign --verify --deep --strict`, runtime logs and screenshots in `docs/archive/planning/task_plan.md`.

- [ ] **Step 4: Commit only the approved V3 calibration changes**

```bash
git add SpotifyLyrics/Design/BackdropPalette.swift \
  SpotifyLyrics/Views/Components/AppleMusicImmersiveV3BackdropView.swift \
  SpotifyLyrics/Views/MainWindow/AppleMusicImmersiveV3WindowView.swift \
  Tests/apple_music_immersive_v3_contract.sh docs/archive/planning/task_plan.md
git commit -m "Calibrate Apple Music immersive V3 depth"
```

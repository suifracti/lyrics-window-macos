# V3 Album Ambient Backdrop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the default giant enlarged-cover backdrop with the approved album-derived ambient field while preserving a one-switch legacy fallback.

**Architecture:** `AppSettingsStore` owns one persistent Boolean. The V3 backdrop keeps the legacy renderer intact and adds a separate ambient renderer using a low-resolution cached artwork texture, luminance-clamped palette colors, directional light, readability veil, and existing noise. The current track-bound cache remains the only artwork pipeline.

**Tech Stack:** SwiftUI, AppKit, ImageIO, UserDefaults, shell contracts.

## Global Constraints

- Modify V3 only; do not modify Direction D/V4.
- Do not add playback-time-dependent rendering.
- Do not run `generate_xcodeproj.py`.
- The legacy backdrop must remain selectable without rebuilding.

---

### Task 1: Lock the ambient/legacy behavior

**Files:**
- Create: `Tests/v3_ambient_backdrop_contract.sh`
- Modify: `SpotifyLyrics/Settings/AppSettingsStore.swift`
- Modify: `SpotifyLyrics/Views/MainWindow/AppleMusicImmersiveV3WindowView.swift`
- Modify: `SpotifyLyrics/Views/Components/AppleMusicImmersiveV3BackdropView.swift`

**Interfaces:**
- Produces: `AppSettingsStore.v3AmbientBackdropEnabled: Bool`
- Produces: `ambientArtworkLayers(image:)` and retained `legacyArtworkLayers(image:)`

- [ ] **Step 1: Write the failing contract**

Assert the new key/property/default, popover toggle, explicit ambient/legacy branch, low-frequency artwork data, and absence of playback time in the request key.

- [ ] **Step 2: Run the contract and verify RED**

Run: `bash Tests/v3_ambient_backdrop_contract.sh`

Expected: FAIL because `v3AmbientBackdropEnabled` and the ambient renderer do not exist.

- [ ] **Step 3: Implement the persistent switch and ambient renderer**

Add the Boolean with a default of `true`, expose `Toggle("专辑环境光背景", ...)`, retain the existing artwork layers as `legacyArtworkLayers`, and route the enabled path through the new ambient renderer. Extend the existing immutable backdrop snapshot with a 48px low-frequency image generated in the same detached task.

- [ ] **Step 4: Verify GREEN and regressions**

Run:

```bash
bash Tests/v3_ambient_backdrop_contract.sh
bash Tests/v3_backdrop_contract.sh
bash Tests/v3_visual_tuning_reactivity_contract.sh
bash Tests/phase_2_3d_background_contract.sh
```

Expected: all four pass.

- [ ] **Step 5: Commit**

```bash
git add SpotifyLyrics/Settings/AppSettingsStore.swift SpotifyLyrics/Views/MainWindow/AppleMusicImmersiveV3WindowView.swift SpotifyLyrics/Views/Components/AppleMusicImmersiveV3BackdropView.swift Tests/v3_ambient_backdrop_contract.sh
git commit -m "feat(v3): add album ambient backdrop"
```


# V3 Track Metadata and Controls Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Improve V3's left-side metadata, progress, and transport hierarchy using native macOS interaction patterns without changing playback behavior.

**Architecture:** Keep existing `TrackMetadataView`, progress seeking, and playback actions. Adjust only their V3 presentation: white hierarchical metadata, thin filled progress with hover thumb, familiar SF Symbols, material primary action, subtle hover surfaces, and help labels.

**Tech Stack:** SwiftUI, SF Symbols, native materials, existing `PlaybackState` actions.

## Global Constraints

- Do not change playback semantics or Spotify commands.
- Do not add a permanent metadata card.
- Preserve left, center, right, medium, and small layouts.

---

### Task 1: Lock the visual/interaction contract

**Files:**
- Create: `Tests/v3_track_controls_visual_contract.sh`
- Modify: `SpotifyLyrics/Views/MainWindow/AppleMusicImmersiveV3WindowView.swift`

**Interfaces:**
- Consumes: existing previous/play-next/seek actions
- Produces: V3-only metadata and transport presentation

- [ ] **Step 1: Write the failing contract**

Require readable white artist/album hierarchy, familiar SF Symbols, material primary control, hover state, help labels, and a hover/drag progress thumb.

- [ ] **Step 2: Run and verify RED**

Run: `bash Tests/v3_track_controls_visual_contract.sh`

Expected: FAIL because the new V3 presentation markers do not exist.

- [ ] **Step 3: Implement the V3 presentation**

Update metadata color hierarchy and transport/progress visuals without changing action closures or layout breakpoints.

- [ ] **Step 4: Verify GREEN and V3 layout regressions**

Run:

```bash
bash Tests/v3_track_controls_visual_contract.sh
bash Tests/apple_music_immersive_v3_contract.sh
bash Tests/v3_visual_polish_contract.sh
```

Expected: the new contract passes; any pre-existing stale contract assertion is reported separately instead of being hidden.

- [ ] **Step 5: Commit**

```bash
git add SpotifyLyrics/Views/MainWindow/AppleMusicImmersiveV3WindowView.swift Tests/v3_track_controls_visual_contract.sh
git commit -m "refactor(v3): polish track controls"
```

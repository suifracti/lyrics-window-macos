# Phase 3.4 Findings

待 Stage 0 审计后记录事实；文件内容只作为工作记录，不替代源码和真实运行证据。

## 2026-08-05 baseline findings

- Actual branch: `antigravity/phase-3-4-direction-d-main-window`.
- Actual HEAD: `3bc484ed5452c987dca1e33c06a973bc5d64e510`, four commits after requested baseline `81f313a2c0e3b7783bf491fcbc0df3e306faf5f0`.
- Phase 3.4 added `DirectionDResponsiveLayout.swift`, `DirectionDMainWindowView.swift`, project references, a static contract script, a report, and 15 screenshot files.
- `DirectionDMainWindowView` currently has only value/default fixture inputs, uses a hard-coded sample lyric fallback, a constant Slider, no playback command closures, a gradient-only background, and no production/debug window entry. It is not yet a real live main-window surface.
- `DirectionDExperimentalProductHost` is the only Direction D debug window entry and its root is `DirectionDProductStateHostView`, not `DirectionDMainWindowView`.
- `PresentationCatalog` contains Direction D metadata only; no Direction D Main Window factory exists.
- Existing project file has one PBXFileReference and one PBXBuildFile for each Phase 3.4 Swift file, and both are in the application Sources phase.
- Existing 15 screenshots are invalid evidence: SHA-256 grouping is 5 copies of `1c10d0b3...` and 10 copies of `bab0c82a...`; they show the old `Direction D Experimental Host` waiting-state window. They were moved to `docs/phase-3/phase-3-4-main-window/invalid-captures/`.
- The working tree already contains unrelated modified and untracked artifacts. Do not reset, clean, or stage those files.

## 2026-08-06 sandbox merge findings

- `/Users/apple/backup/sptifylyrics-v4-ui-sandbox` is a filesystem snapshot, not a Git worktree; it has no `.git` directory.
- The snapshot is a later Direction D UI baseline: it adds the DirectionD design/component sources and the corresponding Xcode project references, plus follow-on changes in existing presentation, playback, settings, and V3 files.
- The snapshot's `AppleMusicImmersiveV3WindowView.swift` does not contain the current V3 automatic Japanese-reading/cache repair; that repair must be reapplied after importing the snapshot.
- The snapshot hides the V3 toolbar by default (`toolsVisible = false`), which conflicts with the user's current requirement that the right toolbar/settings be visible; preserve the formal repo's `toolsVisible = true` behavior.
- Do not import snapshot build products, DerivedData, screenshots, planning documents, or unrelated audit artifacts. Import source files, the Xcode project references, and only Direction D contract tests needed to validate the merged source.
- A safety branch `backup/pre-sandbox-merge-20260806` now points to the current formal HEAD before the merge.

## 2026-08-06 kana regression diagnosis

- The screenshot regression was reproducible in source: `shouldRenderInlineRuby` checked only for a line-level `kana` string and passed an optional token list to `RubyLineView`.
- `RubyLineView` intentionally falls back to one `LyricRubyToken(surface: originalText, ruby: kanaText)` when tokens are nil; this rendered the entire lyric line's kana as ruby and caused the visual symptom.
- The historical fix's missing guard was restored: inline ruby now requires `inlineRubyTokens` and a non-empty per-token mapping. Lines without safe token alignment do not enter the whole-line ruby fallback.
- A regression contract `Tests/v3_inline_ruby_gate_contract.sh` was written and observed failing before the production change, then passing after the change. The exact screenshot lines are also covered by `Tests/japanese_reading_contract.swift`.

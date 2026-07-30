# Lyrics Editing and Version Management V1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Provide an independent macOS lyric editor that derives, validates, saves, locks, imports, exports, and restores lyric/translation versions without overwriting Provider or AI originals.

**Architecture:** Extend SQLite schema v2 to v3 with parent-version relations and locked reading-layer records. Keep SQL behind `LyricsEditingRepository`; `LyricsEditorSessionController` owns an identity/version-bound draft, undo/redo, validation, and save orchestration. A separate SwiftUI `Window` renders the editor and uses `PlaybackState` only for explicit transport actions.

**Tech Stack:** Swift 5, SwiftUI/AppKit, SQLite3 actor repository, existing `LyricsSessionController` and `TranslationSessionController`, Foundation LRC parser/exporter.

## Global Constraints

- Provider and AI originals remain immutable; manual saves create new `manualEdit`/`manualImport` versions.
- Schema migration v3 is backed up, transactional, idempotent, and preserves all v1/v2 records.
- No AI HTTP, Provider, auto-alignment, TTML, or main-window visual changes.
- Timeline edits never average timestamps and only seek Spotify after an explicit user action.
- Every save rechecks TrackIdentity, source content hash, version ID, and editor revision.
- Locked manual lyrics/readings/translations cannot be automatically overwritten.

### Task 1: Contract tests and editor data model

**Files:** Create `Tests/lyrics_editor_contract.sh`, `Tests/lyrics_editor_contract.swift`, `Tests/lrc_roundtrip_contract.sh`, `Tests/lrc_roundtrip_contract.swift`, `Tests/sqlite_editing_contract.sh`, `Tests/sqlite_editing_contract.swift`; create `SpotifyLyrics/Editor/LyricsEditorModels.swift`, `SpotifyLyrics/Editor/LyricsTimelineValidator.swift`, `SpotifyLyrics/Editor/LRCImportExport.swift`.

- [x] Write contracts for line mutations, undo/redo, timeline rejection/warnings, LRC metadata/multiple timestamps/plain text, and export/reparse equality.
- [x] Implement the pure models, mutation history, validator, and LRC round-trip API.
- [x] Run the contracts green.

### Task 2: SQLite v3 and editing repository

**Files:** Modify `SpotifyLyrics/Persistence/DatabaseMigrator.swift`, `DatabaseModels.swift`, `LyricsPersistenceMapper.swift`, `LyricsRepository.swift`, `TranslationRepository.swift`, `SQLiteLyricsRepository.swift`; create `SpotifyLyrics/Persistence/LyricsEditingRepository.swift`; create `Tests/sqlite_editing_contract.sh`, `Tests/sqlite_editing_contract.swift`.

- [x] Add `parent_version_id` to lyric and translation versions plus a locked reading-layer table and normal indexes.
- [x] Add repository DTOs and one-transaction manual save for lyrics plus optional translation, with hash/identity/revision validation.
- [x] Add version listing, locked reading load/save, lock operations, and migration tests.
- [x] Verify Provider originals stay present, manual versions point to parents, locked versions survive reload, and failed saves leave no partial rows.

### Task 3: Shared editor session and transport boundary

**Files:** Create `SpotifyLyrics/Services/LyricsEditorSessionController.swift`; modify `LyricsSessionController.swift`, `TranslationSessionController.swift`, `PlaybackState.swift`.

- [x] Bind a session to TrackIdentity, lyrics version ID, source hash, translation version ID, and starting revision.
- [x] Add operations for split/merge/insert/delete/move, current-line regeneration, full regeneration, locked reading preservation, explicit save/lock, and stale-track rejection.
- [x] Project a confirmed manual document back into the shared lyric/translation sessions without changing playback position.
- [x] Add controller contracts for stale save rejection and lock-first restore.

### Task 4: Independent editor window and LRC actions

**Files:** Create `SpotifyLyrics/Views/Editor/LyricsEditorWindowView.swift`; modify `Main.swift`, `MainLyricsWindowView.swift`, `AppleMusicImmersiveV3WindowView.swift`, `SpotifyLyrics.xcodeproj/project.pbxproj`.

- [x] Add a separate `Window("歌词编辑", id: "lyrics-editor")` scene and a restrained menu entry.
- [x] Render version selectors, editable rows, timestamps, translation, validation, undo/redo, save/lock, import preview/confirm, and separate original/translation LRC exports.
- [x] Route seek/play/mark-current-time only through explicit editor buttons.
- [x] Verify the editor does not retarget when Spotify changes tracks and never writes to the new track.

### Task 5: Real acceptance, build, and commit

- [x] Run all existing contracts plus editing/LRC/migration contracts.
- [x] Use real `恋風 / Lilas` to create, edit, lock, restart, and verify the LRCLIB parent remains.
- [x] Use real `水曜日の約束 / Kawasaki.Rio` to edit and restore plain text without fabricating sync.
- [x] Import a matching LRC, export/reparse it, test invalid timelines and A→B stale-save protection.
- [x] Clean/build the exact Debug app, verify codesign/process origin, inspect diff, and commit one independent change.

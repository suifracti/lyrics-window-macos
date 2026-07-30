# Implementation Checkpoint — Real Audio Line Alignment V1

- Date: 2026-07-30
- Workspace: `/Users/apple/backup/sptifylyrics`
- Branch: `ui-redesign-phase-1`
- HEAD before implementation: `f5c0c9ba8ee26d1e5d9c6cc97aba711711652bd8`
- Implementation plan: `docs/superpowers/plans/2026-07-30-real-audio-line-alignment-v1.md`
- Plan SHA-256: `7f125244333828a4e28d08c4d96e2a2e4a5240b0e1b0993097b3eec093a42432`

## Pre-implementation repository status

The following changes/untracked paths predate this implementation and are intentionally not part of the alignment scope:

```text
 M findings.md
 M progress.md
?? DerivedData.bak.20260727220515/
?? LyricsX-master/
?? TaskbarLyrics-main/
?? docs/LYRICS_COVERAGE_AUDIT_2026-07-30.md
?? docs/PROJECT_STATUS_2026-07-28.md
?? docs/REFERENCE_PROJECTS_LYRICS_AUDIT.md
?? docs/superpowers/plans/2026-07-30-real-audio-line-alignment-v1.md
```

## Baseline data checks

- Production database: `~/Library/Application Support/SpotifyLyrics/SpotifyLyrics.sqlite3`
- `PRAGMA integrity_check`: `ok`
- `lyrics_versions`: `59`
- `lyric_lines`: `2903`
- Synthetic alignment data in the production database: not used for this implementation checkpoint.
- No production database migration is planned for this phase.
- SQLite schema v3 remains the source of LyricsVersion, `parent_version_id`, and line timing data.
- Alignment provenance will be stored only in sidecars under `~/Library/Application Support/SpotifyLyrics/AlignmentProvenance/`.

## Explicit scope gates

- No migration v4 or TrackIdentity merge is performed.
- No Spotify download, DRM extraction, or remote audio acquisition is performed.
- No TTS or synthetic audio is accepted as commercial-song evidence.
- No global, leading, trailing, or all-line average timing fallback is allowed.
- Real commercial-song acceptance remains **UNVERIFIED** until the user selects a matching complete local audio file in the App.

## Implementation checklist

1. Freeze/remove unsafe average timing and TTS-success paths.
2. Add injectable `TimedTranscriptProvider` and Speech adapter.
3. Implement deterministic DP line alignment with per-line evidence and safe unresolved boundaries.
4. Add audio preflight, metadata/hash validation, cancellation, and temporary PCM lifecycle.
5. Add revision/source/identity/track-switch guards and alignment preview flow.
6. Persist child alignment versions in existing SQLite v3 and write atomic provenance sidecars.
7. Reuse the editor for preview/manual correction and prevent low-confidence locking.
8. Run contract/regression tests, signed build, codesign verification, and exact-process verification.

This checkpoint is created before modifying SpotifyLyrics production source or alignment tests.

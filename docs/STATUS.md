# Project Status

Status snapshot: 2026-08-13.

This file describes what is present in the repository and how mature it is. It is not a release promise. Product direction and priority still come from the latest top-level Craft execution board; Git identifies the exact source.

## Source baseline

- `main` is the confirmed default baseline.
- The current V3, lyrics-source, reading, and responsive-layout work is included in the baseline after explicit build/test verification.
- Task branches may still contain newer or experimental work; they are not the source of truth unless explicitly selected for a task.
- Always verify the current branch, `HEAD`, upstream, and worktree status instead of treating this date or a document as the exact version.

## Implemented in the repository

- Spotify Desktop current-track observation and basic playback commands.
- Main, floating, fullscreen, and capsule lyrics presentations.
- Synchronized lyrics rendering, progress tracking, search/recovery states, and presentation settings.
- Local LRC/TXT import and paste, a lyrics editor, versioned SQLite persistence, and local-file lookup.
- LRCLIB lookup plus experimental NetEase and QQ provider implementations.
- Japanese reading/ruby generation, romanization and translation companion-layer infrastructure, including local correction data.
- Optional Spotify Web Catalog integration with credentials stored outside the repository.
- Focused shell/Swift contract tests for major UI, persistence, provider, reading, and alignment boundaries.

## Current implementation

- Distinct ambient, artwork-stage, and classic enlarged-artwork backdrop treatments, including honest zero-blur behavior.
- Consolidated user-facing main-window layout families: Classic Companion V1, Album Immersion V2, and Experimental Workbench V0.
- AMLL lookup and broader personal-source defaults.
- Concurrent network-provider execution with bounded timeouts and result deduplication.
- Improved translation/romanization preservation, long-line wrapping, lyric transitions, and scoped Japanese reading corrections.
- V3 lower-boundary resizing now keeps one bounded split composition when automatic Lyrics Focus is disabled; metadata, playback seeking, and the current-song operation surface also have adaptive UI fallbacks.

These items have code and contracts, but remain development work until accepted in real playback.

## Partial, experimental, or unreliable

- Online coverage varies by catalog, metadata quality, region, and provider availability. A provider existing in code does not mean a track will match.
- NetEase and QQ integrations use unofficial endpoints and may stop working; they are unsuitable as a release guarantee.
- Japanese readings use contextual rules and corrections but can still choose the wrong reading for names, rare words, or ambiguous phrases.
- Translation UI and persistence exist, but Apple/system and AI-backed translation paths still need broader real-machine acceptance.
- Automatic alignment has models, controls, experiments, and contracts, but is not a dependable zero-operation product feature.
- Direction D / Experimental Workbench is a development surface, not the recommended stable interface.
- UI polish, performance soak testing, and app-hang investigation remain ongoing; the latest responsive V3 checkpoint has passed a Debug build and a live resize smoke check but still needs longer real-playback soak testing.

## Planned or not implemented

- Reliable near-universal lyrics coverage.
- Production-quality automatic timing for unsynchronized text.
- Subject-aware artwork cropping and mature per-artwork background selection.
- MV or other dynamic-video backgrounds.
- Final packaging, signing, distribution, release notes, and a SemVer release.

## How to verify the current truth

```sh
git status
git branch --show-current
git rev-parse HEAD
git log -5 --oneline
git rev-parse '@{upstream}'
```

If the worktree is dirty, describe the version as `base HEAD + uncommitted changes`. Do not infer freshness from `.app` files, DerivedData, `.local/`, screenshots, backups, or modification times.

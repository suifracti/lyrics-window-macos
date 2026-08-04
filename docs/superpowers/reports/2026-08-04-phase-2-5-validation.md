# Phase 2.5 AI Translation System — Validation Report

Date: 2026-08-04
Repository: `/Users/apple/backup/sptifylyrics`
Branch: `codex/phase-2-5-ai-translation-system`
Phase 2.4 baseline: `625a8ad9093ed52302a3cd8e7eab8a97068e50c2`

## Scope

Phase 2.5 adds two translation engines, model-directory handling, prompt presets, personal style profiles, read-only prompt preview, candidate-first translation execution, strict response validation, translation provenance metadata, and explicit adopt/archive/lock/no-translation actions.

The implementation keeps one `PlaybackState`, one `LyricsSessionController`, one `TranslationSessionController`, one Keychain store, and the existing SQLite repository. AI output never changes original text, kana, romaji, or timing.

## Stable IDs

### Engines

- `translationEngine.openAICompatible.v1`
- `translationEngine.appleSystem.v1`

### Prompt presets

- `translationPrompt.naturalSong.v1` — default
- `translationPrompt.literalFaithful.v1`
- `translationPrompt.poeticFlow.v1`
- `translationPrompt.contextAware.v1`
- `translationPrompt.custom.v1`

### Workflows

- `translationWorkflow.classicV1`
- `translationWorkflow.contextualV2` — current configuration default

## Implementation commits

1. `8904cb6 feat(ai): add translation engines and model catalog`
   - Engine catalog and IDs, model status/cache, Base URL normalization, Chinese AI settings, explicit model refresh, and contracts.
2. `8bc2ac1 feat(ai): add prompt presets and style profiles`
   - Prompt preset catalog, personal profile store, immutable profile snapshots, prompt preview, and structured response validator.
3. This commit — `feat(ai): add translation execution and engine fallback`
   - Translation metadata v5, Apple System adapter, candidate-first execution, explicit adoption/archive/fallback, current-song operations, and settings/profile UI.

The third commit is created only after this report and the final repository checks are staged together.

## Execution and safety rules

- OpenAI-compatible requests use the normalized `/models` and `/v1/chat/completions` endpoints. Existing `/v1`, full `/v1/chat/completions`, trailing slashes, and custom reverse-proxy paths are covered by contracts.
- API Key is read only by an explicit model refresh, connection test, or translation request. It is never written to SQLite, logs, diagnostics, screenshots, or source control.
- Translation requests save a complete non-default draft only after strict JSON/index/line/content validation succeeds.
- A draft is not selected automatically. The user must preview and adopt it.
- Explicit retranslation always creates a new version. Locked and manually selected versions are not replaced.
- `no translation` clears only the current session selection; it does not delete a stored version.
- Apple System Translation is independently selectable and has an availability gate. Automatic fallback is opt-in; the default is no automatic switch.

## SQLite v5

The additive v5 fields are:

- `engine_id`
- `prompt_preset_id`
- `profile_id`
- `profile_snapshot`
- `temperature`
- `workflow_id`
- `fallback_strategy`
- `is_draft`
- `is_archived`

Existing translation versions receive neutral metadata; the migration does not guess an engine, model, prompt, or profile. Translation lines remain independently stored. The v5 migration is transactional and only the disposable validation database was used for the final controlled run.

## Contract results

Fresh runs passed:

- `Tests/phase_2_5a_contract.sh` — PASS
- `Tests/phase_2_5b_contract.sh` — PASS
- `Tests/phase_2_5c_contract.sh` — PASS
- `Tests/ai_translation_contract.sh` — PASS
- `Tests/translation_persistence_contract.sh` — PASS
- `Tests/translation_session_contract.sh` — PASS
- `Tests/translation_ui_contract.sh` — PASS
- `bash Tests/synthetic_text_lyrics_e2e_contract.sh` — PASS (synthetic TEST fixtures only; no real song lyrics asserted)

The contracts cover model-directory success/empty/401/429/unsupported/error paths, manual model fallback, prompt/profile behavior, strict line validation, cancellation and late-result protection, no-selection and lock protection, explicit fallback, Apple availability gating, adoption, metadata, and no extra session/timer/playback changes.

## Build results

- Debug: `BUILD SUCCEEDED`
  - App: `/tmp/SpotifyLyricsPhase25CDebugFinal/Build/Products/Debug/SpotifyLyrics.app`
- Release: `BUILD SUCCEEDED`
  - App: `/tmp/SpotifyLyricsPhase25CReleaseCheck2/Build/Products/Release/SpotifyLyrics.app`
- `git diff --check`: PASS
- codesign: not run, as requested for this phase.

## Controlled temporary-database run

Final controlled run:

- Database: `/tmp/SpotifyLyricsPhase25Runtime4.koXk1L/SpotifyLyrics.sqlite3`
- Runtime log: `/tmp/SpotifyLyricsPhase25Runtime4.koXk1L/runtime.log`
- App executable used: `/tmp/SpotifyLyricsPhase25CDebugFinal/Build/Products/Debug/SpotifyLyrics.app/Contents/MacOS/SpotifyLyrics`
- Log evidence: `temporary_copy=YES`, `formal_database_opened=NO`
- Temporary database `user_version`: `5`
- Temporary database `integrity_check`: `ok`
- Temporary database `foreign_key_check`: empty

The production database was restored to the exact pre-run SHA-256 after an initial UI harness mistake. See the note below; the final controlled run itself used the temporary database path and did not open the formal database.

## Screenshots

Captured or retained validation artifacts:

- `/Users/apple/backup/sptifylyrics/docs/superpowers/reports/2026-08-04-phase-2-5-validation/screenshots/01-ai-settings.png`
- `/Users/apple/backup/sptifylyrics/docs/superpowers/reports/2026-08-04-phase-2-5-validation/screenshots/02-prompt-preview.png`
- `/Users/apple/backup/sptifylyrics/docs/superpowers/reports/2026-08-04-phase-2-5-validation/screenshots/03-translation-profile.png`
- `/Users/apple/backup/sptifylyrics/docs/superpowers/reports/2026-08-04-phase-2-5-validation/screenshots/current-screen.png`
- Existing current-song UI reference: `/Users/apple/backup/sptifylyrics/docs/current-song-main.png`

The screenshots contain no API Key or token. The model-directory success screen and real translation candidate/adopt recording remain unverified because no user API Key was supplied; their behavior is covered by controlled contract fixtures instead. Apple System Translation is compiled against the public macOS Translation API and availability-gated, but a real translation request was not run against a loaded lyric document in this validation.

## Formal database incident and recovery

The exact pre-run formal-database copy used for recovery was:

`9eabebc5540302821e4e8f0a989df6cd99ef74c7`

An initial path-based Computer Use launch bypassed the temporary environment and briefly opened the formal database, advancing it to v5. It was stopped immediately. An exact pre-run copy made before that launch was available at:

`/tmp/SpotifyLyricsPhase25Runtime2.3CLYkC/SpotifyLyrics.pre-v4-20260804-105109.sqlite3`

That copy had the SHA-256 above and `user_version=4`. The formal database was restored from that exact copy. The post-restoration formal SHA-256 is again:

`9eabebc5540302821e4e8f0a989df6cd99ef74c7`

The accidentally generated v5 copy was retained separately at `/tmp/SpotifyLyricsPhase25Formal-post-accidental-open-20260804.sqlite3`; its current SHA-256 is `b7d7e18e1bbbe206130ac70cc6912c2f6e1cdfbb` and it was not used as the formal database. No lyric, translation, or UUID deletion was performed. This incident is why the final UI evidence is explicitly labeled controlled/temp only.

## Remaining verification

- A real OpenAI-compatible translation request requires the user to enter their API Key in the App settings. It was not supplied to this run.
- Model directory success, real candidate preview/adopt, restart restoration of a newly generated translation, and Apple System Translation on a loaded lyric document remain pending user-side verification.
- No Phase 2.6 work was started.

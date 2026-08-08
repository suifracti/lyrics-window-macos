# Reading and Provider Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make contextual Japanese reading the single user-facing Japanese engine and make multi-provider lyric retrieval bounded, concurrent, cancellable, and deterministic before adding another experimental source.

**Architecture:** Preserve all persisted stable IDs for migration, but normalize legacy Japanese-engine preferences to the contextual engine and route V3 fallback readings through the same user dictionary as `ReadingSessionController`. Add provider execution metadata to the existing `LyricsProvider` protocol, keep local providers in an exclusive first lane, then execute network providers concurrently per query variant with individual timeouts and deterministic provider-order reduction through the existing safe matcher.

**Tech Stack:** Swift 6, Swift Concurrency, SwiftUI, Foundation, existing shell/Swift contract tests, Xcode Debug build.

## Global Constraints

- Work only in `/Users/apple/backup/sptifylyrics` on `codex/v3-ambient-ui-ruby-polish`.
- Do not modify Direction D / V4 product code.
- Do not run `generate_xcodeproj.py`.
- Keep `readingEngine.japaneseDictionary.v1` decodable as a migration alias; do not expose it as a selectable current engine.
- User dictionary changes must affect generated ruby without mutating provider original text, lyric IDs, or timestamps.
- Local lyric providers run before network providers. Network completion order must not change configured source priority.
- Every network provider receives an individual timeout and cancellation; one failure must not cancel other providers.
- Do not add Kugou until real-song probes and license/API review show an independently maintainable implementation path.

---

### Task 1: Normalize the Japanese engine setting

**Files:**
- Modify: `SpotifyLyrics/Lyrics/ReadingSettings.swift`
- Modify: `SpotifyLyrics/Settings/AppSettingsStore.swift`
- Modify: `SpotifyLyrics/Views/Settings/ReadingSettingsView.swift`
- Modify: `SpotifyLyrics/Lyrics/ReadingEngineRegistry.swift`
- Test: `Tests/phase_2_6b_engines_contract.swift`
- Test: `Tests/settings_contract.sh`

**Interfaces:**
- Consumes: `ReadingEngineID.japaneseDictionary`, `ReadingEngineID.japaneseContextual`, persisted `ReadingPreferences` JSON.
- Produces: `ReadingPreferences.normalizedForCurrentEngines() -> ReadingPreferences` and a registry whose user-facing Japanese stable ID list contains only `.japaneseContextual`.

- [ ] **Step 1: Write failing migration and catalog assertions**

Add assertions that a decoded preference carrying `readingEngine.japaneseDictionary.v1` normalizes to `readingEngine.japaneseContextual.v2`, unknown IDs also normalize to contextual, and `ReadingEngineRegistry.userSelectableJapaneseIDs == [.japaneseContextual]`. Update the settings shell contract to reject a visible `词典读音 v1` picker option.

- [ ] **Step 2: Run tests and verify RED**

Run:

```bash
./Tests/settings_contract.sh
./Tests/phase_2_6b_engines_contract.sh
```

Expected: FAIL because normalization and the selectable-engine catalog do not exist and the legacy picker remains visible.

- [ ] **Step 3: Implement the migration boundary**

Add a pure normalization method to `ReadingPreferences`; call it from `AppSettingsStore.loadReadingPreferences(defaults:)` and persist the normalized value when it differs. Add `ReadingEngineRegistry.userSelectableJapaneseIDs`. Keep `make(.japaneseDictionary)` working only for old records/tests. Replace the Japanese engine picker with a noninteractive “上下文读音” row plus text explaining that user corrections are applied before local morphology.

- [ ] **Step 4: Run tests and verify GREEN**

Run the two commands from Step 2 and `./Tests/v3_japanese_engine_contract.sh`.

- [ ] **Step 5: Commit**

```bash
git add SpotifyLyrics/Lyrics/ReadingSettings.swift SpotifyLyrics/Settings/AppSettingsStore.swift SpotifyLyrics/Views/Settings/ReadingSettingsView.swift SpotifyLyrics/Lyrics/ReadingEngineRegistry.swift Tests/phase_2_6b_engines_contract.swift Tests/settings_contract.sh
git commit -m "refactor(reading): make contextual Japanese the default path"
```

### Task 2: Apply scoped user corrections in V3 fallback ruby

**Files:**
- Modify: `SpotifyLyrics/Views/MainWindow/AppleMusicImmersiveV3WindowView.swift`
- Modify: `SpotifyLyrics/Lyrics/JapaneseReadingEngines.swift`
- Test: `Tests/v3_japanese_engine_contract.sh`
- Test: `Tests/japanese_reading_contract.swift`

**Interfaces:**
- Consumes: `ReadingUserDictionaryStore.load()`, current `TrackIdentity.stableKey`, artist display, `JapaneseContextualReadingEngine`.
- Produces: a synchronous, cacheable contextual analysis helper that accepts scoped `[ReadingDictionaryEntry]` and returns token-aligned `JapaneseReadingResult` for V3.

- [ ] **Step 1: Write failing V3 user-correction assertions**

Add a test fixture for `満を持して 衝動に Feeling Feeling Yeah` plus a scoped correction and assert that only `満` receives `まん`, the original line remains unchanged, and the cache signature includes correction revision/scope.

- [ ] **Step 2: Run tests and verify RED**

Run:

```bash
./Tests/v3_japanese_engine_contract.sh
./Tests/japanese_reading_contract.sh
```

Expected: FAIL because V3 calls `JapaneseReadingPipeline` directly and ignores the user dictionary/scope.

- [ ] **Step 3: Implement one shared contextual analysis helper**

Expose a pure helper from `JapaneseContextualReadingEngine` that applies enabled scoped entries before morphology and returns token-aligned output. Change `V3JapaneseReadingCache` to include engine ID, original text, track stable key, artist, and a stable hash of active correction entries. Pass the current track scope and `settings.readingUserDictionary.load()` from the V3 row.

- [ ] **Step 4: Run tests and verify GREEN**

Run the commands from Step 2 plus `./Tests/ruby_layout_contract.sh` and `./Tests/real_track_lyrics_contract.sh`.

- [ ] **Step 5: Commit**

```bash
git add SpotifyLyrics/Views/MainWindow/AppleMusicImmersiveV3WindowView.swift SpotifyLyrics/Lyrics/JapaneseReadingEngines.swift Tests/v3_japanese_engine_contract.sh Tests/japanese_reading_contract.swift
git commit -m "fix(reading): apply scoped corrections to V3 ruby"
```

### Task 3: Define provider execution lanes and timeout policy

**Files:**
- Modify: `SpotifyLyrics/Lyrics/LyricsModels.swift`
- Modify: `SpotifyLyrics/Lyrics/LocalLyricsProvider.swift`
- Modify: `SpotifyLyrics/Lyrics/AMLLLyricsProvider.swift`
- Modify: `SpotifyLyrics/Lyrics/LRCLIBLyricsProvider.swift`
- Modify: `SpotifyLyrics/Providers/NetEaseExperimentalLyricsProvider.swift`
- Modify: `SpotifyLyrics/Providers/QQExperimentalLyricsProvider.swift`
- Test: `Tests/phase_2_11a_retrieval_contract.swift`

**Interfaces:**
- Produces: `LyricsProviderExecutionLane { case local, network }`, `LyricsProvider.executionLane`, and `LyricsProvider.timeoutInterval` with safe defaults.
- Consumes: existing provider implementations without changing lookup result semantics.

- [ ] **Step 1: Write failing provider metadata assertions**

Assert Local is `.local`; AMLL/LRCLIB/NetEase/QQ are `.network`; local timeout is 2 seconds, exact/open network sources 8 seconds, experimental sources 6 seconds.

- [ ] **Step 2: Run test and verify RED**

Run `./Tests/phase_2_11a_retrieval_contract.sh`.

Expected: FAIL because execution metadata does not exist.

- [ ] **Step 3: Add protocol defaults and explicit overrides**

Add protocol-extension defaults (`.network`, 8 seconds) and override Local/experimental values. Do not add a second provider registry.

- [ ] **Step 4: Run test and verify GREEN**

Run `./Tests/phase_2_11a_retrieval_contract.sh` and `./Tests/lyrics_source_mode_contract.sh`.

- [ ] **Step 5: Commit**

```bash
git add SpotifyLyrics/Lyrics/LyricsModels.swift SpotifyLyrics/Lyrics/LocalLyricsProvider.swift SpotifyLyrics/Lyrics/AMLLLyricsProvider.swift SpotifyLyrics/Lyrics/LRCLIBLyricsProvider.swift SpotifyLyrics/Providers/NetEaseExperimentalLyricsProvider.swift SpotifyLyrics/Providers/QQExperimentalLyricsProvider.swift Tests/phase_2_11a_retrieval_contract.swift
git commit -m "refactor(lyrics): define provider execution policy"
```

### Task 4: Run network providers concurrently and reduce deterministically

**Files:**
- Modify: `SpotifyLyrics/Lyrics/LyricsSearchManager.swift`
- Test: `Tests/phase_2_11a_retrieval_contract.swift`
- Test: `Tests/lyrics_correctness_test.swift`

**Interfaces:**
- Consumes: `LyricsProvider.executionLane`, `LyricsProvider.timeoutInterval`, provider array order, existing `LyricsSafeMatcher`.
- Produces: internal `ProviderProbeResult` and `probeNetworkProviders(track:identity:providers:) async -> [ProviderProbeResult]` sorted by configured provider index.

- [ ] **Step 1: Write failing concurrency, timeout, isolation, and priority tests**

Use deterministic delayed providers to prove: local match prevents any network probe; two network misses complete near the slower single delay rather than their sum; a timed-out provider does not suppress a later match; when two providers match, the lower configured index wins even if it completes later; cancellation returns `.cancelled`.

- [ ] **Step 2: Run tests and verify RED**

Run:

```bash
./Tests/phase_2_11a_retrieval_contract.sh
./Tests/real_track_lyrics_contract.sh
```

Expected: the elapsed-time and timeout assertions fail under the serial manager.

- [ ] **Step 3: Implement local-first and concurrent-network probing**

Keep query variants sequential to preserve alias strategy priority. For each variant, run local providers sequentially through the existing reducer. If unresolved, launch a throwing task-group child per network provider; race each lookup against its timeout, convert timeout into `.failed(.timedOut)`, gather all results, sort by provider index, then feed them through the existing identity/matcher/candidate reducer. Preserve negative-cache behavior and diagnostic durations.

- [ ] **Step 4: Run tests and verify GREEN**

Run the commands from Step 2, then `./Tests/assist_candidate_merge_contract.sh`.

- [ ] **Step 5: Commit**

```bash
git add SpotifyLyrics/Lyrics/LyricsSearchManager.swift Tests/phase_2_11a_retrieval_contract.swift Tests/lyrics_correctness_test.swift
git commit -m "perf(lyrics): query network providers concurrently"
```

### Task 5: Probe real unsynchronized coverage and decide the next provider

**Files:**
- Modify: `docs/research/SOURCE_PROVIDER_RESEARCH.md`

**Interfaces:**
- Consumes: read-only current SQLite track metadata, existing provider public lookup interfaces, no lyric persistence.
- Produces: aggregate hit/miss/timeout counts only; no private track list or lyric body is committed.

- [ ] **Step 1: Record the immutable AMLL baseline**

Document the already measured aggregate result: 169 tracks with Spotify IDs, 27 without a synchronized version, AMLL 0/27. Do not commit titles, IDs, lyric text, or local database paths.

- [ ] **Step 2: Probe existing NetEase and QQ implementations, then review Kugou independently**

Run against the 27 tracks that lack synchronized versions. Record aggregate exact/candidate/unsynced/timeout/error counts. Inspect the public request/response protocol and license boundary for a possible Kugou provider. Add Kugou only in a follow-up plan if it can be implemented independently and gated under `experimentalFree`.

- [ ] **Step 3: Update research decision and verify**

Run `./Tests/real_track_lyrics_contract.sh`. Confirm no titles, IDs, lyrics, cookies, or local database paths appear in tracked output.

- [ ] **Step 4: Commit**

```bash
git add docs/research/SOURCE_PROVIDER_RESEARCH.md
git commit -m "docs(lyrics): record real source coverage decision"
```

### Task 6: First-stage verification and push

**Files:**
- Verify only: all changed files in Tasks 1–5.

- [ ] **Step 1: Run focused contracts**

```bash
./Tests/settings_contract.sh
./Tests/v3_japanese_engine_contract.sh
./Tests/japanese_reading_contract.sh
./Tests/ruby_layout_contract.sh
./Tests/phase_2_11a_retrieval_contract.sh
./Tests/real_track_lyrics_contract.sh
```

- [ ] **Step 2: Run Debug build**

```bash
xcodebuild -project SpotifyLyrics.xcodeproj -scheme SpotifyLyrics -configuration Debug -derivedDataPath /tmp/sptifylyrics-derived build
```

- [ ] **Step 3: Inspect diff and status**

```bash
git diff main...HEAD --stat
git status --short
```

- [ ] **Step 4: Push the task branch**

```bash
git push origin codex/v3-ambient-ui-ruby-polish
```

- [ ] **Step 5: Update Craft**

Record exact commit SHAs, test/build evidence, real provider hit counts, remaining visual stage, and any blocked provider source.

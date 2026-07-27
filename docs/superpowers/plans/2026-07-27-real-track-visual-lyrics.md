# Real Track Visual and Lyrics Slice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep real Spotify track identity, lyrics, and generated artwork background synchronized while adding read-only Local/LRCLIB lyric lookup without changing the main-window layout.

**Architecture:** A pure Foundation identity/model/parser layer feeds a provider chain (`LocalLyricsProvider` then `LRCLIBLyricsProvider`). `PlaybackState` owns an identity-checked lyrics session and explicit Mock Preview mode. `TrackBackdropView` owns only the visual crossfade/palette pipeline and publishes no song data back to state.

**Tech Stack:** Swift 5, Foundation, AppKit, SwiftUI, URLSession, `NSImage`, `NSCache`, Xcode 26.6, macOS 14+.

## Global Constraints

- Do not change the existing main-window layout or window sizes.
- Prefer Spotify Track ID / Spotify URI, then ISRC, then normalized title/artist/album/duration identity.
- Every asynchronous lyrics/artwork result must re-check identity and request revision before publication.
- Local lyrics paths are read-only and ordered: `~/Music/SpotifyLyrics/Lyrics`, `~/Library/Application Support/SpotifyLyrics/Lyrics`, Debug-only repository `Lyrics/`.
- Release code must not depend on the source checkout.
- Mock lyrics require explicit Mock Preview mode.
- Do not add Spotify Web API, OAuth, SQLite, AI, automatic saving, or any other lyric source.

---

### Task 1: Approved design and red core contract

**Files:**
- Create: `docs/superpowers/specs/2026-07-27-real-track-visual-lyrics-design.md`
- Create: `docs/superpowers/plans/2026-07-27-real-track-visual-lyrics.md`
- Create: `Tests/real_track_lyrics_contract.sh`
- Create: `Tests/lyrics_core_test.swift`
- Test/compile inputs to be created in Task 2: `SpotifyLyrics/Lyrics/TrackIdentity.swift`, `SpotifyLyrics/Lyrics/LyricsModels.swift`, `SpotifyLyrics/Lyrics/LRCParser.swift`, `SpotifyLyrics/Lyrics/LyricsMatcher.swift`

**Interfaces:**
- The shell contract will compile the four pure Foundation files plus `Tests/lyrics_core_test.swift` and assert the expected identity/parser/matcher behaviors.

- [ ] Write the failing test harness with assertions for primary identity precedence, metadata fallback stability, LRC timestamps/language optionals, and confidence thresholds.
- [ ] Run `./Tests/real_track_lyrics_contract.sh` and confirm it fails because the production core files are missing.
- [ ] Commit only the approved design and plan documents before implementation.

### Task 2: Pure identity, lyric document, LRC parser, and matcher

**Files:**
- Create: `SpotifyLyrics/Lyrics/TrackIdentity.swift`
- Create: `SpotifyLyrics/Lyrics/LyricsModels.swift`
- Create: `SpotifyLyrics/Lyrics/LRCParser.swift`
- Create: `SpotifyLyrics/Lyrics/LyricsMatcher.swift`
- Modify: `SpotifyLyrics/Models/Models.swift` only if the shared Track initializer needs a stable identity helper.
- Test: `Tests/lyrics_core_test.swift`, `Tests/real_track_lyrics_contract.sh`

**Interfaces:**
- `TrackIdentity.init(track: Track)`, `stableKey`, `metadataFingerprint`, `lookupKeys`.
- `LyricsLoadState`: `idle`, `loading(TrackIdentity)`, `loaded(LyricsDocument)`, `noLyrics(TrackIdentity)`, `candidates(TrackIdentity, [LyricsCandidate])`, `failed(TrackIdentity, String)`, `mockPreview`.
- `LyricsDocument`, `LyricsCandidate`, `LyricsLookupResult`.
- `LRCParser.parse(_:, identity:, source:) -> LyricsDocument?`.
- `LyricsMatcher.score(track: Track, candidate: LyricsCandidate) -> Double` and `isHighConfidence(_:)`.

- [ ] Run the red contract and record its expected missing-symbol failure.
- [ ] Implement normalization that folds case/width, removes punctuation/spacing, and rounds duration to whole seconds for the fallback fingerprint.
- [ ] Implement identity lookup keys in priority order without making Track ID the only comparison value.
- [ ] Implement LRC `[mm:ss.xx]` parsing, metadata tags, sorted lines, and nil optional translation/romaji/kana.
- [ ] Implement weighted title/artist/album/duration matching with a high-confidence threshold of `0.84` and candidate threshold of `0.35`.
- [ ] Run the contract and verify all core assertions pass.

### Task 3: Read-only LocalLyricsProvider

**Files:**
- Create: `SpotifyLyrics/Lyrics/LocalLyricsProvider.swift`
- Modify: `SpotifyLyrics.xcodeproj/project.pbxproj`
- Test: `Tests/real_track_lyrics_contract.sh`

**Interfaces:**
- `LocalLyricsProvider(searchDirectories: [URL]? = nil)`.
- `lookup(track: Track, identity: TrackIdentity) async -> LyricsLookupResult`.

- [ ] Add a contract assertion for the three ordered search roots and the absence of write APIs.
- [ ] Implement search order: `~/Music/SpotifyLyrics/Lyrics`, `~/Library/Application Support/SpotifyLyrics/Lyrics`, and `#if DEBUG` current-working-directory `Lyrics/`.
- [ ] Match exact Track ID/Spotify URI/ISRC filenames first, then normalized metadata tags/filename and duration.
- [ ] Read and parse only existing `.lrc` files; return loaded, candidates, noLyrics, or failed without copying or modifying any file.
- [ ] Run the contract and a temporary-directory read-only probe; verify no file timestamp or content changes.

### Task 4: LRCLIBProvider and provider chain

**Files:**
- Create: `SpotifyLyrics/Lyrics/LRCLIBLyricsProvider.swift`
- Create: `SpotifyLyrics/Lyrics/CompositeLyricsProvider.swift`
- Modify: `SpotifyLyrics.xcodeproj/project.pbxproj`
- Test: `Tests/real_track_lyrics_contract.sh`

**Interfaces:**
- `LRCLIBLyricsProvider(session: URLSession = .shared, baseURL: URL = URL(string: "https://lrclib.net/api")!)`.
- `CompositeLyricsProvider(providers: [LyricsProvider])`.
- Both conform to `LyricsProvider` and return `LyricsLookupResult`.

- [ ] Add contract assertions for LRCLIB URL construction, JSON fields, and provider ordering.
- [ ] Validate the current LRCLIB endpoint response shape against a live metadata query before wiring it into the app.
- [ ] Implement metadata-specific lookup using title, artist, album, and duration; parse `syncedLyrics`/`plainLyrics` only.
- [ ] On a valid but low-confidence result, return candidates rather than auto-adopting; on empty lyric fields return noLyrics.
- [ ] Implement composite behavior: local loaded/candidates stop the chain; local no match proceeds to LRCLIB; failures preserve the most useful failure state.
- [ ] Run contract and a live provider probe with a real Spotify track, recording response classification without saving lyrics.

### Task 5: Identity-safe PlaybackState lyrics session

**Files:**
- Create: `SpotifyLyrics/Services/LyricsSessionController.swift`
- Modify: `SpotifyLyrics/Services/PlaybackState.swift`
- Modify: `SpotifyLyrics/Models/Models.swift` if `ProviderTrack` needs `isrc` propagation.
- Modify: `SpotifyLyrics.xcodeproj/project.pbxproj`
- Test: `Tests/real_track_lyrics_contract.sh`

**Interfaces:**
- `PlaybackState.lyricsState: LyricsLoadState`.
- `PlaybackState.currentTrackIdentity: TrackIdentity?`.
- `PlaybackState.lyricsSessionRevision: UInt64`.
- `PlaybackState.enterMockPreview()` and `exitMockPreview()`.
- `PlaybackState.retryLyrics()` and `adoptLyricsCandidate(_:)`.

- [ ] Add red assertions for immediate clearing on identity change and no Mock lyrics while `providerStatus == .ready`.
- [ ] Initialize real mode with an empty lyric array and no active background identity; do not use `MockData.sampleLyrics` as a default.
- [ ] On real-track identity change, cancel the previous lookup, clear all lyric layers and scroll revision, set loading, and start the composite provider.
- [ ] Check identity and revision before applying loaded/noLyrics/candidates/failed results.
- [ ] Keep MockData only behind explicit `enterMockPreview()`; exiting cancels Mock mode and reconnects Spotify.
- [ ] Preserve current playback interpolation and command semantics while removing automatic Mock lyric fallback.
- [ ] Run contract and an injected delayed-provider probe proving an old result cannot overwrite a new identity.

### Task 6: Identity-bound artwork palette and background crossfade

**Files:**
- Create: `SpotifyLyrics/Views/Components/TrackBackdropView.swift`
- Create: `SpotifyLyrics/Design/BackdropPalette.swift`
- Modify: `SpotifyLyrics/Providers/ArtworkImageLoader.swift` only for cancellation-safe image delivery if required.
- Modify: `SpotifyLyrics/Views/MainWindow/MainLyricsWindowView.swift` only to replace the current background composition, not layout structure.
- Modify: `SpotifyLyrics.xcodeproj/project.pbxproj`
- Test: `Tests/real_track_lyrics_contract.sh`

**Interfaces:**
- `BackdropPalette.from(image: NSImage) -> BackdropPalette`.
- `TrackBackdropView(track: Track, identity: TrackIdentity?, isLiveTrack: Bool)`.

- [ ] Add red assertions for Track ID/artwork request keys, palette extraction, cancellation checks, and absence of old-track binding.
- [ ] Implement downsampled bitmap sampling for dominant colors, luminance, saturation, and adaptive dark veil values.
- [ ] Render neutral gradient when no live identity/artwork exists; render scaled/cropped blurred artwork texture and layered gradients when it does.
- [ ] On request-key changes clear the current bound payload, preserve only an unbound outgoing snapshot, cancel prior work, and ignore late results.
- [ ] Crossfade the new payload into the existing background slot without changing the main-window layout.
- [ ] Run contract and build the app before UI integration.

### Task 7: Lyrics canvas states and language-layer correctness

**Files:**
- Modify: `SpotifyLyrics/Views/Components/LyricsCanvasView.swift`
- Modify: `SpotifyLyrics/Views/Components/LyricLineView.swift`
- Modify: `SpotifyLyrics/Views/LyricsViews.swift`
- Modify: `SpotifyLyrics/Views/MainWindow/MainLyricsWindowView.swift` only for loading/error/Mock actions in the existing status bar.
- Modify: `SpotifyLyrics.xcodeproj/project.pbxproj` only if new files were added.
- Test: `Tests/real_track_lyrics_contract.sh`

**Interfaces:**
- Canvas renders `LyricsLoadState` and uses `lyricsSessionRevision` as its scroll reset identity.
- Candidate selection calls `PlaybackState.adoptLyricsCandidate(_:)`.

- [ ] Add red assertions for loading, `暂未找到歌词`, failed, candidates, and explicit Mock Preview copy.
- [ ] Render no lyric rows while loading/noLyrics/failed/candidates; do not leave spacer rows for missing translation/romaji/kana.
- [ ] Keep current row timing/scroll behavior for loaded documents and reset the `ScrollView` identity on every track change.
- [ ] Replace auxiliary-view stale placeholders with the same state-derived message.
- [ ] Add explicit enter/exit Mock Preview action without changing the window layout.
- [ ] Run the contract and build after the main UI state wiring.

### Task 8: Runtime verification, screenshots, and handoff

**Files:**
- Create: `real-track-lyrics-assets/*.png`
- Modify: `progress.md`, `findings.md`, `task_plan.md`

- [ ] Run `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project SpotifyLyrics.xcodeproj -scheme SpotifyLyrics -configuration Debug -derivedDataPath ./DerivedData CODE_SIGNING_ALLOWED=NO build` and capture `** BUILD SUCCEEDED **`.
- [ ] Run the normal signed Debug build for Apple Events and launch `/Users/apple/backup/sptifylyrics/DerivedData/Build/Products/Debug/SpotifyLyrics.app`.
- [ ] Verify English, Japanese, Chinese, no-lyrics, loading during a cut, failed lookup, bright artwork, dark artwork, saturated artwork, and single-color artwork.
- [ ] For each screenshot confirm title, cover, generated background, and lyric text belong to one identity; do not use old provider screenshots as evidence.
- [ ] Verify LocalProvider did not modify any local file and Release does not reference the checkout `Lyrics/` path.
- [ ] Update planning findings with actual endpoint, song identities, states, errors, screenshot paths, and build logs.
- [ ] Run `git status --short`, `git diff --stat`, and the full contract one final time; do not claim completion if any required state lacks evidence.

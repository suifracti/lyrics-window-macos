# Real Track Visual and Lyrics Slice

## Goal

Make the visible song, lyrics session, and background represent the same real Spotify track at every state transition, while keeping the existing main-window layout unchanged.

## Scope and constraints

- Track identity must prefer Spotify Track ID / Spotify URI, then ISRC, then a normalized title/artist/album/duration fingerprint.
- A track change immediately invalidates old lyrics, language layers, scroll position, and background data state.
- Every asynchronous lyrics or artwork request carries the identity it started with and re-checks it before publishing.
- A previous background may remain only as an unbound visual snapshot during a short crossfade; it is never treated as the current track background.
- Local lyrics are read-only. Search locations, in priority order, are `~/Music/SpotifyLyrics/Lyrics`, `~/Library/Application Support/SpotifyLyrics/Lyrics`, and (Debug only) the repository `Lyrics/` directory. Release code must not depend on the source checkout.
- The only remote lyrics source is LRCLIB. No Spotify Web API, OAuth, SQLite, AI translation, automatic saving, or other lyric source is added.
- Mock lyrics are rendered only in an explicit Mock Preview mode. A connected Spotify track never falls back to Mock lyrics.
- Existing window layout, auxiliary-window scope, playback semantics, and Spotify Desktop provider dictionary remain unchanged.

## Architecture

### Track identity

`TrackIdentity` is a value type containing the normalized primary identifiers and a metadata fingerprint. Its stable key is constructed from the first available primary identifier (Spotify ID, Spotify URI, or ISRC) plus the normalized metadata fingerprint. If no primary identifier exists, the metadata fingerprint is the stable key. This prevents an ID-only comparison while preserving identity when one field is unavailable.

### Lyrics session

`LyricsLoadState` represents `idle`, `loading`, `loaded`, `noLyrics`, `candidates`, `failed`, and `mockPreview`. `PlaybackState` owns the active identity and a monotonically increasing session revision. On a real-track change it cancels the previous task, clears the lyric array and all derived language layers, resets the scroll revision, clears the bound background identity, then starts a new lookup. A returned result is accepted only if both identity and revision still match.

`LyricsProvider` returns either a high-confidence document, a candidate list, no result, or a failure. `LocalLyricsProvider` parses read-only LRC files and returns only exact/high-confidence matches. `LRCLIBLyricsProvider` first requests the metadata-specific LRCLIB endpoint and falls back to search results when necessary. Candidate scores combine normalized title, artist, album, and duration. Only a high-confidence result is adopted automatically; lower-confidence results are displayed for explicit selection and are never saved.

LRCLIB supplies synced/plain original lyrics only. Missing translation, romaji, or kana remain `nil`; view code conditionally omits those layers without spacer rows.

### Background

`TrackBackdropView` receives the current `Track`, `TrackIdentity?`, and a live-track flag. It loads artwork asynchronously, downsamples it for palette extraction, and creates a `BackdropPalette` with a primary gradient, secondary glow, enlarged/cropped blurred texture, and an adaptive dark readability veil. The request key includes identity and artwork URL. On a new key it clears the current bound payload immediately, keeps an optional unbound outgoing snapshot for a short fade, and publishes a new payload only after the identity check passes. Cancellation and late artwork/palette results are ignored.

### Mock Preview

`PlaybackState.enterMockPreview()` explicitly installs the sample track and sample lyrics. `exitMockPreview()` clears the session and reconnects to Spotify. Provider-unavailable states show an empty/no-track lyrics state and an explicit action to enter Mock Preview; they do not silently install Mock lyrics.

## UI behavior

- The existing window hierarchy and sizing remain unchanged.
- The lyrics canvas renders a centered status presentation for loading, no-lyrics, failed, and candidate states; loaded documents continue to use the current lyric rows.
- A candidate row shows title, artist, album, duration, source, and confidence with an explicit adopt button.
- The provider status bar gains only the necessary Mock Preview enter/exit action; no new permanent settings panel is introduced.
- Auxiliary lyric views consume the same `LyricsLoadState` and never show stale or Mock lines for a real Spotify identity.

## Error handling

- Missing Spotify or no current track: clear the real lyric session and show an explanatory empty state.
- LRCLIB network/HTTP/decoding failure: `failed` with a retry action; no stale lyrics are retained.
- Valid response without synced/plain lyrics: `noLyrics`.
- Low-confidence search response: `candidates`.
- Cancelled or out-of-date tasks: silently discard their result.
- Artwork failure: retain the neutral generated gradient, never an old track-bound payload.

## Verification design

1. Red contract compiles and runs pure Foundation identity, LRC parser, and confidence-matching tests before production implementations exist.
2. Xcode Debug builds run after provider/state work and after background/UI wiring.
3. Runtime verification uses real Spotify tracks and saves screenshots where song title, cover, generated background, and lyrics are visibly the same track.
4. Required runtime states: English, Japanese, Chinese, no lyrics, loading during a song change, failed lookup, bright artwork, dark artwork, highly saturated artwork, and single-color artwork.
5. No completion claim is made without a fresh build, test output, and screenshots.

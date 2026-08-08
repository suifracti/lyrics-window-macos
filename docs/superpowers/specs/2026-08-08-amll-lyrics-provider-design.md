# AMLL Lyrics Provider and Search Routing Design

## Status

Approved by the user on 2026-08-08.

## Goal

Increase synchronized lyric coverage immediately without copying AGPL reference code or embedding private cookies, tokens, signatures, or DRM bypasses.

## Source

AMLL TTML DB (`amll-dev/amll-ttml-db`) is a CC0 database that publishes generated lyric files keyed by platform IDs. Spotify-keyed line-synchronized LRC files are available at:

`https://raw.githubusercontent.com/amll-dev/amll-ttml-db/main/spotify-lyrics/<spotify-id>.lrc`

The first implementation consumes LRC only. TTML/word timing is a separate data-model project.

## Provider behavior

Add `AMLLLyricsProvider`:

- Requires a non-empty Spotify track ID.
- Percent-encodes and validates the ID before constructing the raw GitHub URL.
- Uses an ephemeral URL session and a five-second request/resource timeout.
- Treats HTTP 404 as `noMatch`, 2xx non-empty parseable LRC as a synchronized match, and other HTTP/network failures as typed failures.
- Returns source ID `amll:spotify:<spotify-id>`.
- Never sends a cookie, authorization token, or Referer.
- Uses only the caller's exact `TrackIdentity`; it does not invent identity aliases.

## Product policy

Add AMLL as an open/free source enabled in both source modes. Default order:

1. local files
2. SQLite adopted version
3. AMLL TTML DB
4. LRCLIB
5. NetEase experimental
6. QQ experimental

Existing user provider settings migrate additively so AMLL is inserted before LRCLIB without losing custom enable/order state.

## Routing performance

The provider must cache an in-flight/completed lookup by Spotify ID for the lifetime of the instance so query variants do not repeat the same network request. This bounded cache is cleared when providers are rebuilt. A larger parallel search refactor is deferred until the provider works end-to-end; it must not be mixed into the first source commit.

## Excluded sources

- Do not copy Folia provider/parser code (AGPL).
- Do not reverse engineer Dynamic Lyrics.
- Do not embed Musixmatch browser tokens.
- Do not add Kugou/QRC/KRC private-signature or decryption paths in this change.
- Existing NetEase and QQ experimental providers remain available and isolated.

## Acceptance

- A fixture Spotify ID returns parsed synchronized lyrics.
- 404 returns `noMatch`.
- Missing Spotify ID performs no request and returns `noMatch`.
- Repeated query variants for one ID perform at most one network request per provider instance.
- Settings expose AMLL and preserve existing provider configuration.
- Existing provider/session contracts and Debug build pass.

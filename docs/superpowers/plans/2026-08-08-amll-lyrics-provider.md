# AMLL Lyrics Provider Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use test-driven-development and executing-plans.

**Goal:** Retrieve AMLL community-timed LRC by exact Spotify track ID before title-based network fallbacks.

**Architecture:** Add a read-only `AMLLLyricsProvider` backed by the CC0 `amll-ttml-db/spotify-lyrics/<id>.lrc` path. It returns no match without a Spotify ID, parses with the existing LRC parser, caches per track ID, and participates in provider configuration and default routing.

**Tech Stack:** Swift concurrency, URLSession abstraction, existing lyrics models/parser, shell/Swift contract tests.

## Tasks

1. Add failing provider contracts for success, 404, missing Spotify ID, and request de-duplication.
2. Implement the provider and source label.
3. Add provider ID, display metadata, defaults/migration, and settings visibility.
4. Register AMLL ahead of LRCLIB in playback provider construction.
5. Add the Swift file to the Xcode project manually and run provider/configuration contracts.

## Acceptance

- A valid AMLL Spotify-ID LRC returns synced lyrics.
- 404 or missing ID cleanly returns no match.
- Repeated query variants do not re-download the same track.
- Existing local, LRCLIB, NetEase, and QQ providers remain available.

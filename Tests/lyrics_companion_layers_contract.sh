#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/spotifylyrics-companion-layers.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

swiftc -parse-as-library \
  "$ROOT_DIR/SpotifyLyrics/Models/Models.swift" \
  "$ROOT_DIR/SpotifyLyrics/Lyrics/TrackIdentity.swift" \
  "$ROOT_DIR/SpotifyLyrics/Lyrics/AlignmentModels.swift" \
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LyricsModels.swift" \
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LRCParser.swift" \
  "$ROOT_DIR/SpotifyLyrics/Lyrics/TrackAlias.swift" \
  "$ROOT_DIR/SpotifyLyrics/Lyrics/TrackMetadata.swift" \
  "$ROOT_DIR/SpotifyLyrics/Lyrics/TrackTextNormalizer.swift" \
  "$ROOT_DIR/SpotifyLyrics/Lyrics/JapaneseRomanizer.swift" \
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LyricsE2ELog.swift" \
  "$ROOT_DIR/SpotifyLyrics/Providers/QQExperimentalLyricsProvider.swift" \
  "$ROOT_DIR/Tests/lyrics_companion_layers_contract.swift" \
  -o "$TMP_DIR/lyrics-companion-layers-contract"

"$TMP_DIR/lyrics-companion-layers-contract"

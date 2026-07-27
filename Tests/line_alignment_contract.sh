#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
TMP="$(mktemp -d /tmp/align.XXXXXX)"
trap 'rm -rf "$TMP" 2>/dev/null || true' EXIT
cp Tests/line_alignment_contract.swift "$TMP/main.swift"
swiftc -parse-as-library \
  SpotifyLyrics/Models/Models.swift \
  SpotifyLyrics/Lyrics/TrackIdentity.swift \
  SpotifyLyrics/Lyrics/LyricsModels.swift \
  SpotifyLyrics/Lyrics/AlignmentModels.swift \
  SpotifyLyrics/Lyrics/JapaneseRomanizer.swift \
  SpotifyLyrics/Lyrics/JapaneseKanaGenerator.swift \
  SpotifyLyrics/Lyrics/LineForcedAligner.swift \
  "$TMP/main.swift" -o "$TMP/align"
export SPOTIFYLYRICS_KANA_DICT="$ROOT_DIR/SpotifyLyrics/Resources/japanese_kanji_readings.json"
"$TMP/align"
echo "line alignment contract OK"

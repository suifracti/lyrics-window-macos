#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d /tmp/real-align.XXXXXX)"
trap 'rmdir "$TMP" 2>/dev/null || true' EXIT
swiftc -parse-as-library \
  "$ROOT_DIR/SpotifyLyrics/Models/Models.swift" \
  "$ROOT_DIR/SpotifyLyrics/Lyrics/TrackIdentity.swift" \
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LyricsModels.swift" \
  "$ROOT_DIR/SpotifyLyrics/Lyrics/AlignmentModels.swift" \
  "$ROOT_DIR/SpotifyLyrics/Lyrics/JapaneseRomanizer.swift" \
  "$ROOT_DIR/SpotifyLyrics/Lyrics/JapaneseReadingPipeline.swift" \
  "$ROOT_DIR/SpotifyLyrics/Lyrics/JapaneseKanaGenerator.swift" \
  "$ROOT_DIR/SpotifyLyrics/Lyrics/TimedTranscript.swift" \
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LineForcedAligner.swift" \
  "$ROOT_DIR/Tests/real_audio_line_alignment_contract.swift" \
  -o "$TMP/real-align"
export SPOTIFYLYRICS_KANA_DICT="$ROOT_DIR/SpotifyLyrics/Resources/japanese_kanji_readings.json"
"$TMP/real-align"
echo "real audio line alignment contract OK"

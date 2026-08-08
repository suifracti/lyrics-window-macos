#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VIEW="$ROOT/SpotifyLyrics/Views/MainWindow/AppleMusicImmersiveV3WindowView.swift"
TOKENS="$ROOT/SpotifyLyrics/Design/LyricsDesignTokens.swift"

require_view() {
  local pattern="$1"
  local label="$2"
  if ! grep -Eq "$pattern" "$VIEW"; then
    echo "FAIL: $label (missing /$pattern/)" >&2
    exit 1
  fi
}

require_file() {
  local file="$1"
  local pattern="$2"
  local label="$3"
  if ! grep -Eq "$pattern" "$file"; then
    echo "FAIL: $label (missing /$pattern/)" >&2
    exit 1
  fi
}

require_file "$TOKENS" 'enum LyricsTransitionStyle' 'shared lyric transition policy'
require_view 'LyricsTransitionPolicy\.animation\(reduceMotion: reduceMotion\)' 'lyric animation source'
require_file "$TOKENS" 'smoothRelayoutV1' 'smooth lyric transition preset'
require_file "$TOKENS" 'lyricDuration' 'dedicated lyric transition duration'
require_view 'onChange\(of: currentIndex\)' 'current-line transition trigger'
require_view 'LyricsTransitionPolicy\.perform' 'scroll uses the shared lyric motion policy'

if grep -q 'value: state\.liveCurrentLineIndex' "$VIEW"; then
  echo 'FAIL: V3 lyric stack still animates the entire document on every current-line update' >&2
  exit 1
fi

if grep -Eq '\.animation\(transitionAnimation, value: isActive\)' "$VIEW"; then
  echo 'FAIL: V3 rows still own a second active-line animation' >&2
  exit 1
fi

echo 'V3 lyric transition contract: PASS'

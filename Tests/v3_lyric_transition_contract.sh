#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VIEW="$ROOT/SpotifyLyrics/Views/MainWindow/AppleMusicImmersiveV3WindowView.swift"

require() {
  local pattern="$1"
  local label="$2"
  if ! grep -Eq "$pattern" "$VIEW"; then
    echo "FAIL: $label (missing /$pattern/)" >&2
    exit 1
  fi
}

require 'private enum V3LyricsMotion' 'V3-only lyric motion coordinator'
require 'V3LyricsMotion\.animation\(reduceMotion: reduceMotion\)' 'V3 lyric animation source'
require 'interactiveSpring\(' 'interruptible V3 lyric spring'
require 'response: 0\.44' 'V3 lyric spring response'
require 'dampingFraction: 0\.93' 'V3 lyric spring damping'
require 'blendDuration: 0\.12' 'V3 lyric spring blending'
require 'onChange\(of: state\.liveCurrentLineIndex\)' 'current-line transition trigger'
require 'V3LyricsMotion\.perform' 'scroll uses V3 lyric motion'

if grep -q 'value: state\.liveCurrentLineIndex' "$VIEW"; then
  echo 'FAIL: V3 lyric stack still animates the entire document on every current-line update' >&2
  exit 1
fi

if grep -Eq '\.animation\(transitionAnimation, value: isActive\)' "$VIEW"; then
  echo 'FAIL: V3 rows still own a second active-line animation' >&2
  exit 1
fi

echo 'V3 lyric transition contract: PASS'

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

playback="SpotifyLyrics/Services/PlaybackState.swift"
canvas="SpotifyLyrics/Views/Components/LyricsCanvasView.swift"

grep -q 'private let alignmentService: any AlignmentService' "$playback"
grep -q 'sourceVersionID' "$playback"
grep -q 'sourceContentHash' "$playback"
grep -q 'AlignmentSessionGuard' "$playback"
grep -q 'inspectMetadata' "$playback"
if grep -q 'SPOTIFYLYRICS_AUTO_ALIGN' "$playback"; then
  echo "unsafe automatic alignment environment hook remains" >&2
  exit 1
fi
if grep -R -q 'spreadLowConfidence' SpotifyLyrics/Lyrics; then
  echo "unsafe confidence spreading remains" >&2
  exit 1
fi
if grep -R -q 'SPOTIFYLYRICS_AUTO_ALIGN' SpotifyLyrics; then
  echo "unsafe automatic alignment hook remains" >&2
  exit 1
fi
grep -q 'Button("自动排轴")' "$canvas"
grep -q 'state.alignCurrentLyricsWithLocalAudio()' "$canvas"
grep -q 'AlignmentPreviewView' "$canvas"

echo "alignment wiring contract passed"

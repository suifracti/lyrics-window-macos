#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

playback="SpotifyLyrics/Services/PlaybackState.swift"
canvas="SpotifyLyrics/Views/Components/LyricsCanvasView.swift"

grep -q 'private var didAutoAlignForIdentity: TrackIdentity?' "$playback"
grep -q 'private func tryAutoAlignIfRequested()' "$playback"
grep -q 'SPOTIFYLYRICS_AUTO_ALIGN' "$playback"
grep -q 'didAutoAlignForIdentity != identity' "$playback"
grep -q 'Button("自动排轴")' "$canvas"
grep -q 'state.alignCurrentLyricsWithLocalAudio()' "$canvas"

echo "alignment wiring contract passed"

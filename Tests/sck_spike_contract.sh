#!/usr/bin/env bash
# Contract: ScreenCaptureKit Spotify audio spike stays isolated from
# ASR/alignment/formal persistence and only targets Spotify.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SPIKE="$ROOT/SpotifyLyrics/Capture/SpotifyScreenCaptureAudioSpike.swift"
MAIN="$ROOT/SpotifyLyrics/Main.swift"

test -f "$SPIKE"
grep -Eq 'com\.spotify\.client' "$SPIKE"
grep -Eq 'SCStreamOutputType|\.audio' "$SPIKE"
grep -Eq 'capturesAudio' "$SPIKE"
grep -Eq 'excludesCurrentProcessAudio' "$SPIKE"
grep -Eq 'SpotifyLyricsCapture' "$SPIKE"
grep -Eq 'SCKSpikeLog|/tmp/spotifylyrics-sck-spike\.log' "$SPIKE"
grep -Eq 'SPOTIFYLYRICS_SCK_SPIKE' "$SPIKE"
grep -Eq 'spotifyNotFound|拒绝退化为全屏' "$SPIKE"

# No ASR / alignment wiring inside the spike.
if grep -Eq 'SpeechTimedTranscriptProvider|LineForcedAligner|saveAlignedVersion|SpeechForcedAlignmentService' "$SPIKE"; then
  echo "spike must not call ASR/alignment/persistence" >&2
  exit 1
fi

# Debug-only surface.
grep -Eq '#if DEBUG' "$SPIKE"
grep -Eq '排轴捕获 Spike' "$MAIN"

# Screen capture usage string present in project settings.
grep -Eq 'NSScreenCaptureUsageDescription' "$ROOT/SpotifyLyrics.xcodeproj/project.pbxproj"

echo "sck_spike_contract: PASS"

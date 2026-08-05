#!/usr/bin/env bash
# Phase 2.11C-S1: missing binary/model → unavailable, no crash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WHISPER="$ROOT/SpotifyLyrics/Capture/WhisperCLISpeechEngine.swift"
ENGINE="$ROOT/SpotifyLyrics/Capture/SpeechEngine.swift"
PIPE="$ROOT/SpotifyLyrics/Capture/SegmentPartialAlignmentPipeline.swift"
PB="$ROOT/SpotifyLyrics/Services/PlaybackState.swift"

grep -Eq 'case unavailable' "$ENGINE"
grep -Eq 'var isAvailable: Bool' "$WHISPER" "$ENGINE"
grep -Eq 'SpeechEngineError\.unavailable' "$WHISPER"
# Pipeline checks isAvailable / surfaces unavailable
grep -Eq 'isAvailable|recognizerUnavailable' "$PIPE"
# Product maps speech failures without claiming lifecycle nil-report only
grep -Eq 'speechFailed|识别失败或引擎不可用' "$PB"
# Must not force-unwrap binary/model paths
if grep -Eq 'binaryURL!|modelURL!|try!' "$WHISPER"; then
  echo "Whisper must not force-unwrap paths" >&2
  exit 1
fi

echo "engine_unavailable_contract: PASS"

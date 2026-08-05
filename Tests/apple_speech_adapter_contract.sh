#!/usr/bin/env bash
# Phase 2.11C-S1: AppleSpeechEngine wraps production Speech path
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APPLE="$ROOT/SpotifyLyrics/Capture/AppleSpeechEngine.swift"
ENGINE="$ROOT/SpotifyLyrics/Capture/SpeechEngine.swift"

test -f "$APPLE"
grep -Eq 'struct AppleSpeechEngine: LyricsSpeechEngine' "$APPLE"
grep -Eq 'SpeechTimedTranscriptProvider' "$APPLE"
grep -Eq 'engineID: SpeechEngineID = \.apple|speechEngine\.apple\.v1' "$APPLE" "$ENGINE"
grep -Eq 'SpeechEngineResult|SpeechEngineSegment' "$APPLE"
grep -Eq 'SpeechEngineError' "$APPLE"
# Adapter must not invent timestamps / write DB
if grep -Eq 'saveAlignedVersion|SQLiteLyricsRepository|AssistedCandidateMerger' "$APPLE"; then
  echo "Apple adapter must not write DB or merge candidates" >&2
  exit 1
fi
# Locale default remains Japanese product baseline
grep -Eq 'ja-JP' "$APPLE"

echo "apple_speech_adapter_contract: PASS"

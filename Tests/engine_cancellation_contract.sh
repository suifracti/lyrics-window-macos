#!/usr/bin/env bash
# Phase 2.11C-S1: speech engine + assist cancellation safety
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WHISPER="$ROOT/SpotifyLyrics/Capture/WhisperCLISpeechEngine.swift"
APPLE="$ROOT/SpotifyLyrics/Capture/AppleSpeechEngine.swift"
ENGINE="$ROOT/SpotifyLyrics/Capture/SpeechEngine.swift"
COORD="$ROOT/SpotifyLyrics/Capture/LiveCaptureCoordinator.swift"
PB="$ROOT/SpotifyLyrics/Services/PlaybackState.swift"

grep -Eq 'case cancelled' "$ENGINE"
grep -Eq 'SpeechEngineError\.cancelled|CancellationError' "$APPLE"
grep -Eq 'terminate|onCancel|SpeechEngineError\.timeout|Task\.checkCancellation' "$WHISPER"
# Capture stop publishes cancelled handoff for userStop/trackChanged when no report
grep -Eq 'failureKind: \.cancelled' "$COORD"
# User cancel path
grep -Eq 'cancelListeningAssist|userStop' "$PB"
# Alignment task cancelled on identity change
grep -Eq 'alignmentTask\?\.cancel' "$COORD"

echo "engine_cancellation_contract: PASS"

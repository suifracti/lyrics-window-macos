#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COORD="$ROOT/SpotifyLyrics/Capture/LiveCaptureCoordinator.swift"
MODELS="$ROOT/SpotifyLyrics/Capture/CapturedAudioModels.swift"
POLICY="$ROOT/SpotifyLyrics/Capture/CaptureContinuityPolicy.swift"
SPIKE="$ROOT/SpotifyLyrics/Capture/SpotifyScreenCaptureAudioSpike.swift"
MAIN="$ROOT/SpotifyLyrics/Main.swift"

test -f "$COORD" && test -f "$MODELS" && test -f "$POLICY"

grep -Eq 'struct CapturedAudioSession' "$MODELS"
grep -Eq 'struct CapturedAudioSegment' "$MODELS"
grep -Eq 'seekJumpThreshold|audioGapTimeout|anchorLogInterval' "$POLICY"
grep -Eq 'LiveCaptureCoordinator' "$COORD"
grep -Eq 'SEGMENT start|SESSION start|ANCHOR|SUMMARY_SEG' "$COORD"
grep -Eq 'audioSampleHandler' "$SPIKE"
grep -Eq 'Live Capture \(S2\)|LiveCaptureCoordinator' "$MAIN"
grep -Eq 'SPOTIFYLYRICS_SCK_S2' "$COORD"

# Must not wire ASR / alignment / SQLite lyrics.
for f in "$COORD" "$MODELS" "$POLICY"; do
  if grep -Eq 'SpeechTimedTranscriptProvider|LineForcedAligner|saveAlignedVersion|SpeechForcedAlignmentService' "$f"; then
    echo "S2 must not call ASR/alignment/persistence: $f" >&2
    exit 1
  fi
done

grep -Eq '#if DEBUG' "$COORD"

echo "s2_live_capture_contract: PASS"

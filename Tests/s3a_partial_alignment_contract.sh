#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PIPE="$ROOT/SpotifyLyrics/Capture/SegmentPartialAlignmentPipeline.swift"
MODELS="$ROOT/SpotifyLyrics/Capture/PartialAlignmentModels.swift"
LOCALE="$ROOT/SpotifyLyrics/Capture/AlignmentLocaleRecommender.swift"
WAV="$ROOT/SpotifyLyrics/Capture/SegmentWAVWriter.swift"
COORD="$ROOT/SpotifyLyrics/Capture/LiveCaptureCoordinator.swift"

test -f "$PIPE" && test -f "$MODELS" && test -f "$LOCALE" && test -f "$WAV"

grep -Eq 'PartialAlignmentCandidate|outsideCapturedRange' "$MODELS"
grep -Eq 'SpeechTimedTranscriptProvider|LineForcedAligner' "$PIPE"
grep -Eq 'spotifyPositionStart|speechRelative' "$PIPE"
grep -Eq 'held_out|HeldOutErrorStats|evaluateHeldOut' "$PIPE"
grep -Eq 'ja-JP|zh-CN|en-US' "$LOCALE"
grep -Eq '16_000|mono' "$WAV"
grep -Eq 'runPartialAlignment|S3A|SPOTIFYLYRICS_SCK_S3A' "$COORD"
grep -Eq 'wavWriter|SegmentWAVWriter' "$COORD"

# Must not write formal SQLite lyrics versions.
if grep -Eq 'saveAlignedVersion|SQLiteLyricsRepository' "$PIPE" "$COORD"; then
  echo "S3A must not write formal lyrics versions" >&2
  exit 1
fi
# No Whisper / paid
if grep -Eiq 'whisper|musixmatch|openai|付费' "$PIPE" "$MODELS" "$LOCALE"; then
  echo "S3A must not introduce paid/whisper engines" >&2
  exit 1
fi

echo "s3a_partial_alignment_contract: PASS"

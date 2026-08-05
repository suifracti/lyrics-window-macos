#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PIPE="$ROOT/SpotifyLyrics/Capture/SegmentPartialAlignmentPipeline.swift"
MODELS="$ROOT/SpotifyLyrics/Capture/PartialAlignmentModels.swift"
LOCALE="$ROOT/SpotifyLyrics/Capture/AlignmentLocaleRecommender.swift"
WAV="$ROOT/SpotifyLyrics/Capture/SegmentWAVWriter.swift"
COORD="$ROOT/SpotifyLyrics/Capture/LiveCaptureCoordinator.swift"

test -f "$PIPE" && test -f "$MODELS" && test -f "$LOCALE" && test -f "$WAV"

ENGINE="$ROOT/SpotifyLyrics/Capture/SpeechEngine.swift"

grep -Eq 'PartialAlignmentCandidate|outsideCapturedRange' "$MODELS"
# S1: speech is pluggable via LyricsSpeechEngine; S3A still uses LineForcedAligner only.
grep -Eq 'SpeechEngineRegistry|LyricsSpeechEngine|LineForcedAligner' "$PIPE"
grep -Eq 'spotifyPositionStart|speechRelative' "$PIPE"
grep -Eq 'held_out|HeldOutErrorStats|evaluateHeldOut' "$PIPE"
grep -Eq 'ja-JP|zh-CN|en-US' "$LOCALE"
grep -Eq '16_000|mono' "$WAV"
grep -Eq 'runPartialAlignment|S3A|SPOTIFYLYRICS_SCK_S3A' "$COORD"
grep -Eq 'wavWriter|SegmentWAVWriter' "$COORD"
test -f "$ENGINE"
grep -Eq 'asTimedTranscript|SpeechEngineResult' "$ENGINE"

# Must not write formal SQLite lyrics versions.
if grep -Eq 'saveAlignedVersion|SQLiteLyricsRepository' "$PIPE" "$COORD"; then
  echo "S3A must not write formal lyrics versions" >&2
  exit 1
fi
# S3A pipeline must stay engine-agnostic (no whisper-cli flags / SFSpeech in pipeline).
if grep -Eiq 'whisper-cli|SFSpeechRecognizer|musixmatch|openai|付费' "$PIPE" "$MODELS" "$LOCALE"; then
  echo "S3A must not hardcode engine subprocess or paid engines" >&2
  exit 1
fi
# No second aligner / merger / draft stack inside S3A.
if grep -Eq 'AssistedCandidateMerger|AssistedAlignmentDraft|LineForcedAligner\(' "$PIPE" | grep -vc 'LineForcedAligner.align' >/dev/null 2>&1; then
  :
fi
if grep -Eq 'struct LineForcedAligner|class AssistedCandidateMerger' "$PIPE"; then
  echo "S3A must not redefine aligner/merger" >&2
  exit 1
fi

echo "s3a_partial_alignment_contract: PASS"

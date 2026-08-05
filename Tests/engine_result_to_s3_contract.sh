#!/usr/bin/env bash
# Phase 2.11C-S2: engines only feed TimedTranscript into shared S3 path
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MAIN="$ROOT/Tools/s2_full_pipeline/main.swift"
PIPE="$ROOT/SpotifyLyrics/Capture/SegmentPartialAlignmentPipeline.swift"
ENGINE="$ROOT/SpotifyLyrics/Capture/SpeechEngine.swift"

grep -Eq 'asTimedTranscript|alignFromTimedTranscript' "$MAIN" "$ENGINE" "$PIPE"
# S3 path still uses LineForcedAligner + AnchorConstrainedAligner + no second stack
grep -Eq 'LineForcedAligner|AnchorConstrainedAligner' "$PIPE"
if grep -Eq 'struct LineForcedAligner|class AssistedCandidateMerger' "$MAIN"; then
  echo "Harness must not redefine aligner/merger" >&2
  exit 1
fi
# Whisper must not emit LRC / skip S3
if grep -Eiq 'writeLRC|\.lrc' "$MAIN"; then
  echo "Must not write LRC from engine" >&2
  exit 1
fi
echo "engine_result_to_s3_contract: PASS"

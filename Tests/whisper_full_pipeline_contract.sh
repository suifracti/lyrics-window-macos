#!/usr/bin/env bash
# Phase 2.11C-S2: offline full pipeline harness Speech→S3A→S3B→Merger
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MAIN="$ROOT/Tools/s2_full_pipeline/main.swift"
PIPE="$ROOT/SpotifyLyrics/Capture/SegmentPartialAlignmentPipeline.swift"
RUN="$ROOT/Tools/s2_full_pipeline/run_matrix.py"
DOC="$ROOT/docs/phase-2-11c-zero-operation-alignment/S2_WHISPER_FULL_PIPELINE.md"

test -f "$MAIN" && test -f "$RUN" && test -f "$DOC"
grep -Eq 'alignFromTimedTranscript|AssistedCandidateMerger\.merge' "$MAIN"
grep -Eq 'alignFromTimedTranscript|finalizeFromBundles' "$PIPE"
grep -Eq 'whisper_small|whisper_medium|apple' "$RUN"
# No formal DB open / auto adopt in harness
if grep -Eiq 'SQLiteLyricsRepository|saveAlignedVersion|formal.*open' "$MAIN" "$RUN"; then
  if grep -Eq 'formal_db_opened.: false|formal_db_opened = false|NEVER' "$MAIN" "$RUN"; then
    :
  else
    echo "S2 harness must not open formal DB" >&2
    exit 1
  fi
fi
if grep -Eq 'saveAlignedVersion|auto.?adopt' "$MAIN"; then
  echo "S2 harness must not save/adopt" >&2
  exit 1
fi
# Must not introduce Demucs this phase
if grep -Eiq 'demucs|spleeter' "$MAIN" "$RUN" "$PIPE"; then
  echo "S2 must not integrate Demucs" >&2
  exit 1
fi
echo "whisper_full_pipeline_contract: PASS"

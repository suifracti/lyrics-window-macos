#!/usr/bin/env bash
# Phase 2.11C-S2: same WAV/lyrics/params across engines
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUN="$ROOT/Tools/s2_full_pipeline/run_matrix.py"
MAIN="$ROOT/Tools/s2_full_pipeline/main.swift"
FIX="$ROOT/docs/phase-2-11c-zero-operation-alignment/s2-whisper-full-pipeline/fixtures/samples_manifest.json"

test -f "$FIX"
grep -Eq 'sampleA|sampleB|sampleC|sampleD' "$FIX"
grep -Eq 'whisper_small|whisper_medium|apple' "$RUN"
# Harness passes same wav/lyrics per sample for each engine
grep -Eq 'sample\["wav"\]|sample\["lyrics"\]' "$RUN"
# No engine-specific Merger thresholds
if grep -Eiq 's3bResolvedMinimumConfidence.*=|s3aResolvedMinimumConfidence.*=' "$MAIN"; then
  echo "Must not retune merger thresholds per engine" >&2
  exit 1
fi
grep -Eq 'AssistedCandidateMerger\.merge' "$MAIN"
echo "same_input_engine_comparison_contract: PASS"

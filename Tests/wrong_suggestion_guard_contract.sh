#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUN="$ROOT/Tools/s2_full_pipeline/run_matrix.py"
MG="$ROOT/SpotifyLyrics/Capture/AssistedCandidateMerger.swift"
grep -Eq 'wrong_suggestions|heuristic_wrong' "$RUN"
# Merger still rejects interpolation / non-monotonic
grep -Eq 'dropped_non_monotonic|boundedInterpolation|time_order_conflict' "$MG"
# Must not lower S3A/S3B product thresholds below historical floors
grep -Eq 's3bResolvedMinimumConfidence: Double = 0.72' "$ROOT/SpotifyLyrics/Capture/AssistedAlignmentDraft.swift"
grep -Eq 's3aResolvedMinimumConfidence: Double = 0.78' "$ROOT/SpotifyLyrics/Capture/AssistedAlignmentDraft.swift"
echo "wrong_suggestion_guard_contract: PASS"

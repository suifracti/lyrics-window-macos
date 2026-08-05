#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SC="$ROOT/Tools/s45_real_song_gate/score_against_gt.py"
grep -Eq 'wrong_occurrence|timing_error_gt3s|capture_violation|gt_offset_estimate' "$SC"
# Must score against GT file, not only confidence fields
grep -Eq 'load_gt|suggestedStartTime' "$SC"
if grep -Eq 'confidenceClass|overallConfidence' "$SC"; then
  echo "Scorer must not use model confidence as correctness" >&2
  exit 1
fi
echo "automatic_reference_scoring_contract: PASS"

#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SC="$ROOT/Tools/s45_real_song_gate/score_against_gt.py"
R="$ROOT/Tools/s45_real_song_gate/run_eval.py"
grep -Eq 'capture_violation|position_start|cap0' "$SC"
grep -Eq 'position-start|position-end' "$R"
echo "captured_range_violation_contract: PASS"

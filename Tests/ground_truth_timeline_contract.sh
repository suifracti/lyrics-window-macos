#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
S="$ROOT/Tools/s45_real_song_gate/select_candidates.py"
SC="$ROOT/Tools/s45_real_song_gate/score_against_gt.py"
grep -Eq 'gt.tsv|start_time|timed' "$S"
grep -Eq 'load_gt|median_abs_error|wrong_occurrence' "$SC"
echo "ground_truth_timeline_contract: PASS"

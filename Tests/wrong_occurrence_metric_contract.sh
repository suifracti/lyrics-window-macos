#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SC="$ROOT/Tools/s45_real_song_gate/score_against_gt.py"
grep -Eq 'wrong_occurrence|build_groups|closer_to_line' "$SC"
echo "wrong_occurrence_metric_contract: PASS"

#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GATE="$ROOT/SpotifyLyrics/Capture/AutomaticAlignmentQualityGate.swift"
for d in accumulate completeAndAdopt reject deferred; do
  grep -Eq "case $d" "$GATE"
done
grep -Eq 'weakinterpolated|weak_interpolation|coverage >= 0\.98|non_monotonic' "$GATE"
echo "automatic_alignment_quality_gate_contract: PASS"

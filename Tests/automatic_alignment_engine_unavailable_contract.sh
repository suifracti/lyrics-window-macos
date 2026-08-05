#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JOB="$ROOT/SpotifyLyrics/Capture/AutomaticAlignmentJobController.swift"
GATE="$ROOT/SpotifyLyrics/Capture/AutomaticAlignmentQualityGate.swift"
grep -Eq 'engine_unavailable|引擎尚未准备好' "$JOB" "$GATE"
grep -Eq 'isAvailable' "$JOB" "$GATE"
# Must not force unwrap crash paths for missing model
if grep -Eq 'try!|fatalError\(' "$JOB"; then
  echo "JobController must not fatalError/try!" >&2
  exit 1
fi
echo "automatic_alignment_engine_unavailable_contract: PASS"

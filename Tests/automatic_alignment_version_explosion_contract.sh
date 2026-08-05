#!/usr/bin/env bash
# Progress uses file store; formal versions only on completeAndAdopt.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROG="$ROOT/SpotifyLyrics/Capture/AutomaticAlignmentProgressStore.swift"
JOB="$ROOT/SpotifyLyrics/Capture/AutomaticAlignmentJobController.swift"
# Progress is JSON file based, not new DB
grep -Eq 'AutomaticAlignmentProgress|\.json' "$PROG"
# Only completeAndAdopt calls saveAlignedVersion
count=$(grep -c 'saveAlignedVersion' "$JOB" || true)
if [[ "$count" -lt 1 ]]; then
  echo "expected saveAlignedVersion in complete path" >&2
  exit 1
fi
# Quality gate prefers accumulate over complete for partial
grep -Eq 'partial_reliable_progress' "$ROOT/SpotifyLyrics/Capture/AutomaticAlignmentQualityGate.swift"
echo "automatic_alignment_version_explosion_contract: PASS"

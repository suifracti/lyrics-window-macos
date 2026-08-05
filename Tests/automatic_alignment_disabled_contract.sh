#!/usr/bin/env bash
# Switch off: no new auto jobs; cancel in-flight product jobs.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JOB="$ROOT/SpotifyLyrics/Capture/AutomaticAlignmentJobController.swift"
STORE="$ROOT/SpotifyLyrics/Settings/AppSettingsStore.swift"

grep -Eq 'guard settings\.automaticAlignmentEnabled else' "$JOB"
grep -Eq 'cancelCurrentJob' "$JOB"
# Default off
grep -Eq 'automaticAlignmentEnabled = defaults\.object\(forKey: Key\.automaticAlignmentEnabled\) as\? Bool \?\? false' "$STORE"
echo "automatic_alignment_disabled_contract: PASS"

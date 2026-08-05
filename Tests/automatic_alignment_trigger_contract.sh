#!/usr/bin/env bash
# Product auto-align starts only when switch on + playing + plain unsynced lyrics.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JOB="$ROOT/SpotifyLyrics/Capture/AutomaticAlignmentJobController.swift"
STORE="$ROOT/SpotifyLyrics/Settings/AppSettingsStore.swift"
PB="$ROOT/SpotifyLyrics/Services/PlaybackState.swift"

test -f "$JOB"
grep -Eq 'automaticAlignment\.enabled\.v1' "$STORE"
grep -Eq 'automaticAlignmentEnabled' "$STORE" "$JOB"
grep -Eq 'func evaluateTrigger|func startJob' "$JOB"
grep -Eq 'isPlaying' "$JOB"
grep -Eq 'plainDocument|!plain\.isSynchronized|isSynchronized' "$JOB"
# Must bind product path without assist_start
grep -Eq 'AutomaticAlignmentJobController\.shared\.bind' "$PB" "$ROOT/SpotifyLyrics/Main.swift"
if grep -Eq 'assist_start' "$JOB"; then
  echo "product job must not call assist_start" >&2
  exit 1
fi
echo "automatic_alignment_trigger_contract: PASS"

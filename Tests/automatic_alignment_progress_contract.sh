#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROG="$ROOT/SpotifyLyrics/Capture/AutomaticAlignmentProgressStore.swift"
JOB="$ROOT/SpotifyLyrics/Capture/AutomaticAlignmentJobController.swift"
GATE="$ROOT/SpotifyLyrics/Capture/AutomaticAlignmentQualityGate.swift"
grep -Eq 'TimedLineRecord|ProgressDocument|timedLines' "$PROG"
grep -Eq 'case \.accumulate' "$JOB"
grep -Eq 'isSynchronized: full' "$PROG"
# Partial must not claim full sync by default
grep -Eq 'case accumulate' "$GATE"
echo "automatic_alignment_progress_contract: PASS"

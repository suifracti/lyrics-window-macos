#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JOB="$ROOT/SpotifyLyrics/Capture/AutomaticAlignmentJobController.swift"
PROG="$ROOT/SpotifyLyrics/Capture/AutomaticAlignmentProgressStore.swift"
grep -Eq 'case paused|已暂停' "$JOB"
grep -Eq 'func load\(|func merge\(|func save\(' "$PROG"
grep -Eq 'old\.quality > quality' "$PROG"
echo "automatic_alignment_resume_contract: PASS"

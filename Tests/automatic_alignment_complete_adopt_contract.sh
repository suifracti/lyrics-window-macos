#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JOB="$ROOT/SpotifyLyrics/Capture/AutomaticAlignmentJobController.swift"
grep -Eq 'case \.completeAndAdopt' "$JOB"
grep -Eq 'saveAlignedVersion|AlignmentPersistenceRequest' "$JOB"
grep -Eq 'adoptPersisted' "$JOB"
grep -Eq 'source: \.automaticAlignment' "$JOB"
grep -Eq 'parentVersionID' "$JOB"
echo "automatic_alignment_complete_adopt_contract: PASS"

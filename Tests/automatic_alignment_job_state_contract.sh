#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JOB="$ROOT/SpotifyLyrics/Capture/AutomaticAlignmentJobController.swift"
for s in idle waitingForPlayback capturing paused aligning evaluating accumulating completed failed canceled deferred; do
  grep -Eq "case $s" "$JOB"
done
echo "automatic_alignment_job_state_contract: PASS"

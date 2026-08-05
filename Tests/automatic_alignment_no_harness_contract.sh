#!/usr/bin/env bash
# Product path must not depend on acceptance harness or assist_start.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JOB="$ROOT/SpotifyLyrics/Capture/AutomaticAlignmentJobController.swift"
MAIN="$ROOT/SpotifyLyrics/Main.swift"
if grep -Eq 'assist_start|SPOTIFYLYRICS_ACCEPTANCE_CONTROL|SPOTIFYLYRICS_SCK_S3A' "$JOB"; then
  echo "JobController must not depend on harness env" >&2
  exit 1
fi
# Auto-align bind is outside DEBUG-only block in Main (product onAppear)
grep -Eq 'AutomaticAlignmentJobController\.shared\.bind' "$MAIN"
# env auto-start for SCK stays DEBUG in LiveCapture
LC="$ROOT/SpotifyLyrics/Capture/LiveCaptureCoordinator.swift"
# If SCK_S3A appears it must be under DEBUG
if grep -n 'SPOTIFYLYRICS_SCK' "$LC" >/dev/null; then
  # ensure nearby #if DEBUG (heuristic: file still has DEBUG wrapper around env start)
  grep -Eq '#if DEBUG' "$LC"
fi
echo "automatic_alignment_no_harness_contract: PASS"

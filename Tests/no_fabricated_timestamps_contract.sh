#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
S="$ROOT/SpotifyLyrics/Capture/TranscriptSegmentSplitter.swift"
# Times must stay within parent start/end
grep -Eq 'start: seg\.startTime|end: seg\.endTime|interpolatedWithinObservedSegment' "$S"
# No song-duration average assignment
if grep -Eiq 'trackDuration\s*/\s*lineCount|evenly|uniform.*duration' "$S"; then
  echo "No uniform song-wide time assignment" >&2
  exit 1
fi
echo "no_fabricated_timestamps_contract: PASS"

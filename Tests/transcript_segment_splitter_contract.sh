#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
S="$ROOT/SpotifyLyrics/Capture/TranscriptSegmentSplitter.swift"
test -f "$S"
grep -Eq 'enum TranscriptSegmentSplitter|TimeProvenance|interpolatedWithinObservedSegment|lyric_token_alignment' "$S"
grep -Eq 'observed|allocateTimes' "$S"
# Must not invent content outside observed segment
if grep -Eiq 'randomTime|evenlyDistributeAcrossSong|uniformTrackDuration' "$S"; then
  echo "Splitter must not fabricate global timestamps" >&2
  exit 1
fi
grep -Eq 'without fabricating|observed parent' "$S"
echo "transcript_segment_splitter_contract: PASS"

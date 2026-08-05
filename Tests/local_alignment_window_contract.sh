#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
L="$ROOT/SpotifyLyrics/Capture/LocalAlignmentWindow.swift"
PIPE="$ROOT/SpotifyLyrics/Capture/SegmentPartialAlignmentPipeline.swift"
grep -Eq 'refineBetweenAnchors|LineForcedAligner.align' "$L"
grep -Eq 'LocalAlignmentWindow' "$PIPE"
# Must not define a second DP type
if grep -Eq 'struct LineForcedAligner|class LineForcedAligner' "$L"; then
  echo "Must reuse LineForcedAligner" >&2
  exit 1
fi
echo "local_alignment_window_contract: PASS"

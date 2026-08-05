#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
S="$ROOT/SpotifyLyrics/Capture/TranscriptSegmentSplitter.swift"
L="$ROOT/SpotifyLyrics/Capture/LocalAlignmentWindow.swift"
grep -Eq 'constrainedInterpolated|weakInterpolated|observed' "$S"
grep -Eq 'localWindow:constrainedInterpolated|refineBetweenAnchors' "$L"
echo "constrained_interpolation_contract: PASS"

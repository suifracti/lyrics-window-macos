#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
R="$ROOT/SpotifyLyrics/Capture/RepeatedLyricsSectionResolver.swift"
PIPE="$ROOT/SpotifyLyrics/Capture/SegmentPartialAlignmentPipeline.swift"
MAIN="$ROOT/Tools/s2_full_pipeline/main.swift"
grep -Eq 'CaptureWindow|outside_capture_window|contains\(' "$R"
grep -Eq 'CaptureWindow|positionStart|capStart|capEnd' "$PIPE"
grep -Eq 'position-start|position-end|track-duration' "$MAIN"
echo "captured_range_constraint_contract: PASS"

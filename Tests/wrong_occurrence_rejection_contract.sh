#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
R="$ROOT/SpotifyLyrics/Capture/RepeatedLyricsSectionResolver.swift"
PIPE="$ROOT/SpotifyLyrics/Capture/SegmentPartialAlignmentPipeline.swift"
grep -Eq 'wrong_occurrence_order_conflict|applyRejections' "$R"
grep -Eq 'applyRejections|s4:' "$PIPE"
echo "wrong_occurrence_rejection_contract: PASS"

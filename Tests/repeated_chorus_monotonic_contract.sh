#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
R="$ROOT/SpotifyLyrics/Capture/RepeatedLyricsSectionResolver.swift"
AN="$ROOT/SpotifyLyrics/Capture/AnchorConstrainedAligner.swift"
grep -Eq 'wrong_occurrence_order_conflict|occurrenceIndex' "$R"
grep -Eq 'failed_final_monotonic_filter|time_lyric_order_conflict' "$AN"
echo "repeated_chorus_monotonic_contract: PASS"

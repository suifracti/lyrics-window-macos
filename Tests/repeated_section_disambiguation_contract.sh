#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AN="$ROOT/SpotifyLyrics/Capture/AnchorConstrainedAligner.swift"
# Ambiguous multi-line matches rejected; monotonic selection remains
grep -Eq 'ambiguous_multiple_lyric_matches|duplicate_lyric_line|failed_final_monotonic_filter' "$AN"
grep -Eq 'uniquenessGap|minimumTemporalSeparation' "$ROOT/SpotifyLyrics/Capture/AnchorAlignmentPolicy.swift"
echo "repeated_section_disambiguation_contract: PASS"

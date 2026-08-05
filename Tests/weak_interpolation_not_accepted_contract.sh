#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
M="$ROOT/SpotifyLyrics/Capture/AssistedCandidateMerger.swift"
A="$ROOT/SpotifyLyrics/Capture/AssistedAlignmentDraft.swift"
grep -Eq 'weakInterpolated' "$A" "$M"
grep -Eq 'weakinterpolated' "$M"
echo "weak_interpolation_not_accepted_contract: PASS"

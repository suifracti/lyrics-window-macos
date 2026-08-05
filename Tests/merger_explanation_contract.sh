#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MG="$ROOT/SpotifyLyrics/Capture/AssistedCandidateMerger.swift"
AD="$ROOT/SpotifyLyrics/Capture/AssistedAlignmentDraft.swift"
MAIN="$ROOT/Tools/s2_full_pipeline/main.swift"
grep -Eq 'mergeWithExplanation|AssistedMergeDecision' "$MG" "$AD"
grep -Eq 'accepted|rejected|reason' "$MG"
grep -Eq 'merger_decisions' "$MAIN"
echo "merger_explanation_contract: PASS"

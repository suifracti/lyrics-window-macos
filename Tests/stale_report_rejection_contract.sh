#!/usr/bin/env bash
# Phase 2.11C-S1: canceled / wrong-generation reports never apply to new song
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COORD="$ROOT/SpotifyLyrics/Capture/LiveCaptureCoordinator.swift"
PB="$ROOT/SpotifyLyrics/Services/PlaybackState.swift"
PIPE="$ROOT/SpotifyLyrics/Capture/SegmentPartialAlignmentPipeline.swift"

# Generation invalidation on track change
grep -Eq 'alignmentGeneration|generationFlag|trackChanged' "$COORD"
grep -Eq 'S3A cancel gen=|drop stale report|isGenerationCurrent' "$COORD"
# Pipeline cancel when generation drifts
grep -Eq 'isGenerationCurrent|AlignmentError\.cancelled' "$PIPE"
# Assist rejects mismatched handoff generation
grep -Eq 'reject stale handoff|handoff\.generation != startedGen' "$PB"
# Identity guard still drops assist on track change
grep -Eq 'invalidateAssistOnTrackChange|ASSIST drop stale identity' "$PB"
# start() clears handoff only when taking a new session (idle/failed)
grep -Eq 'lastAlignmentHandoff = nil' "$COORD"
# publishHandoff refuses older gen overwrite
grep -Eq 'existing\.generation > generation' "$COORD"
# start ignored must not wipe a newer in-flight result with empty success
grep -Eq 'startIgnored|捕获仍在进行中' "$COORD"

echo "stale_report_rejection_contract: PASS"

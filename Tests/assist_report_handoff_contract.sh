#!/usr/bin/env bash
# Phase 2.11C-S1: lastPartialReport / PartialAlignmentHandoff lifecycle
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COORD="$ROOT/SpotifyLyrics/Capture/LiveCaptureCoordinator.swift"
PB="$ROOT/SpotifyLyrics/Services/PlaybackState.swift"

grep -Eq 'struct PartialAlignmentHandoff' "$COORD"
grep -Eq 'lastAlignmentHandoff|publishHandoff|waitUntilIdle' "$COORD"
grep -Eq 'PartialAlignmentFailureKind' "$COORD"
# Handoff published on success and on stratified failures
grep -Eq 'publishHandoff\(' "$COORD"
grep -Eq 'failureKind: \.noCompletedSession|failureKind: \.noWavSegments|failureKind: \.speechFailed|failureKind: \.cancelled' "$COORD"
# Must not overwrite newer generation
grep -Eq 'drop stale handoff|existing\.generation > generation' "$COORD"
# Assist consumes handoff by generation (not raw lastPartialReport alone)
grep -Eq 'lastAlignmentHandoff|startedGen|handoff\?\.report' "$PB"
grep -Eq 'handoff\.generation != startedGen|reject stale handoff' "$PB"
# Zero suggestions is ready, not lifecycle failed
grep -Eq 'suggestedCount == 0|识别完成，但可靠建议不足' "$PB"
# PCM append must not schedule async MainActor work (race root cause)
if awk '/func appendPCM/,/^    (private |public |func |@)/' "$COORD" | grep -Eq 'Task \{'; then
  echo "appendPCM must not hop via Task (WAV race)" >&2
  exit 1
fi
grep -A5 'func appendPCM' "$COORD" | grep -Eq 'wavWriter\?\.append'
# Assist must not treat idle+nil as success path into merger without report
grep -Eq 'AssistedCandidateMerger\.merge' "$PB"
# report-ready path always merges when report exists
awk '/confirmListeningAssistAndCapture/,/^    public func openListeningAssist/' "$PB" | grep -Eq 'AssistedCandidateMerger\.merge'

echo "assist_report_handoff_contract: PASS"

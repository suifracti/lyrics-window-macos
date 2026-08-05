#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AN="$ROOT/SpotifyLyrics/Capture/AnchorConstrainedAligner.swift"
PIPE="$ROOT/SpotifyLyrics/Capture/SegmentPartialAlignmentPipeline.swift"
grep -Eq 'missing_asr|neutralPrior|textConfidence' "$AN"
# Pipeline prepares transcript before anchors
grep -Eq 'prepareTranscript|TranscriptSegmentSplitter' "$PIPE"
# No whisper-only hardcode
if grep -Eiq 'whisper|ggml' "$AN"; then
  echo "Anchors must stay engine-agnostic" >&2
  exit 1
fi
echo "anchor_recovery_contract: PASS"

#!/usr/bin/env bash
# S3B: conservative anchors + constrained region DP (Debug-only).
# Does not replace S3A; must reuse Speech + LineForcedAligner.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PIPE="$ROOT/SpotifyLyrics/Capture/SegmentPartialAlignmentPipeline.swift"
MODELS="$ROOT/SpotifyLyrics/Capture/PartialAlignmentModels.swift"
ANCHOR="$ROOT/SpotifyLyrics/Capture/AlignmentAnchor.swift"
POLICY="$ROOT/SpotifyLyrics/Capture/AnchorAlignmentPolicy.swift"
ALIGNER="$ROOT/SpotifyLyrics/Capture/AnchorConstrainedAligner.swift"
COORD="$ROOT/SpotifyLyrics/Capture/LiveCaptureCoordinator.swift"
PBX="$ROOT/SpotifyLyrics.xcodeproj/project.pbxproj"

for f in "$PIPE" "$MODELS" "$ANCHOR" "$POLICY" "$ALIGNER" "$COORD"; do
  test -f "$f" || { echo "missing $f" >&2; exit 1; }
done

# Core types & policy thresholds centralized
grep -Eq 'struct AlignmentAnchor' "$ANCHOR"
grep -Eq 'minimumTextSimilarity|minimumOverallConfidence|minimumNormalizedLength|uniquenessGap|minimumAnchorsForConstrained' "$POLICY"
grep -Eq 'selectAnchors|alignConstrained' "$ALIGNER"
grep -Eq 'AnchorConstrainedAligner|acceptedAnchors|s3aCandidate|usedConstrainedAlignment|insufficientAnchors' "$PIPE"
grep -Eq 's3aCandidate|acceptedAnchors|rejectedAnchors|usedConstrainedAlignment' "$MODELS"
grep -Eq 'withinHalfSecondCount|withinOneSecondCount|withinTwoSecondCount' "$MODELS"

# Reuse existing Speech + LineForcedAligner; no second ASR
grep -Eq 'SpeechTimedTranscriptProvider|LineForcedAligner' "$PIPE"
if grep -Eiq 'whisper|WhisperKit|openai|musixmatch' "$PIPE" "$ALIGNER" "$ANCHOR" "$POLICY"; then
  echo "S3B must not introduce Whisper/paid engines" >&2
  exit 1
fi

# No formal DB / product adopt
if grep -Eq 'saveAlignedVersion|SQLiteLyricsRepository' "$PIPE" "$ALIGNER"; then
  echo "S3B must not write formal lyrics versions" >&2
  exit 1
fi

# Anchors must not use held-out timestamps for selection
if grep -Eq 'groundTruth|heldOut|syncedLines' "$ALIGNER"; then
  echo "AnchorConstrainedAligner must not take/use held-out GT" >&2
  exit 1
fi

# pbxproj includes new sources
grep -Eq 'AlignmentAnchor.swift in Sources' "$PBX"
grep -Eq 'AnchorAlignmentPolicy.swift in Sources' "$PBX"
grep -Eq 'AnchorConstrainedAligner.swift in Sources' "$PBX"

# Monotonic / uniqueness rejection reasons exist
grep -Eq 'ambiguous_multiple_lyric_matches|duplicate_lyric_line|time_lyric_order_conflict|failed_final_monotonic_filter' "$ALIGNER"

# Fallback when <2 anchors
grep -Eq 'insufficientAnchors' "$PIPE"

echo "s3b_anchor_alignment_contract: PASS"

#!/usr/bin/env bash
# Assist MVP Commit 1: merge S3A/S3B into draft without lowering thresholds.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DRAFT="$ROOT/SpotifyLyrics/Capture/AssistedAlignmentDraft.swift"
MERGE="$ROOT/SpotifyLyrics/Capture/AssistedCandidateMerger.swift"
MODELS="$ROOT/SpotifyLyrics/Lyrics/LyricsModels.swift"
MAPPER="$ROOT/SpotifyLyrics/Persistence/LyricsPersistenceMapper.swift"
PBX="$ROOT/SpotifyLyrics.xcodeproj/project.pbxproj"

test -f "$DRAFT" && test -f "$MERGE"
grep -Eq 'AssistedAlignmentDraft|AssistedLineSuggestion|AssistedCandidateMergePolicy' "$DRAFT"
grep -Eq 'AssistedCandidateMerger|merge\(|s3bResolvedMinimumConfidence|s3aResolvedMinimumConfidence' "$MERGE"
grep -Eq 'acceptedAnchors|boundedInterpolation|lowConfidence' "$MERGE"
# Must not lower S3B policy thresholds in merge file
if grep -Eq 'minimumTextSimilarity.*=.*0\.[0-5]' "$MERGE"; then
  echo "must not lower anchor text thresholds in merger" >&2
  exit 1
fi
# Partial timeline support without schema migration
grep -Eq 'explicitlyTimedLineIndices|lineHasExplicitTiming' "$MODELS"
grep -Eq 'lineHasExplicitTiming|explicitlyTimedLineIndices' "$MAPPER"
grep -Eq 'AssistedAlignmentDraft.swift in Sources|AssistedCandidateMerger.swift in Sources' "$PBX"
# No Whisper / vocal sep
if grep -Eiq 'whisper|demucs|spleeter|vocal.?separat' "$DRAFT" "$MERGE"; then
  echo "Assist merge must not add separation/whisper" >&2
  exit 1
fi
echo "assist_candidate_merge_contract: PASS"

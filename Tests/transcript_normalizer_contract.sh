#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
N="$ROOT/SpotifyLyrics/Capture/TranscriptNormalizer.swift"
test -f "$N"
grep -Eq 'enum TranscriptNormalizer|matchView|fullwidth|kana_match_view|en_contraction' "$N"
# Must not overwrite display lyrics / write DB
if grep -Eq 'saveAlignedVersion|SQLiteLyricsRepository|originalText\s*=' "$N"; then
  echo "Normalizer must not mutate lyrics storage" >&2
  exit 1
fi
echo "transcript_normalizer_contract: PASS"

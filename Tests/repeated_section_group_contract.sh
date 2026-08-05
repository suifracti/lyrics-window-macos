#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
R="$ROOT/SpotifyLyrics/Capture/RepeatedLyricsSectionResolver.swift"
test -f "$R"
grep -Eq 'buildGroups|RepeatedGroup|occurrenceIndex|ambiguous_repeated_section' "$R"
grep -Eq 'outside_capture_window|wrong_occurrence_order_conflict' "$R"
# Engine-agnostic
if grep -Eiq 'whisper|SFSpeech|apple speech' "$R"; then
  echo "Repeated resolver must be engine-agnostic" >&2
  exit 1
fi
echo "repeated_section_group_contract: PASS"

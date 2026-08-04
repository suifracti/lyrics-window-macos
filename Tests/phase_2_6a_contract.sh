#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${TMPDIR:-/tmp}/spotifylyrics-phase-2-6a-contract"
rm -rf "$BUILD"
mkdir -p "$BUILD"

[[ -x "$ROOT/Scripts/run-controlled-validation.sh" ]]
! grep -Eq '(^|[[:space:]])open([[:space:]]|$)' "$ROOT/Scripts/run-controlled-validation.sh"

swiftc -parse-as-library \
  "$ROOT/SpotifyLyrics/Lyrics/ReadingModels.swift" \
  "$ROOT/SpotifyLyrics/Lyrics/ReadingLanguageGate.swift" \
  "$ROOT/Tests/phase_2_6a_contract.swift" \
  -o "$BUILD/phase_2_6a_contract"

"$BUILD/phase_2_6a_contract"

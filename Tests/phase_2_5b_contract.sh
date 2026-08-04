#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h}/.."
BUILD="${TMPDIR:-/tmp}/spotifylyrics-phase-2-5b-contract"
rm -rf "$BUILD"
mkdir -p "$BUILD"

swiftc -parse-as-library \
  "$ROOT/SpotifyLyrics/AI/AITranslationModels.swift" \
  "$ROOT/SpotifyLyrics/AI/AITranslationConfiguration.swift" \
  "$ROOT/SpotifyLyrics/AI/AITranslationPromptBuilder.swift" \
  "$ROOT/SpotifyLyrics/AI/AITranslationResponseParser.swift" \
  "$ROOT/Tests/phase_2_5b_contract.swift" \
  -o "$BUILD/phase_2_5b_contract"

"$BUILD/phase_2_5b_contract"

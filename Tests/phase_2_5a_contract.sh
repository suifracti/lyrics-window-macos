#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h}/.."
BUILD="${TMPDIR:-/tmp}/spotifylyrics-phase-2-5a-contract"
rm -rf "$BUILD"
mkdir -p "$BUILD"

swiftc -parse-as-library \
  "$ROOT/SpotifyLyrics/AI/AITranslationModels.swift" \
  "$ROOT/SpotifyLyrics/AI/AITranslationConfiguration.swift" \
  "$ROOT/SpotifyLyrics/AI/AITranslationKeychain.swift" \
  "$ROOT/SpotifyLyrics/AI/AITranslationPromptBuilder.swift" \
  "$ROOT/SpotifyLyrics/AI/OpenAICompatibleClient.swift" \
  "$ROOT/Tests/phase_2_5a_contract.swift" \
  -o "$BUILD/phase_2_5a_contract"

"$BUILD/phase_2_5a_contract"

#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h}/.."
BUILD="${TMPDIR:-/tmp}/spotifylyrics-ai-translation-contract"
rm -rf "$BUILD"
mkdir -p "$BUILD"

swiftc -parse-as-library \
  "$ROOT/SpotifyLyrics/AI/AITranslationModels.swift" \
  "$ROOT/SpotifyLyrics/AI/AITranslationConfiguration.swift" \
  "$ROOT/SpotifyLyrics/AI/AITranslationKeychain.swift" \
  "$ROOT/SpotifyLyrics/AI/AITranslationPromptBuilder.swift" \
  "$ROOT/SpotifyLyrics/AI/AITranslationResponseParser.swift" \
  "$ROOT/SpotifyLyrics/AI/OpenAICompatibleClient.swift" \
  "$ROOT/SpotifyLyrics/AI/AITranslationService.swift" \
  "$ROOT/Tests/ai_translation_contract.swift" \
  -o "$BUILD/ai_translation_contract"

"$BUILD/ai_translation_contract"

SERVICE="$ROOT/SpotifyLyrics/AI/AITranslationService.swift"
grep -q 'session.prepareTranslation()' "$SERVICE" || {
  echo 'FAIL: Apple system translation does not prepare or download its language session' >&2
  exit 1
}

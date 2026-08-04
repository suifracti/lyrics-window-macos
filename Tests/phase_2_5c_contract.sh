#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

swiftc -parse-as-library \
  "$ROOT_DIR/SpotifyLyrics/Models/Models.swift" \
  "$ROOT_DIR/SpotifyLyrics/Lyrics/TrackIdentity.swift" \
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LyricsModels.swift" \
  "$ROOT_DIR/SpotifyLyrics/Lyrics/AlignmentModels.swift" \
  "$ROOT_DIR/SpotifyLyrics/Lyrics/TrackAlias.swift" \
  "$ROOT_DIR/SpotifyLyrics/Lyrics/TrackMetadata.swift" \
  "$ROOT_DIR/SpotifyLyrics/Lyrics/TrackTextNormalizer.swift" \
  "$ROOT_DIR/SpotifyLyrics/Lyrics/JapaneseRomanizer.swift" \
  "$ROOT_DIR/SpotifyLyrics/Lyrics/JapaneseReadingPipeline.swift" \
  "$ROOT_DIR/SpotifyLyrics/Lyrics/JapaneseKanaGenerator.swift" \
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LyricsMatcher.swift" \
  "$ROOT_DIR/SpotifyLyrics/AI/AITranslationModels.swift" \
  "$ROOT_DIR/SpotifyLyrics/AI/AITranslationConfiguration.swift" \
  "$ROOT_DIR/SpotifyLyrics/AI/AITranslationKeychain.swift" \
  "$ROOT_DIR/SpotifyLyrics/AI/AITranslationPromptBuilder.swift" \
  "$ROOT_DIR/SpotifyLyrics/AI/AITranslationResponseParser.swift" \
  "$ROOT_DIR/SpotifyLyrics/AI/OpenAICompatibleClient.swift" \
  "$ROOT_DIR/SpotifyLyrics/AI/AITranslationService.swift" \
  "$ROOT_DIR/SpotifyLyrics/Persistence/DatabaseModels.swift" \
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LyricsLanguageGate.swift" \
  "$ROOT_DIR/SpotifyLyrics/Persistence/LyricsPersistenceMapper.swift" \
  "$ROOT_DIR/SpotifyLyrics/Persistence/TranslationRepository.swift" \
  "$ROOT_DIR/SpotifyLyrics/Services/TranslationSessionController.swift" \
  "$ROOT_DIR/Tests/phase_2_5c_contract.swift" \
  -o "$TMP_DIR/phase-2-5c-contract"

"$TMP_DIR/phase-2-5c-contract"

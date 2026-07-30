#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h}/.."
BUILD="${TMPDIR:-/tmp}/spotifylyrics-translation-session-contract"
mkdir -p "$BUILD"

swiftc -parse-as-library \
  "$ROOT/SpotifyLyrics/Models/Models.swift" \
  "$ROOT/SpotifyLyrics/Lyrics/TrackIdentity.swift" \
  "$ROOT/SpotifyLyrics/Lyrics/LyricsModels.swift" \
  "$ROOT/SpotifyLyrics/Lyrics/AlignmentModels.swift" \
  "$ROOT/SpotifyLyrics/Lyrics/TrackAlias.swift" \
  "$ROOT/SpotifyLyrics/Lyrics/TrackMetadata.swift" \
  "$ROOT/SpotifyLyrics/Lyrics/TrackTextNormalizer.swift" \
  "$ROOT/SpotifyLyrics/Lyrics/JapaneseRomanizer.swift" \
  "$ROOT/SpotifyLyrics/Lyrics/JapaneseReadingPipeline.swift" \
  "$ROOT/SpotifyLyrics/Lyrics/JapaneseKanaGenerator.swift" \
  "$ROOT/SpotifyLyrics/Lyrics/LyricsMatcher.swift" \
  "$ROOT/SpotifyLyrics/AI/AITranslationModels.swift" \
  "$ROOT/SpotifyLyrics/AI/AITranslationConfiguration.swift" \
  "$ROOT/SpotifyLyrics/AI/AITranslationKeychain.swift" \
  "$ROOT/SpotifyLyrics/AI/AITranslationPromptBuilder.swift" \
  "$ROOT/SpotifyLyrics/AI/AITranslationResponseParser.swift" \
  "$ROOT/SpotifyLyrics/AI/OpenAICompatibleClient.swift" \
  "$ROOT/SpotifyLyrics/AI/AITranslationService.swift" \
  "$ROOT/SpotifyLyrics/Persistence/DatabaseModels.swift" \
  "$ROOT/SpotifyLyrics/Persistence/LyricsPersistenceMapper.swift" \
  "$ROOT/SpotifyLyrics/Persistence/TranslationRepository.swift" \
  "$ROOT/SpotifyLyrics/Services/TranslationSessionController.swift" \
  "$ROOT/Tests/translation_session_contract.swift" \
  -o "$BUILD/translation_session_contract"

"$BUILD/translation_session_contract"

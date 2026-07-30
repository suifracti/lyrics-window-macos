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
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LyricsQueryPlanner.swift" \
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LyricsRecoveryModels.swift" \
  "$ROOT_DIR/SpotifyLyrics/Editor/TextLyricsImport.swift" \
  "$ROOT_DIR/SpotifyLyrics/Editor/LRCImportExport.swift" \
  "$ROOT_DIR/SpotifyLyrics/Editor/LyricsEditorModels.swift" \
  "$ROOT_DIR/SpotifyLyrics/Editor/LyricsTimelineValidator.swift" \
  "$ROOT_DIR/SpotifyLyrics/AI/AITranslationModels.swift" \
  "$ROOT_DIR/SpotifyLyrics/AI/AITranslationConfiguration.swift" \
  "$ROOT_DIR/SpotifyLyrics/AI/AITranslationPromptBuilder.swift" \
  "$ROOT_DIR/SpotifyLyrics/AI/AITranslationResponseParser.swift" \
  "$ROOT_DIR/SpotifyLyrics/AI/AITranslationKeychain.swift" \
  "$ROOT_DIR/SpotifyLyrics/AI/OpenAICompatibleClient.swift" \
  "$ROOT_DIR/SpotifyLyrics/AI/AITranslationService.swift" \
  "$ROOT_DIR/SpotifyLyrics/Persistence/DatabaseModels.swift" \
  "$ROOT_DIR/SpotifyLyrics/Persistence/DatabaseMigrator.swift" \
  "$ROOT_DIR/SpotifyLyrics/Persistence/LyricsRepository.swift" \
  "$ROOT_DIR/SpotifyLyrics/Persistence/LyricsPersistenceMapper.swift" \
  "$ROOT_DIR/SpotifyLyrics/Persistence/TranslationRepository.swift" \
  "$ROOT_DIR/SpotifyLyrics/Persistence/LyricsEditingRepository.swift" \
  "$ROOT_DIR/SpotifyLyrics/Persistence/SQLiteLyricsRepository.swift" \
  "$ROOT_DIR/SpotifyLyrics/Services/LyricsEditorSessionController.swift" \
  "$ROOT_DIR/SpotifyLyrics/Services/TranslationSessionController.swift" \
  "$ROOT_DIR/Tests/synthetic_text_lyrics_e2e_contract.swift" \
  -o "$TMP_DIR/synthetic-text-lyrics-e2e"

"$TMP_DIR/synthetic-text-lyrics-e2e"

#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$ROOT/SpotifyLyrics/Persistence/SQLiteLyricsRepository.swift"
MAPPER="$ROOT/SpotifyLyrics/Persistence/LyricsPersistenceMapper.swift"
MODELS="$ROOT/SpotifyLyrics/Lyrics/LyricsModels.swift"
grep -Eq 'explicitlyTimedLineIndices' "$MODELS" "$MAPPER"
# documentWithoutTranslations must preserve mask
grep -A25 'documentWithoutTranslations' "$REPO" | grep -Eq 'explicitlyTimedLineIndices: document.explicitlyTimedLineIndices'
echo "assist_partial_persist_contract: PASS"

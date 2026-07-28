#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

echo "japanese alias + auto-complete foundation contract"

required_prod=(
  "SpotifyLyrics/Lyrics/TrackAlias.swift"
  "SpotifyLyrics/Lyrics/TrackMetadata.swift"
  "SpotifyLyrics/Lyrics/TrackTextNormalizer.swift"
  "SpotifyLyrics/Lyrics/JapaneseRomanizer.swift"
  "SpotifyLyrics/Lyrics/JapaneseReadingPipeline.swift"
  "SpotifyLyrics/Lyrics/JapaneseKanaGenerator.swift"
  "SpotifyLyrics/Lyrics/LyricsQueryPlanner.swift"
  "SpotifyLyrics/Lyrics/LyricsSafeMatcher.swift"
  "SpotifyLyrics/Lyrics/LyricsRecoveryModels.swift"
  "SpotifyLyrics/Lyrics/LyricsSearchManager.swift"
  "docs/superpowers/specs/2026-07-27-japanese-alias-lyrics-recovery-design.md"
  "docs/superpowers/specs/2026-07-27-one-button-lyrics-autocomplete-design.md"
)

for f in "${required_prod[@]}"; do
  test -f "$f" || { echo "missing: $f" >&2; exit 1; }
done

rg -q 'TrackAliasKind|original|kana|romaji|officialEnglish' \
  docs/superpowers/specs/2026-07-27-japanese-alias-lyrics-recovery-design.md
rg -q 'LyricsSearchManager|autoComplete|originalText|kanaText|romajiText' \
  docs/superpowers/specs/2026-07-27-one-button-lyrics-autocomplete-design.md
rg -q 'primaryOriginal|romajiTitleArtist|titleOnlyLoose' \
  docs/superpowers/specs/2026-07-27-japanese-alias-lyrics-recovery-design.md

# Product principle: one-button is default; paste is advanced fallback only
rg -q '一键|autoComplete|自动补全' docs/superpowers/specs/2026-07-27-one-button-lyrics-autocomplete-design.md
rg -q 'pasteOrImport|高级兜底|advanced' docs/superpowers/specs/2026-07-27-one-button-lyrics-autocomplete-design.md

TMP_DIR="$(mktemp -d /tmp/jp-alias.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT
cp Tests/japanese_alias_contract.swift "$TMP_DIR/main.swift"

SOURCES=(
  SpotifyLyrics/Models/Models.swift
  SpotifyLyrics/Lyrics/TrackIdentity.swift
  SpotifyLyrics/Lyrics/LyricsModels.swift
  SpotifyLyrics/Lyrics/AlignmentModels.swift
  SpotifyLyrics/Lyrics/TrackAlias.swift
  SpotifyLyrics/Lyrics/TrackMetadata.swift
  SpotifyLyrics/Lyrics/TrackTextNormalizer.swift
  SpotifyLyrics/Lyrics/JapaneseRomanizer.swift
  SpotifyLyrics/Lyrics/JapaneseReadingPipeline.swift
  SpotifyLyrics/Lyrics/JapaneseKanaGenerator.swift
  SpotifyLyrics/Lyrics/LyricsQueryPlanner.swift
  SpotifyLyrics/Lyrics/LyricsSafeMatcher.swift
  SpotifyLyrics/Lyrics/LyricsRecoveryModels.swift
  SpotifyLyrics/Lyrics/LyricsE2ELog.swift
  SpotifyLyrics/Lyrics/LyricsSearchManager.swift
  SpotifyLyrics/Lyrics/LRCParser.swift
  SpotifyLyrics/Lyrics/LyricsMatcher.swift
  "$TMP_DIR/main.swift"
)

swiftc -parse-as-library "${SOURCES[@]}" -o "$TMP_DIR/japanese-alias-contract"
"$TMP_DIR/japanese-alias-contract"

echo "japanese alias contract passed"

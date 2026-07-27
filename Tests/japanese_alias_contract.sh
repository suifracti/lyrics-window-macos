#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

echo "japanese alias contract: expecting RED until production models are implemented"

required_prod=(
  "SpotifyLyrics/Lyrics/TrackAlias.swift"
  "SpotifyLyrics/Lyrics/TrackMetadata.swift"
  "SpotifyLyrics/Lyrics/TrackTextNormalizer.swift"
  "SpotifyLyrics/Lyrics/JapaneseRomanizer.swift"
  "SpotifyLyrics/Lyrics/LyricsQueryPlanner.swift"
  "SpotifyLyrics/Lyrics/LyricsSafeMatcher.swift"
  "SpotifyLyrics/Lyrics/LyricsRecoveryModels.swift"
)

missing=0
for f in "${required_prod[@]}"; do
  if [[ ! -f "$f" ]]; then
    echo "missing production source: $f" >&2
    missing=1
  fi
done

if [[ ! -f "docs/superpowers/specs/2026-07-27-japanese-alias-lyrics-recovery-design.md" ]]; then
  echo "missing design spec" >&2
  exit 1
fi

# Design must lock critical rules
rg -q 'TrackAliasKind|original|kana|romaji|officialEnglish' \
  docs/superpowers/specs/2026-07-27-japanese-alias-lyrics-recovery-design.md
rg -q 'machineGenerated|autoHigh|versionConflict|noMatchExhausted' \
  docs/superpowers/specs/2026-07-27-japanese-alias-lyrics-recovery-design.md
rg -q 'primaryOriginal|romajiTitleArtist|titleOnlyLoose' \
  docs/superpowers/specs/2026-07-27-japanese-alias-lyrics-recovery-design.md
rg -q 'あやふや|Ayafuya' \
  docs/superpowers/specs/2026-07-27-japanese-alias-lyrics-recovery-design.md

if [[ "$missing" -ne 0 ]]; then
  echo "japanese alias contract RED: production sources not implemented (design-only phase)" >&2
  exit 1
fi

TMP_DIR="$(mktemp -d /tmp/jp-alias.XXXXXX)"
trap 'rm -f "$TMP_DIR"/* 2>/dev/null; rmdir "$TMP_DIR" 2>/dev/null || true' EXIT
cp Tests/japanese_alias_contract.swift "$TMP_DIR/main.swift"

SOURCES=(
  SpotifyLyrics/Models/Models.swift
  SpotifyLyrics/Lyrics/TrackIdentity.swift
  SpotifyLyrics/Lyrics/LyricsModels.swift
  SpotifyLyrics/Lyrics/TrackAlias.swift
  SpotifyLyrics/Lyrics/TrackMetadata.swift
  SpotifyLyrics/Lyrics/TrackTextNormalizer.swift
  SpotifyLyrics/Lyrics/JapaneseRomanizer.swift
  SpotifyLyrics/Lyrics/LyricsQueryPlanner.swift
  SpotifyLyrics/Lyrics/LyricsSafeMatcher.swift
  SpotifyLyrics/Lyrics/LyricsRecoveryModels.swift
  "$TMP_DIR/main.swift"
)

swiftc -parse-as-library "${SOURCES[@]}" -o "$TMP_DIR/japanese-alias-contract"
"$TMP_DIR/japanese-alias-contract"

echo "japanese alias contract passed"

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

echo "japanese morphology reading contract"

TMP_DIR="$(mktemp -d /tmp/jp-reading.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

SOURCES=(
  SpotifyLyrics/Models/Models.swift
  SpotifyLyrics/Lyrics/JapaneseRomanizer.swift
  SpotifyLyrics/Lyrics/JapaneseReadingPipeline.swift
  SpotifyLyrics/Lyrics/JapaneseKanaGenerator.swift
  Tests/japanese_reading_contract.swift
)

swiftc -parse-as-library "${SOURCES[@]}" -o "$TMP_DIR/japanese-reading-contract"
SPOTIFYLYRICS_MECAB_PATH="${SPOTIFYLYRICS_MECAB_PATH:-/opt/homebrew/bin/mecab}" \
  "$TMP_DIR/japanese-reading-contract"

echo "japanese reading contract passed"

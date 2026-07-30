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
  "$ROOT_DIR/SpotifyLyrics/Editor/LyricsEditorModels.swift" \
  "$ROOT_DIR/SpotifyLyrics/Editor/LyricsTimelineValidator.swift" \
  "$ROOT_DIR/SpotifyLyrics/Editor/LRCImportExport.swift" \
  "$ROOT_DIR/Tests/lyrics_editor_contract.swift" \
  -o "$TMP_DIR/lyrics-editor-contract"
"$TMP_DIR/lyrics-editor-contract"

#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCES=(
  "$ROOT_DIR/SpotifyLyrics/Models/Models.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/TrackIdentity.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LyricsModels.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LRCParser.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LyricsMatcher.swift"
  "$ROOT_DIR/Tests/lyrics_core_test.swift"
)

for source in "${SOURCES[@]}"; do
  if [[ ! -f "$source" ]]; then
    echo "missing production/test source: $source" >&2
    exit 1
  fi
done

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

cp "$ROOT_DIR/Tests/lyrics_core_test.swift" "$TMP_DIR/main.swift"
COMPILE_SOURCES=(
  "$ROOT_DIR/SpotifyLyrics/Models/Models.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/TrackIdentity.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LyricsModels.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LRCParser.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LyricsMatcher.swift"
  "$TMP_DIR/main.swift"
)
swiftc "${COMPILE_SOURCES[@]}" -o "$TMP_DIR/lyrics-core-contract"
"$TMP_DIR/lyrics-core-contract"

required_sources=(
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LocalLyricsProvider.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LRCLIBLyricsProvider.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/CompositeLyricsProvider.swift"
  "$ROOT_DIR/SpotifyLyrics/Services/LyricsSessionController.swift"
  "$ROOT_DIR/SpotifyLyrics/Views/Components/TrackBackdropView.swift"
  "$ROOT_DIR/SpotifyLyrics/Design/BackdropPalette.swift"
)
for source in "${required_sources[@]}"; do
  if [[ ! -f "$source" ]]; then
    echo "missing required slice source: $source" >&2
    exit 1
  fi
done

rg -q 'Mock Preview|enterMockPreview|exitMockPreview' "$ROOT_DIR/SpotifyLyrics/Services/PlaybackState.swift"
rg -q '暂未找到歌词|LyricsLoadState|loading|candidates|failed' "$ROOT_DIR/SpotifyLyrics/Views/Components/LyricsCanvasView.swift"
rg -q 'https://lrclib.net/api|syncedLyrics|plainLyrics' "$ROOT_DIR/SpotifyLyrics/Lyrics/LRCLIBLyricsProvider.swift"
rg -q 'Music/SpotifyLyrics/Lyrics|Application Support/SpotifyLyrics/Lyrics' "$ROOT_DIR/SpotifyLyrics/Lyrics/LocalLyricsProvider.swift"
rg -q 'Task.isCancelled|TrackIdentity|artwork' "$ROOT_DIR/SpotifyLyrics/Views/Components/TrackBackdropView.swift"

echo "real track lyrics contract passed"

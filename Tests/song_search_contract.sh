#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

required_files=(
  "SpotifyLyrics/Search/SongSearchModels.swift"
  "SpotifyLyrics/Search/SongSearchProvider.swift"
  "SpotifyLyrics/Search/LocalSearchProvider.swift"
  "SpotifyLyrics/Search/SpotifyCurrentTrackProvider.swift"
  "SpotifyLyrics/Search/LRCLIBProvider.swift"
  "SpotifyLyrics/Search/SongSearchManager.swift"
  "Tests/song_search_contract.swift"
)

for file in "${required_files[@]}"; do
  test -f "$file" || { echo "missing song search file: $file" >&2; exit 1; }
done

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
cp "Tests/song_search_contract.swift" "$TMP_DIR/main.swift"

SOURCES=(
  "SpotifyLyrics/Models/Models.swift"
  "SpotifyLyrics/Lyrics/TrackIdentity.swift"
  "SpotifyLyrics/Lyrics/LyricsModels.swift"
  "SpotifyLyrics/Lyrics/LRCParser.swift"
  "SpotifyLyrics/Lyrics/LyricsMatcher.swift"
  "SpotifyLyrics/Providers/PlaybackProvider.swift"
  "SpotifyLyrics/Search/SongSearchModels.swift"
  "SpotifyLyrics/Search/SongSearchProvider.swift"
  "SpotifyLyrics/Search/LocalSearchProvider.swift"
  "SpotifyLyrics/Search/SpotifyCurrentTrackProvider.swift"
  "SpotifyLyrics/Search/LRCLIBProvider.swift"
  "SpotifyLyrics/Search/SongSearchManager.swift"
  "$TMP_DIR/main.swift"
)

swiftc -parse-as-library "${SOURCES[@]}" -o "$TMP_DIR/song-search-contract"
"$TMP_DIR/song-search-contract"

echo "song search contract passed"

#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

swiftc -parse-as-library \
  "$ROOT/SpotifyLyrics/Models/Models.swift" \
  "$ROOT/SpotifyLyrics/Lyrics/TrackIdentity.swift" \
  "$ROOT/SpotifyLyrics/Lyrics/LyricsModels.swift" \
  "$ROOT/SpotifyLyrics/Lyrics/AlignmentModels.swift" \
  "$ROOT/SpotifyLyrics/Design/CurrentSongOperationState.swift" \
  "$ROOT/Tests/current_song_operations_contract.swift" \
  -o "$TMP/current-song-operations-contract"

"$TMP/current-song-operations-contract"

VIEW="$ROOT/SpotifyLyrics/Views/Components/CurrentSongOperationsView.swift"
if [[ ! -f "$VIEW" ]]; then
  echo "FAIL: missing current-song operations view" >&2
  exit 1
fi
grep -q 'selectNoLyricsVersion' "$VIEW"
grep -q 'selectNoTranslationVersion' "$VIEW"
grep -q 'prepareLyricsEditor\|prepareBlankLyricsEditor' "$VIEW"
grep -q 'retryLyrics' "$VIEW"
if grep -Eq 'SQLite|Timer\(|currentTime\s*=|\.seek\(' "$VIEW"; then
  echo "FAIL: current-song view owns persistence, timers, or implicit seek" >&2
  exit 1
fi

SETTINGS="$ROOT/SpotifyLyrics/Views/Settings/SettingsRootView.swift"
grep -q '随机度（Temperature）' "$SETTINGS"
if grep -q 'hasStoredKey = keyStore.read' "$SETTINGS"; then
  echo "FAIL: AI settings reads Keychain on ordinary page appearance" >&2
  exit 1
fi

echo "current song operations source contract: PASS"

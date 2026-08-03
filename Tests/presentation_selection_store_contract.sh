#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/presentation-selection-store-contract.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

swiftc -parse-as-library \
  "$ROOT/SpotifyLyrics/Models/Models.swift" \
  "$ROOT/SpotifyLyrics/Lyrics/TrackIdentity.swift" \
  "$ROOT/SpotifyLyrics/Lyrics/LyricsModels.swift" \
  "$ROOT/SpotifyLyrics/Lyrics/AlignmentModels.swift" \
  "$ROOT/SpotifyLyrics/Design/PresentationCatalog.swift" \
  "$ROOT/SpotifyLyrics/Design/PresentationSelectionStore.swift" \
  "$ROOT/Tests/presentation_selection_store_contract.swift" \
  -o "$TMP_DIR/presentation-selection-store-contract"

"$TMP_DIR/presentation-selection-store-contract"

if grep -Ev '^\s*///' "$ROOT/SpotifyLyrics/Design/PresentationSelectionStore.swift" \
  | grep -Eq 'PlaybackState|LyricsSessionController|TranslationSessionController|Timer\(|SQLite'; then
  echo "FAIL: presentation selection store owns business runtime state" >&2
  exit 1
fi

echo "presentation selection store: PASS"

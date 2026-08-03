#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/presentation-catalog-preview-contract.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

swiftc -parse-as-library \
  "$ROOT/SpotifyLyrics/Models/Models.swift" \
  "$ROOT/SpotifyLyrics/Lyrics/TrackIdentity.swift" \
  "$ROOT/SpotifyLyrics/Lyrics/AlignmentModels.swift" \
  "$ROOT/SpotifyLyrics/Lyrics/LyricsModels.swift" \
  "$ROOT/SpotifyLyrics/Design/PresentationCatalog.swift" \
  "$ROOT/SpotifyLyrics/Design/PresentationPreviewContext.swift" \
  "$ROOT/SpotifyLyrics/Design/PresentationPreviewEngine.swift" \
  "$ROOT/Tests/presentation_catalog_preview_contract.swift" \
  -o "$TMP_DIR/presentation-catalog-preview-contract"

"$TMP_DIR/presentation-catalog-preview-contract"

for file in \
  "$ROOT/SpotifyLyrics/Design/PresentationCatalog.swift" \
  "$ROOT/SpotifyLyrics/Design/PresentationPreviewContext.swift" \
  "$ROOT/SpotifyLyrics/Design/PresentationPreviewEngine.swift"; do
  if grep -Eq 'Timer\(|DispatchSourceTimer|CADisplayLink|SQLite|LyricsSessionController|TranslationSessionController' "$file"; then
    echo "FAIL: preview foundation owns runtime state ($file)" >&2
    exit 1
  fi
done

echo "presentation catalog/preview structure: PASS"

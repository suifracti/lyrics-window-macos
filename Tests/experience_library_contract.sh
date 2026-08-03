#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

swiftc \
  "$ROOT/SpotifyLyrics/Models/Models.swift" \
  "$ROOT/SpotifyLyrics/Lyrics/TrackIdentity.swift" \
  "$ROOT/SpotifyLyrics/Lyrics/LyricsModels.swift" \
  "$ROOT/SpotifyLyrics/Lyrics/AlignmentModels.swift" \
  "$ROOT/SpotifyLyrics/Design/PresentationCatalog.swift" \
  "$ROOT/SpotifyLyrics/Design/PresentationPreviewContext.swift" \
  "$ROOT/SpotifyLyrics/Design/PresentationPreviewEngine.swift" \
  "$ROOT/SpotifyLyrics/Design/PresentationPreviewRendererRegistry.swift" \
  "$ROOT/SpotifyLyrics/Design/SettingsCenterPresentation.swift" \
  "$ROOT/Tests/experience_library_contract.swift" \
  -o "$TMP/experience-library-contract"

"$TMP/experience-library-contract"

ADAPTERS="$ROOT/SpotifyLyrics/Views/Debug/PresentationPreviewAdapters.swift"
if grep -v '^///' "$ADAPTERS" | grep -Eq 'PlaybackState|LyricsSession|TranslationSession|Timer|SQLite|seek\('; then
  echo "FAIL: preview adapters contain forbidden runtime ownership or commands" >&2
  exit 1
fi

VIEW="$ROOT/SpotifyLyrics/Views/Settings/ExperienceLibrarySettingsView.swift"
if [[ ! -f "$VIEW" ]]; then
  echo "FAIL: missing release experience library view" >&2
  exit 1
fi
grep -q '体验版本库' "$VIEW"
grep -q 'PresentationPreviewAdapterView' "$VIEW"
grep -q 'applyPresentationSelection' "$VIEW"
grep -q 'Restore Recommended\|恢复推荐' "$VIEW"
if grep -Eq 'snapshotKey|renderer signature|Observer 数量|Debug geometry|Apply-to-Debug' "$VIEW"; then
  echo "FAIL: debug-only diagnostics leaked into release experience library" >&2
  exit 1
fi

echo "experience library source contract: PASS"

#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STYLE="$ROOT/SpotifyLyrics/Design/MainWindowLayoutStyle.swift"
SETTINGS="$ROOT/SpotifyLyrics/Settings/AppSettingsStore.swift"
MAIN="$ROOT/SpotifyLyrics/Views/MainWindow/MainLyricsWindowView.swift"
V3="$ROOT/SpotifyLyrics/Views/MainWindow/AppleMusicImmersiveV3WindowView.swift"
CATALOG="$ROOT/SpotifyLyrics/Design/PresentationCatalog.swift"

grep -q 'static let userSelectableCases' "$STYLE" || {
  echo 'FAIL: main-window layouts have no curated user-facing list' >&2
  exit 1
}
grep -q 'return "经典伴随 V1"' "$STYLE" || {
  echo 'FAIL: legacy focus/split family has not been merged under V1' >&2
  exit 1
}
grep -q 'enum ClassicCompanionPresentation' "$STYLE" || {
  echo 'FAIL: classic companion has no maintained presentation selector' >&2
  exit 1
}
for mode in automatic split lyricsFocus; do
  grep -q "case $mode" "$STYLE" || {
    echo "FAIL: classic companion mode is missing: $mode" >&2
    exit 1
  }
done
grep -q 'classicCompanionPresentation' "$SETTINGS" || {
  echo 'FAIL: classic companion presentation is not persisted' >&2
  exit 1
}
grep -q 'PresentationSelectionStore.storageKey' "$SETTINGS" || {
  echo 'FAIL: the already-migrated legacy focus catalog choice is not recovered' >&2
  exit 1
}
grep -q 'migratedClassicCompanionPresentation' "$SETTINGS" || {
  echo 'FAIL: classic companion migration is not centralized' >&2
  exit 1
}
grep -q '经典伴随呈现' "$MAIN" || {
  echo 'FAIL: classic companion presentation is not switchable from the main window' >&2
  exit 1
}
grep -q 'return "专辑沉浸 V2"' "$STYLE" || {
  echo 'FAIL: maintained immersive layout still exposes the engineering V3 name' >&2
  exit 1
}
grep -q 'return "实验工作台 V0"' "$STYLE" || {
  echo 'FAIL: experimental layout still exposes the Direction D/V4 engineering name' >&2
  exit 1
}

for view in "$MAIN" "$V3"; do
  grep -q 'MainWindowLayoutStyle.userSelectableCases' "$view" || {
    echo "FAIL: $(basename "$view") still exposes historical layouts" >&2
    exit 1
  }
done

grep -q 'storedLayout == MainWindowLayoutStyle.lyricsFocus.rawValue' "$SETTINGS" || {
  echo 'FAIL: saved lyrics-focus selections are not migrated into the fused family' >&2
  exit 1
}
grep -q 'mainWindow.immersiveSplit.v2' "$SETTINGS" || {
  echo 'FAIL: fused family does not preserve the maintained stable identity' >&2
  exit 1
}
layout_migration_line="$(grep -n 'let storedLayout' "$SETTINGS" | head -1 | cut -d: -f1)"
selection_store_line="$(grep -n 'self.presentationSelections = PresentationSelectionStore' "$SETTINGS" | head -1 | cut -d: -f1)"
if [[ -z "$layout_migration_line" || -z "$selection_store_line" || "$layout_migration_line" -ge "$selection_store_line" ]]; then
  echo 'FAIL: selection store is initialized before the legacy layout migration' >&2
  exit 1
fi

grep -q '"歌词专注（已融合）".*\.archived, \.archived' "$CATALOG" || {
  echo 'FAIL: historical lyrics-focus catalog entry is still selectable' >&2
  exit 1
}
grep -q '"经典伴随 V1"' "$CATALOG" || {
  echo 'FAIL: catalog does not expose the fused V1 family' >&2
  exit 1
}
grep -q '"专辑沉浸 V2"' "$CATALOG" || {
  echo 'FAIL: catalog does not expose the renamed V2 family' >&2
  exit 1
}
grep -q '"实验工作台 V0"' "$CATALOG" || {
  echo 'FAIL: catalog does not expose the renamed experimental family' >&2
  exit 1
}

echo 'PASS: main-window layout families are fused and compatibly named'

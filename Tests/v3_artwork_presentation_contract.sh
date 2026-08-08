#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SETTINGS="$ROOT/SpotifyLyrics/Settings/AppSettingsStore.swift"
BACKDROP="$ROOT/SpotifyLyrics/Views/Components/AppleMusicImmersiveV3BackdropView.swift"
WINDOW="$ROOT/SpotifyLyrics/Views/MainWindow/AppleMusicImmersiveV3WindowView.swift"

for stable_id in \
  'v3ArtworkPresentation.ambient.v1' \
  'v3ArtworkPresentation.stage.v1' \
  'v3ArtworkPresentation.classic.v1'; do
  grep -q "$stable_id" "$SETTINGS" || {
    echo "missing stable V3 artwork presentation ID: $stable_id" >&2
    exit 1
  }
done

grep -q 'v3ArtworkPresentationRawValue' "$SETTINGS"
grep -q 'v3AmbientBackdropEnabled' "$SETTINGS" || {
  echo "old ambient preference must remain as a migration input" >&2
  exit 1
}
grep -q 'switch settings.v3ArtworkPresentation' "$BACKDROP"
grep -q 'stageArtworkLayers' "$BACKDROP"
grep -q 'case .stage' "$BACKDROP"
grep -q 'Picker("背景构图"' "$WINDOW"
grep -q 'V3ArtworkPresentation.allCases' "$WINDOW"
grep -q 'showsForegroundArtwork' "$WINDOW"

echo "V3 artwork presentation contract passed"

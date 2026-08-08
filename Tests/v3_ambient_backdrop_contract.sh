#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SETTINGS="$ROOT/SpotifyLyrics/Settings/AppSettingsStore.swift"
BACKDROP="$ROOT/SpotifyLyrics/Views/Components/AppleMusicImmersiveV3BackdropView.swift"
WINDOW="$ROOT/SpotifyLyrics/Views/MainWindow/AppleMusicImmersiveV3WindowView.swift"

grep -q 'v3AmbientBackdropEnabled = "v3.ambientBackdropEnabled"' "$SETTINGS" || {
  echo 'FAIL: missing persistent V3 ambient backdrop key' >&2
  exit 1
}

grep -q '@Published public var v3AmbientBackdropEnabled: Bool' "$SETTINGS" || {
  echo 'FAIL: missing live V3 ambient backdrop setting' >&2
  exit 1
}

grep -q '?? true' "$SETTINGS" || {
  echo 'FAIL: album ambient backdrop is not enabled by default' >&2
  exit 1
}

grep -q 'Toggle("专辑环境光背景"' "$WINDOW" || {
  echo 'FAIL: V3 tuning panel has no ambient/legacy switch' >&2
  exit 1
}

grep -q 'settings.v3AmbientBackdropEnabled' "$BACKDROP" \
  && grep -q 'ambientArtworkLayers' "$BACKDROP" \
  && grep -q 'legacyArtworkLayers' "$BACKDROP" || {
  echo 'FAIL: backdrop does not explicitly route ambient and legacy renderers' >&2
  exit 1
}

grep -q 'ambientArtworkData' "$BACKDROP" \
  && grep -q 'maxPixel: 48' "$BACKDROP" || {
  echo 'FAIL: ambient renderer does not use the shared low-frequency artwork snapshot' >&2
  exit 1
}

if sed -n '/enum AppleMusicImmersiveV3BackdropKey/,/^}/p' "$BACKDROP" | grep -Eq 'currentTime|playbackTime|progress'; then
  echo 'FAIL: backdrop request key depends on playback time' >&2
  exit 1
fi

echo 'V3 ambient backdrop contract: PASS'

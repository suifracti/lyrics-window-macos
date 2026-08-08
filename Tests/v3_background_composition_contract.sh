#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BACKDROP="$ROOT/SpotifyLyrics/Views/Components/AppleMusicImmersiveV3BackdropView.swift"
SETTINGS="$ROOT/SpotifyLyrics/Settings/AppSettingsStore.swift"

test -f "$BACKDROP" || { echo 'FAIL: missing V3 backdrop' >&2; exit 1; }
test -f "$SETTINGS" || { echo 'FAIL: missing settings store' >&2; exit 1; }

stage="$({
  sed -n '/private func stageArtworkLayers/,/private var stageReadingVeil/p' "$BACKDROP"
} || true)"
ambient="$({
  sed -n '/private func ambientArtworkLayers/,/private var ambientReadingVeil/p' "$BACKDROP"
} || true)"
classic="$({
  sed -n '/private func legacyArtworkLayers/,/private func classicArtworkOffset/p' "$BACKDROP"
} || true)"

# Stage is the complete-cover composition. Its maximum size is clamped inside
# the canvas and it must not dissolve the cover through a radial mask.
grep -q 'scaledToFit()' <<<"$stage" || { echo 'FAIL: Stage does not preserve the complete cover' >&2; exit 1; }
grep -q 'stageArtworkPlaneSize' <<<"$stage" || { echo 'FAIL: Stage does not use canvas-clamped sizing' >&2; exit 1; }
if grep -q '\.mask(' <<<"$stage"; then
  echo 'FAIL: Stage still masks away part of the complete cover' >&2
  exit 1
fi

# Ambient is deliberately non-readable low-frequency artwork; Classic is the
# only mode allowed to use a full-canvas scaled-to-fill crop.
grep -q 'ambientImage' <<<"$ambient" || { echo 'FAIL: Ambient has no low-frequency field' >&2; exit 1; }
if grep -q 'Image(nsImage: image)' <<<"$ambient"; then
  echo 'FAIL: Ambient exposes the readable artwork instead of its low-frequency derivative' >&2
  exit 1
fi
grep -q 'scaledToFill()' <<<"$classic" || { echo 'FAIL: Classic no longer owns the zoomed crop' >&2; exit 1; }

# Blur is a per-composition preference. Switching to Stage must not inherit a
# deep Classic crop blur, and returning to a mode must restore its own value.
for key in v3BackdropBlurAmbient v3BackdropBlurStage v3BackdropBlurClassic; do
  grep -q "$key" "$SETTINGS" || { echo "FAIL: missing per-mode blur key $key" >&2; exit 1; }
done
grep -q 'v3BlurByPresentation' "$SETTINGS" || { echo 'FAIL: no per-mode blur memory' >&2; exit 1; }

echo 'PASS: V3 background compositions are structurally distinct'

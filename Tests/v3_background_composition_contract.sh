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
grep -q 'Image(nsImage: image)' <<<"$ambient" || {
  echo 'FAIL: Ambient 0% has no full-resolution clear source' >&2
  exit 1
}
grep -q 'let diffusionRadius = normalizedBlur \*' <<<"$ambient" || {
  echo 'FAIL: Ambient diffusion retains a non-zero minimum at 0%' >&2
  exit 1
}
grep -q 'opacity(normalizedBlur \*' <<<"$ambient" || {
  echo 'FAIL: Ambient low-frequency layer remains visible at 0%' >&2
  exit 1
}
grep -q 'scaledToFill()' <<<"$classic" || { echo 'FAIL: Classic no longer owns the zoomed crop' >&2; exit 1; }

# Stage 0% must use the original full-resolution cover without an always-on
# low-frequency fog or unconditional colour shift. Readability still comes
# from the local directional veil rather than changing the album itself.
grep -q 'opacity(normalizedBlur \*' <<<"$stage" || {
  echo 'FAIL: Stage low-frequency fog remains visible at 0%' >&2
  exit 1
}
grep -q 'saturation(1.0 + normalizedBlur \*' <<<"$stage" || {
  echo 'FAIL: Stage changes cover saturation even at 0%' >&2
  exit 1
}
grep -q 'brightness(-normalizedBlur \*' <<<"$stage" || {
  echo 'FAIL: Stage changes cover brightness even at 0%' >&2
  exit 1
}

# Blur is a per-composition preference. Switching to Stage must not inherit a
# deep Classic crop blur, and returning to a mode must restore its own value.
for key in v3BackdropBlurAmbient v3BackdropBlurStage v3BackdropBlurClassic; do
  grep -q "$key" "$SETTINGS" || { echo "FAIL: missing per-mode blur key $key" >&2; exit 1; }
done
grep -q 'v3BlurByPresentation' "$SETTINGS" || { echo 'FAIL: no per-mode blur memory' >&2; exit 1; }

echo 'PASS: V3 background compositions are structurally distinct'

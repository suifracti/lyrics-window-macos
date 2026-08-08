#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WINDOW="$ROOT/SpotifyLyrics/Views/MainWindow/AppleMusicImmersiveV3WindowView.swift"
METADATA="$ROOT/SpotifyLyrics/Views/Components/TrackMetadataView.swift"

grep -q 'presentation: .v3Immersive' "$WINDOW" || {
  echo 'FAIL: V3 does not opt into its readable metadata hierarchy' >&2
  exit 1
}

grep -q 'case v3Immersive' "$METADATA" \
  && grep -q 'Color.white.opacity(0.86)' "$METADATA" \
  && grep -q 'Color.white.opacity(0.64)' "$METADATA" || {
  echo 'FAIL: artist and album do not have a V3-specific white hierarchy' >&2
  exit 1
}

grep -q 'max(0, width \* progressFraction)' "$WINDOW" \
  && grep -q 'hoverThumbSize' "$WINDOW" || {
  echo 'FAIL: progress rail lacks accurate fill or hover thumb' >&2
  exit 1
}

grep -q 'struct V3TransportIconButton' "$WINDOW" \
  && grep -q '\.background(.thinMaterial, in: Circle())' "$WINDOW" \
  && grep -q '\.help(label)' "$WINDOW" || {
  echo 'FAIL: transport controls lack native material hierarchy or hover help' >&2
  exit 1
}

for symbol in backward.fill pause.fill play.fill forward.fill; do
  grep -q "\"$symbol\"" "$WINDOW" || {
    echo "FAIL: missing familiar transport symbol $symbol" >&2
    exit 1
  }
done

echo 'V3 track controls visual contract: PASS'

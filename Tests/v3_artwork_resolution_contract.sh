#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BACKDROP_FILE="$ROOT_DIR/SpotifyLyrics/Views/Components/AppleMusicImmersiveV3BackdropView.swift"

rg -q 'thumbnailData\(from: artworkData, maxPixel: 1280\)' "$BACKDROP_FILE" \
  || { echo "V3 visible artwork must keep a high-resolution thumbnail" >&2; exit 1; }
rg -q 'thumbnailData\(from: artworkData, maxPixel: 48\)' "$BACKDROP_FILE" \
  || { echo "V3 ambient derivative must remain low-frequency" >&2; exit 1; }
if rg -q 'thumbnailData\(from: artworkData, maxPixel: 640\)' "$BACKDROP_FILE"; then
  echo "V3 must not downsample the visible artwork to 640px" >&2
  exit 1
fi

echo "V3 artwork resolution contract: PASS"

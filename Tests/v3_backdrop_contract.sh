#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VIEW="$ROOT/SpotifyLyrics/Views/Components/AppleMusicImmersiveV3BackdropView.swift"

grep -q 'scaledToFit()' "$VIEW" || {
  echo 'FAIL: V3 backdrop does not preserve the complete artwork plane' >&2
  exit 1
}

grep -q 'frame(maxWidth: .infinity, maxHeight: .infinity)' "$VIEW" || {
  echo 'FAIL: V3 backdrop artwork plane does not fill the background canvas' >&2
  exit 1
}

if grep -q 'completeArtworkLayer' "$VIEW"; then
  echo 'FAIL: V3 backdrop still renders a second floating artwork card' >&2
  exit 1
fi

echo 'V3 backdrop contract: PASS'

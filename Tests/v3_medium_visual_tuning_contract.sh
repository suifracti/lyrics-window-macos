#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VIEW="$ROOT/SpotifyLyrics/Views/MainWindow/AppleMusicImmersiveV3WindowView.swift"

awk '/private func mediumLayout\(/,/^    private func smallLayout\(/' "$VIEW" | grep -q 'settings.v3ArtworkPosition' || {
  echo 'FAIL: V3 medium layout ignores the cover position setting' >&2
  exit 1
}

awk '/private func mediumLayout\(/,/^    private func smallLayout\(/' "$VIEW" | grep -q 'foregroundArtworkScale' || {
  echo 'FAIL: V3 medium layout does not use mode-aware foreground artwork scale' >&2
  exit 1
}

awk '/private func mediumLayout\(/,/^    private func smallLayout\(/' "$VIEW" | grep -q 'position == "right"' || {
  echo 'FAIL: V3 medium layout does not reorder the cover for right position' >&2
  exit 1
}

echo 'V3 medium visual tuning contract: PASS'

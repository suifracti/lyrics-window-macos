#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VIEW="$ROOT/SpotifyLyrics/Views/MainWindow/AppleMusicImmersiveV3WindowView.swift"

LAYOUT="$(awk '/private func adaptiveSplitLayout\(/,/^    private func instrumentalPosterLayout\(/' "$VIEW")"

grep -q 'settings.v3ArtworkPosition' <<<"$LAYOUT" || {
  echo 'FAIL: V3 adaptive split layout ignores the cover position setting' >&2
  exit 1
}

grep -q 'artworkScale: foregroundArtworkScale' <<<"$LAYOUT" || {
  echo 'FAIL: V3 adaptive split layout does not use mode-aware foreground artwork scale' >&2
  exit 1
}

grep -q 'position == "right"' <<<"$LAYOUT" || {
  echo 'FAIL: V3 adaptive split layout does not reorder the cover for right position' >&2
  exit 1
}

echo 'V3 medium visual tuning contract: PASS'

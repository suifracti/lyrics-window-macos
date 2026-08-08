#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VIEW="$ROOT/SpotifyLyrics/Views/MainWindow/AppleMusicImmersiveV3WindowView.swift"

grep -q 'let columnGap: CGFloat = 28' "$VIEW"
grep -q 'let rightWidth = max(1, contentWidth - leftWidth - columnGap)' "$VIEW"
grep -q 'V3ResponsiveGeometry.splitColumns' "$VIEW"
grep -q 'V3ResponsiveGeometry.boundedCoverSize' "$VIEW"
grep -q 'Spacer().frame(width: columnGap)' "$VIEW"
grep -q 'availableWidth: max(1, width -' "$VIEW"

echo "V3 cover layout contract: PASS"

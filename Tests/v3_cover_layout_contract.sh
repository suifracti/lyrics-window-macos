#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VIEW="$ROOT/SpotifyLyrics/Views/MainWindow/AppleMusicImmersiveV3WindowView.swift"

grep -q 'adaptiveSplitLayout(in: geometry)' "$VIEW"
grep -q 'V3ResponsiveGeometry.adaptiveSplitMetrics' "$VIEW"
grep -q 'coverSize: metrics.coverSize' "$VIEW"
grep -q 'Spacer().frame(width: metrics.gap)' "$VIEW"
grep -q 'width: metrics.contentWidth' "$VIEW"
grep -q 'availableWidth: max(1, width -' "$VIEW"

echo "V3 cover layout contract: PASS"

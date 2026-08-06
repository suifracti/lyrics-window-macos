#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VIEW="$ROOT/SpotifyLyrics/Views/MainWindow/AppleMusicImmersiveV3WindowView.swift"

grep -q 'let columnGap: CGFloat = 28' "$VIEW"
grep -q 'let rightWidth = max(1, contentWidth - leftWidth - columnGap)' "$VIEW"
grep -q 'artworkAlignment: artworkAlignment' "$VIEW"
grep -q 'position == "right" ? .trailing' "$VIEW"
grep -q 'showsAmbientLift: true' "$VIEW"
grep -q 'private func frameAlignment' "$VIEW"

echo "V3 cover layout contract: PASS"

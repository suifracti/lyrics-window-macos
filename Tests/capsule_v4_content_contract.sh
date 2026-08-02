#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VIEW="$ROOT_DIR/SpotifyLyrics/Views/Capsule/CapsuleLyricsView.swift"

for needle in \
  'dynamicIslandDarkV4Content' \
  'v4CollapsedContent' \
  'v4HoverContent' \
  'v4ExpandedContent' \
  'accessibilityReduceMotion' \
  'v4Artwork' \
  'v4TransportButton' \
  'CapsuleV4LyricRowView'; do
  grep -F "$needle" "$VIEW" >/dev/null
done

grep -F 'CapsuleDynamicIslandDarkV4.targetSize' "$VIEW" >/dev/null
grep -F 'current.originalText' "$VIEW" >/dev/null
grep -F 'lineLimit(1)' "$VIEW" >/dev/null
grep -F 'pause.fill' "$VIEW" >/dev/null
grep -F 'forward.end.fill' "$VIEW" >/dev/null
grep -F 'backward.end.fill' "$VIEW" >/dev/null

# v4 expanded content is a single current-row projection; it must not render
# the archived following-row context.
awk '
  /private var v4ExpandedContent/ { in_v4 = 1 }
  in_v4 && /private var controlFocusedContent/ { in_v4 = 0 }
  in_v4 && /selection\.following/ { found = 1 }
  END { exit(found ? 1 : 0) }
' "$VIEW"

echo "capsule v4 content contract passed"

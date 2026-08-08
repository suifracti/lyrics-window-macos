#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
V3="$ROOT/SpotifyLyrics/Views/MainWindow/AppleMusicImmersiveV3WindowView.swift"

test -f "$V3" || { echo "FAIL: missing V3 window" >&2; exit 1; }

viewport="$({
  sed -n '/private struct AppleMusicImmersiveV3LyricsViewport/,/private enum V3JapaneseReadingCache/p' "$V3"
} || true)"

# The V3 rows change height when the active line and auxiliary layers change.
# SwiftUI's lazy anchor-placement path can spin indefinitely when an animated
# scrollTo happens during that reflow. Keep this modest document eager and let
# ScrollViewReader own only the scroll animation.
if grep -Eq '^[[:space:]]*LazyVStack' <<<"$viewport"; then
  echo 'FAIL: V3 lyric viewport must not use LazyVStack with variable-height rows' >&2
  exit 1
fi

grep -q 'VStack(alignment: .leading, spacing: rowSpacing(synchronized: synchronized))' <<<"$viewport" || {
  echo 'FAIL: V3 lyric viewport must use the stable eager stack' >&2
  exit 1
}

grep -q 'onChange(of: currentIndex)' <<<"$viewport" || {
  echo 'FAIL: V3 scrolling must be driven by line changes, not playback ticks' >&2
  exit 1
}

grep -q 'let lines = state.liveLyrics' <<<"$viewport" || {
  echo 'FAIL: V3 does not snapshot the lyric projection once per refresh' >&2
  exit 1
}

grep -q 'trackStableKey: trackStableKey' <<<"$viewport" || {
  echo 'FAIL: V3 rows still recompute TrackIdentity independently' >&2
  exit 1
}

if grep -q 'state.liveCurrentLineIndex' <<<"$viewport"; then
  echo 'FAIL: V3 viewport must derive the current row from its shared lyric snapshot' >&2
  exit 1
fi

if grep -q 'onChange(of: state.currentTime)' <<<"$viewport"; then
  echo 'FAIL: V3 scrolling must not react to every playback tick' >&2
  exit 1
fi

echo 'PASS: V3 lyric scroll stability contract'

#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VIEW="$ROOT/SpotifyLyrics/Views/Capsule/CapsuleLyricsView.swift"
PRESENTATION="$ROOT/SpotifyLyrics/Lyrics/CapsuleLyricsPresentation.swift"

require() {
  local pattern="$1"
  local file="$2"
  grep -Eq "$pattern" "$file" || {
    echo "FAIL: missing /$pattern/ in $file" >&2
    exit 1
  }
}

require 'capsule\.legacy\.v1' "$PRESENTATION"
require 'capsule\.controlFocused\.v2' "$PRESENTATION"
require 'CapsuleLyricsPresentationVersion\.current' "$VIEW"
require 'Label\(' "$VIEW"

expanded="$(awk '
  /private var expandedContent/ { in_block=1 }
  /private func transportButton/ { in_block=0 }
  in_block { print }
' "$VIEW")"

row="$(awk '
  /private struct CapsuleLyricsRowView: View/ { in_block=1 }
  in_block { print }
' "$VIEW")"

if printf '%s\n' "$expanded" | grep -Eq 'selection\.following|distance:[[:space:]]*1'; then
  echo 'FAIL: expanded capsule renders a following lyric row' >&2
  exit 1
fi

if [ "$(printf '%s\n' "$expanded" | grep -c 'LyricLineView(' || true)" -gt 1 ]; then
  echo 'FAIL: expanded capsule renders multiple lyric rows' >&2
  exit 1
fi

printf '%s\n' "$expanded" | grep -Eq 'CapsuleLyricsRowView\(' || {
  echo 'FAIL: active expanded capsule does not use a capsule-scoped bounded lyric row' >&2
  exit 1
}

printf '%s\n' "$row" | grep -Eq 'static let (rowHeight|maxHeight)' || {
  echo 'FAIL: capsule lyric row has no explicit bounded height' >&2
  exit 1
}

printf '%s\n' "$row" | grep -Eq 'frame\(height:[[:space:]]*Self\.(rowHeight|maxHeight)' || {
  echo 'FAIL: capsule lyric row does not impose its bounded height' >&2
  exit 1
}

printf '%s\n' "$row" | grep -Eq 'clipped\(\)' || {
  echo 'FAIL: capsule lyric row does not clip overflowing ruby/multi-layer content' >&2
  exit 1
}

printf '%s\n' "$row" | grep -Eq 'lineLimit\(1\)' || {
  echo 'FAIL: capsule lyric row does not request single-line text truncation' >&2
  exit 1
}

printf '%s\n' "$row" | grep -Eq 'truncationMode' || {
  echo 'FAIL: capsule lyric row does not specify safe truncation' >&2
  exit 1
}

printf '%s\n' "$row" | grep -Eq 'LyricLineView\(' || {
  echo 'FAIL: capsule lyric row does not reuse the shared lyric renderer' >&2
  exit 1
}

printf '%s\n' "$row" | grep -Eq 'preferences:' || {
  echo 'FAIL: capsule lyric row does not forward display preferences' >&2
  exit 1
}

printf '%s\n' "$row" | grep -Eq 'visibleLayerCount:' || {
  echo 'FAIL: capsule lyric row does not forward the visible layer count' >&2
  exit 1
}

printf '%s\n' "$row" | grep -Eq 'language:' || {
  echo 'FAIL: capsule lyric row does not forward the live language gate' >&2
  exit 1
}

require 'liveLyrics' "$VIEW"
require 'liveLyricsState' "$VIEW"

echo "phase2.2 capsule control-focused contract passed"

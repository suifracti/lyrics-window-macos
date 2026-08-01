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

if printf '%s\n' "$expanded" | grep -Eq 'selection\.following|distance:[[:space:]]*1'; then
  echo 'FAIL: expanded capsule renders a following lyric row' >&2
  exit 1
fi

if [ "$(printf '%s\n' "$expanded" | grep -c 'LyricLineView(' || true)" -gt 1 ]; then
  echo 'FAIL: expanded capsule renders multiple lyric rows' >&2
  exit 1
fi

require 'lineLimit\(1\)' "$VIEW"
require 'truncationMode' "$VIEW"
require 'liveLyrics' "$VIEW"
require 'liveLyricsState' "$VIEW"

echo "phase2.2 capsule control-focused contract passed"

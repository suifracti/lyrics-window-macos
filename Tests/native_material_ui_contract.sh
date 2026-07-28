#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MAIN="$ROOT/SpotifyLyrics/Views/MainWindow/MainLyricsWindowView.swift"
SPLIT="$ROOT/SpotifyLyrics/Views/MainWindow/ImmersiveSplitWindowView.swift"
CANVAS="$ROOT/SpotifyLyrics/Views/Components/LyricsCanvasView.swift"
LINE="$ROOT/SpotifyLyrics/Views/Components/LyricLineView.swift"
BACKDROP="$ROOT/SpotifyLyrics/Views/Components/TrackBackdropView.swift"
PALETTE="$ROOT/SpotifyLyrics/Design/BackdropPalette.swift"
TOKENS="$ROOT/SpotifyLyrics/Design/LyricsDesignTokens.swift"
APP="$ROOT/SpotifyLyrics/Main.swift"

require() {
  local file="$1"
  local pattern="$2"
  local label="$3"
  if ! grep -Eq "$pattern" "$file"; then
    echo "FAIL: $label ($file does not contain /$pattern/)" >&2
    exit 1
  fi
}

for file in "$MAIN" "$SPLIT" "$CANVAS" "$LINE" "$BACKDROP" "$PALETTE" "$TOKENS" "$APP"; do
  test -f "$file" || { echo "FAIL: missing $file" >&2; exit 1; }
done

# Immersive V2 is the default, while the focus layout remains selectable.
require "$MAIN" 'mainWindowLayoutStyle.*immersiveSplit' 'immersive split default'
require "$MAIN" 'case \.lyricsFocus' 'focus layout remains switchable'
require "$MAIN" 'ImmersiveSplitWindowView' 'immersive split is in the main path'

# Normal playback must not carry a permanent connection label in the split view.
if grep -Eq 'Spotify 已连接' "$SPLIT"; then
  echo 'FAIL: immersive split contains a permanent Spotify connection label' >&2
  exit 1
fi

# Artwork work is track-bound, asynchronous, and cached instead of being driven by progress.
require "$BACKDROP" 'task\(id: requestKey\)' 'artwork change task key'
require "$BACKDROP" 'BackdropPaletteCache' 'cached palette path'
require "$PALETTE" 'actor BackdropPaletteCache' 'off-main palette cache'
require "$BACKDROP" 'ultraThinMaterial' 'material veil'
require "$BACKDROP" 'blur\(radius: [5-9][0-9]' 'large artwork blur'

# Typography reacts to width/layer count without scaling every inactive line.
require "$LINE" 'availableWidth' 'responsive lyric width input'
require "$LINE" 'visibleLayerCount' 'responsive lyric layer input'
if grep -Eq '\.scaleEffect\(' "$LINE"; then
  echo 'FAIL: LyricLineView uses scaleEffect for inactive lyrics' >&2
  exit 1
fi
require "$CANVAS" 'lyricRowSpacing\(' 'responsive lyric row spacing'
require "$CANVAS" '\.mask\(' 'lyric edge mask'
require "$CANVAS" 'easeInOut\(duration:' 'restrained line animation'

require "$TOKENS" 'func lyricEmphasis\(' 'responsive emphasis factory'
require "$TOKENS" 'visibleLayerCount' 'layer-aware token calculation'

# The app window uses a native hidden title bar without changing auxiliary windows.
require "$APP" 'windowStyle\(\.hiddenTitleBar\)' 'native hidden title bar'

echo 'PASS: native material UI contract'

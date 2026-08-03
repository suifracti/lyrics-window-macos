#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOKENS="$ROOT/SpotifyLyrics/Design/LyricsDesignTokens.swift"
LINE="$ROOT/SpotifyLyrics/Views/Components/LyricLineView.swift"
CANVAS="$ROOT/SpotifyLyrics/Views/Components/LyricsCanvasView.swift"
V3="$ROOT/SpotifyLyrics/Views/MainWindow/AppleMusicImmersiveV3WindowView.swift"
FULLSCREEN="$ROOT/SpotifyLyrics/Views/Fullscreen/FullScreenLyricsView.swift"
FLOATING="$ROOT/SpotifyLyrics/Views/Floating/FloatingLyricsView.swift"

require() {
  local file="$1"
  local pattern="$2"
  local label="$3"
  if ! grep -Eq "$pattern" "$file"; then
    echo "FAIL: $label ($file does not contain /$pattern/)" >&2
    exit 1
  fi
}

for file in "$TOKENS" "$LINE" "$CANVAS" "$V3" "$FULLSCREEN" "$FLOATING"; do
  test -f "$file" || { echo "FAIL: missing $file" >&2; exit 1; }
done

# Stable IDs and the smooth strategy are presentation policy only. They must
# not create a second session, clock, or persisted setting.
require "$TOKENS" 'lyricsTransition\.system\.v1' 'system transition ID'
require "$TOKENS" 'lyricsTransition\.smoothRelayout\.v1' 'smooth relayout transition ID'
require "$TOKENS" 'lyricsTransition\.none\.v1' 'none transition ID'
require "$TOKENS" 'smoothRelayoutV1' 'smooth relayout is available'
require "$TOKENS" 'static let active: LyricsTransitionStyle = \.smoothRelayoutV1' 'smooth relayout is the default'
require "$TOKENS" 'reduceMotionDuration' 'reduce motion duration'
require "$TOKENS" 'func animation\(reduceMotion: Bool\) -> Animation\?' 'optional transition animation'

# The active lyric rows animate layout signatures, not playback ticks. Stable
# LyricLine IDs remain the identity during wrapping and layer changes.
require "$LINE" 'LyricsLayoutSignature' 'shared lyric layout signature'
require "$LINE" 'layoutSignature' 'line layout signature'
require "$LINE" '\.animation\(transitionAnimation, value: layoutSignature\)' 'line relayout animation'
require "$LINE" '\.blur\(radius: reduceMotion \? 0 : emphasis\.blurRadius\)' 'reduce motion disables blur morph'
require "$CANVAS" '\.id\(line\.id\)' 'stable lyric line identity'

# V3 uses the same policy and resets the scroll surface by shared session
# revision so a fast track switch cannot animate old rows into the new track.
require "$V3" 'LyricsTransitionPolicy\.perform' 'V3 shared transition policy'
require "$V3" 'lyrics-document-' 'V3 session-bound scroll identity'
require "$V3" 'state\.liveLyricsSessionRevision' 'V3 session revision in scroll identity'
require "$V3" 'layoutSignature' 'V3 row layout signature'
require "$V3" 'transitionAnimation,' 'V3 relayout animation'
require "$V3" 'value: layoutSignature' 'V3 layout signature animation value'

# Compatibility/focus, fullscreen and floating surfaces use the same policy;
# none of them may introduce a playback timer or a currentTime-driven layout
# animation.
require "$CANVAS" 'LyricsTransitionPolicy\.perform' 'canvas shared transition policy'
require "$CANVAS" 'LyricsTransitionPolicy\.animation' 'canvas transition animation'
require "$FULLSCREEN" 'LyricsTransitionPolicy\.perform' 'fullscreen shared transition policy'
require "$FULLSCREEN" 'lyrics-document-' 'fullscreen session-bound scroll identity'
require "$FULLSCREEN" 'state\.liveLyricsSessionRevision' 'fullscreen session revision in scroll identity'
require "$FLOATING" 'LyricsTransitionPolicy\.perform' 'floating shared transition policy'
require "$FLOATING" 'lyrics-document-' 'floating session-bound scroll identity'
require "$FLOATING" 'state\.liveLyricsSessionRevision' 'floating session revision in scroll identity'

for file in "$TOKENS" "$LINE" "$CANVAS" "$V3" "$FULLSCREEN" "$FLOATING"; do
  if grep -Eq 'Timer|DispatchSourceTimer|CADisplayLink' "$file"; then
    echo "FAIL: transition surface added a second timer ($file)" >&2
    exit 1
  fi
done

if grep -Eq 'animation\([^)]*currentTime|withAnimation\([^)]*currentTime' "$LINE" "$CANVAS" "$V3" "$FULLSCREEN" "$FLOATING"; then
  echo 'FAIL: lyric layout animation is driven by playback tick' >&2
  exit 1
fi

echo 'PASS: lyrics transition contract'

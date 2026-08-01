#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WINDOW="$ROOT_DIR/SpotifyLyrics/Windows/FloatingLyricsWindowController.swift"
VIEW="$ROOT_DIR/SpotifyLyrics/Views/Floating/FloatingLyricsView.swift"
LEGACY="$ROOT_DIR/SpotifyLyrics/Views/LyricsViews.swift"
PLAYBACK="$ROOT_DIR/SpotifyLyrics/Services/PlaybackState.swift"

require_file() {
  local file="$1"
  local label="$2"
  test -f "$file" || {
    echo "FAIL: missing V1 $label ($file)" >&2
    exit 1
  }
}

require() {
  local file="$1"
  local pattern="$2"
  local label="$3"
  grep -Eq "$pattern" "$file" || {
    echo "FAIL: $label ($file does not contain /$pattern/)" >&2
    exit 1
  }
}

require_file "$WINDOW" "floating window controller source"
require_file "$VIEW" "floating presentation helper source"

require "$WINDOW" 'NSPanel' 'floating window uses NSPanel'
require "$WINDOW" 'ignoresMouseEvents' 'floating window exposes mouse pass-through'
require "$WINDOW" 'NSWindowDelegate' 'floating window owns delegate lifecycle'
require "$WINDOW" 'didChangeScreenParametersNotification' 'floating window observes display changes'
require "$WINDOW" 'isReleasedWhenClosed[[:space:]]*=[[:space:]]*false' 'floating window is retained after close'

require "$VIEW" 'PlaybackState' 'floating view consumes PlaybackState'
require "$VIEW" 'FloatingLyricsPresentationHelper' 'floating view uses the V1 presentation helper'
! grep -Eq 'Timer|LyricsProvider|LyricsSessionController|TranslationSessionController' "$VIEW" || {
  echo "FAIL: floating view creates a second clock/provider/session" >&2
  exit 1
}

require "$WINDOW" 'PlaybackState' 'window controller receives the shared PlaybackState'
if [ "$(grep -Ec 'FloatingLyricsView\(state: state, windowController: self\)' "$WINDOW")" -ne 1 ]; then
  echo 'FAIL: floating controller must inject exactly one shared PlaybackState view' >&2
  exit 1
fi
! grep -Eq 'FloatingLyricsView' "$ROOT_DIR/SpotifyLyrics/Windows/WindowManager.swift" || {
  echo 'FAIL: WindowManager still contains an alternate floating view construction path' >&2
  exit 1
}
! grep -Eq 'Timer|LyricsProvider|LyricsSessionController|TranslationSessionController' "$WINDOW" || {
  echo "FAIL: floating window controller creates a second clock/provider/session" >&2
  exit 1
}
if [ "$(grep -Ec 'Timer\.scheduledTimer' "$PLAYBACK")" -ne 1 ]; then
  echo 'FAIL: PlaybackState must remain the only polling timer owner' >&2
  exit 1
fi
! grep -Eq 'seek\(|togglePlayPause|currentTime[[:space:]]*=' "$VIEW" || {
  echo 'FAIL: floating view contains an implicit playback seek or clock mutation' >&2
  exit 1
}

require "$LEGACY" 'CapsulePlayerView' 'capsule compatibility path remains frozen'
require "$LEGACY" 'FullScreenLyricsView' 'full-screen compatibility path remains frozen'

echo "floating window behavior contract passed"

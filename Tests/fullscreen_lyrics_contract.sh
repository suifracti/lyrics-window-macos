#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VIEW="$ROOT_DIR/SpotifyLyrics/Views/Fullscreen/FullScreenLyricsView.swift"
PRESENTATION="$ROOT_DIR/SpotifyLyrics/Lyrics/FullScreenLyricsPresentation.swift"
CONTROLLER="$ROOT_DIR/SpotifyLyrics/Windows/FullScreenLyricsWindowController.swift"
MANAGER="$ROOT_DIR/SpotifyLyrics/Windows/WindowManager.swift"
MAIN="$ROOT_DIR/SpotifyLyrics/Main.swift"

require_file() {
  test -f "$1" || { echo "FAIL: missing $1" >&2; exit 1; }
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

require_file "$VIEW"
require_file "$PRESENTATION"
require_file "$CONTROLLER"

require "$VIEW" 'liveLyrics' 'fullscreen reads the live lyrics projection'
require "$VIEW" 'liveLyricsState' 'fullscreen reads the live lyrics state'
require "$VIEW" 'liveLyricsAreSynchronized' 'fullscreen reads the live synchronization flag'
require "$VIEW" 'liveCurrentLineIndex' 'fullscreen reads the shared current-line index'
require "$VIEW" 'currentTrackIdentity' 'fullscreen keys content by the live identity'
require "$VIEW" 'AppleMusicImmersiveV3BackdropView' 'fullscreen reuses the cached V3 backdrop'
require "$VIEW" 'LyricLineView' 'fullscreen reuses the shared lyric row renderer'

if grep -Eq 'state\\.lyrics([[:space:]]|\\.|\\)|,)' "$VIEW"; then
  echo "FAIL: fullscreen reads preview state.lyrics" >&2
  exit 1
fi
if grep -Eq 'state\\.(lyricsState|currentLineIndex)([[:space:]]|\\.|\\)|,)' "$VIEW"; then
  echo "FAIL: fullscreen reads preview state instead of live-only accessors" >&2
  exit 1
fi
if grep -Eq 'Timer|LyricsProvider|LyricsSessionController|TranslationSessionController' "$VIEW" "$CONTROLLER"; then
  echo "FAIL: fullscreen creates a second timer/provider/session" >&2
  exit 1
fi

require "$PRESENTATION" 'alignmentQueued' 'queued alignment is fail-closed'
require "$PRESENTATION" 'alignmentRunning' 'running alignment is fail-closed'
require "$PRESENTATION" 'alignmentPreview' 'unconfirmed alignment preview is fail-closed'
require "$PRESENTATION" 'hasTimingEvidence' 'synchronized presentation requires timing evidence'
require "$PRESENTATION" 'visibleIndices' 'fullscreen uses a bounded row projection'

require "$CONTROLLER" 'NSPanel' 'fullscreen owns a panel'
require "$CONTROLLER" 'NSWindowDelegate' 'fullscreen controller owns window lifecycle'
require "$CONTROLLER" '\.floating' 'fullscreen uses a floating level'
require "$CONTROLLER" 'canJoinAllSpaces' 'fullscreen spans Spaces'
require "$CONTROLLER" 'fullScreenAuxiliary' 'fullscreen can appear over system full-screen apps'
require "$CONTROLLER" 'isReleasedWhenClosed' 'fullscreen panel is retained'
require "$CONTROLLER" 'didChangeScreenParametersNotification' 'fullscreen follows screen changes'
if grep -Eq 'modalPanel|statusBar' "$CONTROLLER" "$MANAGER"; then
  echo "FAIL: fullscreen uses a system-critical window level" >&2
  exit 1
fi

require "$MANAGER" 'FullScreenLyricsWindowController' 'WindowManager owns the formal controller'
require "$MANAGER" 'temporarilyHideForFullScreen' 'WindowManager snapshots and hides auxiliary windows'
require "$MANAGER" 'restoreAfterFullScreen' 'WindowManager restores auxiliary windows'
require "$MAIN" '显示/隐藏全屏歌词' 'main menu exposes the fullscreen façade'

timer_count="$(grep -Rho 'Timer\.scheduledTimer' "$ROOT_DIR/SpotifyLyrics/Services/PlaybackState.swift" | wc -l | tr -d ' ')"
test "$timer_count" = "1" || {
  echo "FAIL: expected exactly one PlaybackState polling timer, found $timer_count" >&2
  exit 1
}

echo "fullscreen lyrics static contract passed"

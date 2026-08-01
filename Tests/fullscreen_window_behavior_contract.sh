#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONTROLLER="$ROOT_DIR/SpotifyLyrics/Windows/FullScreenLyricsWindowController.swift"
MANAGER="$ROOT_DIR/SpotifyLyrics/Windows/WindowManager.swift"

require() {
  local file="$1"
  local pattern="$2"
  local label="$3"
  grep -Eq "$pattern" "$file" || {
    echo "FAIL: $label ($file does not contain /$pattern/)" >&2
    exit 1
  }
}

require "$CONTROLLER" 'func show\(state: PlaybackState' 'show accepts shared PlaybackState'
require "$CONTROLLER" 'func hide\(\)' 'hide keeps the retained panel'
require "$CONTROLLER" 'func revealControls' 'controls can be revealed'
require "$CONTROLLER" 'func scheduleControlsHide' 'controls hide task is cancellable'
require "$CONTROLLER" 'NSEvent\.addLocalMonitorForEvents' 'Esc has a local recovery monitor'
require "$CONTROLLER" 'keyCode.*53|53.*keyCode' 'Esc hides fullscreen'
require "$CONTROLLER" 'setFrame.*screen\.frame|screen\.frame.*setFrame' 'panel follows target screen'
require "$CONTROLLER" 'NSScreen\.main' 'main screen fallback exists'
require "$CONTROLLER" 'NSScreen\.screens' 'screen list fallback exists'
require "$CONTROLLER" 'windowShouldClose' 'close hides instead of destroying'
require "$CONTROLLER" 'windowWillClose' 'window lifecycle is observed'

panel_init_count="$(grep -Ec 'FullScreenLyricsPanel\(' "$CONTROLLER")"
test "$panel_init_count" = "1" || {
  echo "FAIL: fullscreen must create exactly one retained panel initializer, found $panel_init_count" >&2
  exit 1
}

require "$MANAGER" 'fullScreenAuxiliaryVisibilitySnapshot' 'manager keeps transient auxiliary snapshot'
require "$MANAGER" 'finishFullScreenHide' 'manager restores after controller hide'
require "$MANAGER" 'showFullScreen' 'manager exposes show façade'
require "$MANAGER" 'hideFullScreen' 'manager exposes hide façade'

if grep -Eq 'makeKeyAndOrderFront|makeKey' "$CONTROLLER"; then
  echo "FAIL: fullscreen must not force keyboard focus" >&2
  exit 1
fi
if grep -Eq 'seek\(|seekTo' "$CONTROLLER"; then
  echo "FAIL: fullscreen window controller must not seek playback" >&2
  exit 1
fi

echo "fullscreen window behavior contract passed"

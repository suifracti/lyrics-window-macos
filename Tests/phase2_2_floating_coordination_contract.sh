#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MANAGER="$ROOT/SpotifyLyrics/Windows/WindowManager.swift"
CAPSULE="$ROOT/SpotifyLyrics/Views/Capsule/CapsuleLyricsView.swift"
MAIN="$ROOT/SpotifyLyrics/Main.swift"

require() {
  local pattern="$1"
  local file="$2"
  if ! grep -Eq "$pattern" "$file"; then
    echo "FAIL: missing /$pattern/ in $file" >&2
    exit 1
  fi
}

require 'public func showCapsule\(state: PlaybackState\)' "$MANAGER"
require 'public func hideCapsule\(\)' "$MANAGER"
require 'public func toggleCapsule\(state: PlaybackState\)' "$MANAGER"
require 'public func showFloatingLyrics\(state: PlaybackState\)' "$MANAGER"
require 'public func hideFloatingLyrics\(\)' "$MANAGER"
require 'public func toggleFloatingLyrics\(state: PlaybackState\)' "$MANAGER"
require 'public func restoreFloatingSurfacesAfterFullscreen\(\)' "$MANAGER"
require 'WindowManager\.shared\.toggleFloatingLyrics\(state: state\)' "$CAPSULE"

if grep -Eq 'FloatingLyricsWindowController\(|CapsuleLyricsWindowController\(' "$CAPSULE"; then
  echo "FAIL: Capsule view must not construct a window controller" >&2
  exit 1
fi

require 'fullScreenAuxiliaryVisibilitySnapshot' "$MANAGER"
require 'floatingWasVisible: Bool' "$MANAGER"
require 'capsuleWasVisible: Bool' "$MANAGER"

echo "phase2.2 floating coordination contract passed"

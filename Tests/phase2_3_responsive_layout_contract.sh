#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOKENS="$ROOT/SpotifyLyrics/Design/LyricsDesignTokens.swift"
LAYOUT="$ROOT/SpotifyLyrics/Design/MainWindowLayoutStyle.swift"
VIEW="$ROOT/SpotifyLyrics/Views/MainWindow/AppleMusicImmersiveV3WindowView.swift"

require() {
  local needle="$1"
  local file="$2"
  grep -Fq "$needle" "$file" || {
    echo "missing '$needle' in $file" >&2
    exit 1
  }
}

# Phase 2.3A: the shared token surface distinguishes the technical window
# floor from the comfortable layout reference and exposes semantic motion,
# typography, spacing, surface, radius, and shadow values.
require "technicalMinimumMainWindowSize" "$TOKENS"
require "comfortableMainWindowSize" "$TOKENS"
require "enum Spacing" "$TOKENS"
require "enum Typography" "$TOKENS"
require "enum Motion" "$TOKENS"
require "reduceMotion" "$TOKENS"

# Phase 2.3B: responsive resolution is pure and has explicit modes. The V3
# view must consume that resolver rather than inventing another breakpoint set.
require "enum MainWindowResponsiveMode" "$LAYOUT"
require "case wide" "$LAYOUT"
require "case medium" "$LAYOUT"
require "case small" "$LAYOUT"
require "case lyricsFocus" "$LAYOUT"
require "MainWindowResponsiveMode.resolve" "$VIEW"
require "accessibilityReduceMotion" "$VIEW"
require "technicalMinimumSize" "$VIEW"

# The automatic compact focus preference remains opt-in and is not a new
# settings store or a second playback/session state.
require "automaticCompactLyricsFocus" "$ROOT/SpotifyLyrics/Settings/AppSettingsStore.swift"
require "?? false" "$ROOT/SpotifyLyrics/Settings/AppSettingsStore.swift"

echo "phase2.3 responsive layout contract: PASS"

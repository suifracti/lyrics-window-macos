#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOKENS="$ROOT/SpotifyLyrics/Design/LyricsDesignTokens.swift"
V3="$ROOT/SpotifyLyrics/Views/MainWindow/AppleMusicImmersiveV3WindowView.swift"

require() {
  local needle="$1"
  local file="$2"
  grep -Fq "$needle" "$file" || {
    echo "FAIL: missing '$needle' in $file" >&2
    exit 1
  }
}

# Progress is a shared visual vocabulary, not a second playback source.
require "enum Progress" "$TOKENS"
require "AppleMusicImmersiveV3PlaybackProgress" "$V3"
require "AppleMusicImmersiveV3ProgressDensity" "$V3"
require "case wide" "$V3"
require "case medium" "$V3"
require "case small" "$V3"
require "case focus" "$V3"

# The four responsive presentations select density only; they do not create
# another timer, provider, session, or current-line calculator.
require "progressDensity: .wide" "$V3"
require "progressDensity: .medium" "$V3"
require "progressDensity: .small" "$V3"
require "density: .focus" "$V3"
require "onEditingChanged" "$V3"
require "onHover" "$V3"
! grep -Eq "Timer\\(|DispatchSourceTimer|PlaybackProvider|LyricsSessionController|TranslationSessionController" "$V3"

# Lyric timing is explicitly separate from playback progress.  Unsynchronised
# lyrics must expose a reading/status state and never a fake current-line bar.
require "AppleMusicImmersiveV3LyricProgressStatus" "$V3"
require "liveLyricsAreSynchronized" "$V3"
require "plainText" "$V3"
require "未排轴" "$V3"
require ": nil" "$V3"

echo "phase2.3 progress visual contract: PASS"

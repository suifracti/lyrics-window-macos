#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOKENS="$ROOT/SpotifyLyrics/Design/LyricsDesignTokens.swift"
MODELS="$ROOT/SpotifyLyrics/Lyrics/LyricsModels.swift"
CANVAS="$ROOT/SpotifyLyrics/Views/Components/LyricsCanvasView.swift"
V3="$ROOT/SpotifyLyrics/Views/MainWindow/AppleMusicImmersiveV3WindowView.swift"
SEARCH="$ROOT/SpotifyLyrics/Views/Components/SongSearchPopover.swift"

require() {
  local needle="$1"
  local file="$2"
  grep -Fq "$needle" "$file" || {
    echo "FAIL: missing '$needle' in $file" >&2
    exit 1
  }
}

# Stable presentation policy: the renderer is a view concern, not a new
# persisted setting or a second lyrics state machine.
require "lyricsStatePresentation.system.v1" "$TOKENS"
require "lyricsStatePresentation.contentFirst.v1" "$TOKENS"
require "static let active: LyricsStatePresentation = .contentFirstV1" "$TOKENS"
require "enum LyricsStatePresentation" "$TOKENS"

# The same content-first surface is used by the compatibility canvas and V3.
require "LyricsStateContentFirstView" "$CANVAS"
require "LyricsStateContentFirstView" "$V3"
require "contentFirstStateContent" "$CANVAS"
require "正在搜索歌词" "$CANVAS"
require "暂无歌词" "$CANVAS"
require "歌词暂不可用" "$CANVAS"
require "暂不使用歌词" "$CANVAS"
require "friendlyFailureDetail" "$CANVAS"

# Candidate cards expose evidence and preview before adoption.
require "预览" "$CANVAS"
require "含时间轴" "$CANVAS"
require "source.displayName" "$CANVAS"
require "language" "$CANVAS"
require "不使用任何歌词版本" "$CANVAS"

# Search is a presentation of SongSearchManager only; it must not introduce
# a playback or lyrics session.
require "需要授权 Spotify" "$SEARCH"
require "没有找到歌曲" "$SEARCH"
if grep -Eq "Timer\\(|LyricsSessionController|PlaybackProvider" "$SEARCH"; then
  echo "FAIL: search state presentation introduced an independent runtime" >&2
  exit 1
fi

# Content-first state rendering must not own a clock or mutate persistence.
if grep -Eq "Timer\\(|DispatchSourceTimer|LyricsSessionController|TranslationSessionController|SQLite" "$CANVAS"; then
  echo "FAIL: lyrics state presentation introduced an independent runtime" >&2
  exit 1
fi

echo "phase2.3f state presentation contract: PASS"

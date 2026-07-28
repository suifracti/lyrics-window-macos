#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root_dir"

required_files=(
  "SpotifyLyrics/Design/MainWindowLayoutStyle.swift"
  "SpotifyLyrics/Views/MainWindow/ImmersiveSplitWindowView.swift"
  "SpotifyLyrics/Views/Components/ArtworkView.swift"
  "SpotifyLyrics/Views/Components/TrackMetadataView.swift"
  "SpotifyLyrics/Views/Components/PlaybackControlsView.swift"
  "SpotifyLyrics/Views/Components/LyricsViewport.swift"
  "SpotifyLyrics/Views/Components/ArtworkBackgroundView.swift"
)

for file in "${required_files[@]}"; do
  test -f "$file" || { echo "missing required layout file: $file" >&2; exit 1; }
done

grep -q 'enum MainWindowLayoutStyle' SpotifyLyrics/Design/MainWindowLayoutStyle.swift
grep -q 'case lyricsFocus' SpotifyLyrics/Design/MainWindowLayoutStyle.swift
grep -q 'case immersiveSplit' SpotifyLyrics/Design/MainWindowLayoutStyle.swift
grep -q 'mainWindowLayoutStyle' SpotifyLyrics/Views/MainWindow/MainLyricsWindowView.swift
grep -q 'ImmersiveSplitWindowView' SpotifyLyrics/Views/MainWindow/MainLyricsWindowView.swift
grep -q 'ArtworkBackgroundView' SpotifyLyrics/Views/MainWindow/MainLyricsWindowView.swift
grep -q 'LyricsViewport' SpotifyLyrics/Views/Components/LyricsViewport.swift
grep -q 'ZStack(alignment: .bottom)' SpotifyLyrics/Views/MainWindow/MainLyricsWindowView.swift
grep -q 'PlaybackState' SpotifyLyrics/Views/MainWindow/ImmersiveSplitWindowView.swift
grep -q 'ArtworkView' SpotifyLyrics/Views/MainWindow/ImmersiveSplitWindowView.swift
! rg -q 'SpotifyDesktopProvider' SpotifyLyrics/Views
grep -q 'width: 1040' SpotifyLyrics/Design/LyricsDesignTokens.swift
grep -q 'height: 680' SpotifyLyrics/Design/LyricsDesignTokens.swift
grep -q 'width: 760' SpotifyLyrics/Design/LyricsDesignTokens.swift
grep -q 'height: 520' SpotifyLyrics/Design/LyricsDesignTokens.swift

for file in "${required_files[@]}"; do
  basename="$(basename "$file")"
  grep -q "$basename" SpotifyLyrics.xcodeproj/project.pbxproj
done

# The kana display modes are shared by the main, floating and fullscreen lyric
# surfaces.  Keep the legacy surfaces in the contract while allowing them to
# consume the same mode selection instead of freezing them at the old layout.
grep -q 'kanaDisplayMode' SpotifyLyrics/Views/LyricsViews.swift
grep -q 'KanaReplacementLineView' SpotifyLyrics/Views/LyricsViews.swift
grep -q 'RubyLineView' SpotifyLyrics/Views/LyricsViews.swift

echo "phase2 layout contract passed"

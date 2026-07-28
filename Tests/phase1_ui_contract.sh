#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

required_files='
SpotifyLyrics/Views/MainWindow/MainLyricsWindowView.swift
SpotifyLyrics/Views/Components/LyricsCanvasView.swift
SpotifyLyrics/Views/Components/LyricLineView.swift
SpotifyLyrics/Views/Components/TrackHeaderView.swift
SpotifyLyrics/Views/Components/LyricsPreferencesPopover.swift
SpotifyLyrics/Design/LyricsDesignTokens.swift'

for relative_path in $required_files; do
    test -f "$ROOT_DIR/$relative_path" || {
        printf 'missing required phase-1 file: %s\n' "$relative_path" >&2
        exit 1
    }
done

grep -q 'MainLyricsWindowView' "$ROOT_DIR/SpotifyLyrics/Main.swift"
grep -Eq 'defaultSize\(width: 1152, height: 720\)' "$ROOT_DIR/SpotifyLyrics/Main.swift"
grep -q 'minimumMainWindowSize.width' "$ROOT_DIR/SpotifyLyrics/Views/MainWindow/MainLyricsWindowView.swift"
grep -q 'minimumMainWindowSize.height' "$ROOT_DIR/SpotifyLyrics/Views/MainWindow/MainLyricsWindowView.swift"
grep -q 'minWidth: layoutStyle == .appleMusicImmersiveV3 ? 800' "$ROOT_DIR/SpotifyLyrics/Views/MainWindow/MainLyricsWindowView.swift"
grep -q 'minHeight: layoutStyle == .appleMusicImmersiveV3 ? 600' "$ROOT_DIR/SpotifyLyrics/Views/MainWindow/MainLyricsWindowView.swift"

if grep -q 'NavigationSplitView' "$ROOT_DIR/SpotifyLyrics/Views/MainWindow/MainLyricsWindowView.swift"; then
    printf 'phase-1 main window still contains NavigationSplitView\n' >&2
    exit 1
fi

grep -q 'LyricsDesignTokens' "$ROOT_DIR/SpotifyLyrics/Views/Components/LyricLineView.swift"
grep -q 'LyricsPreferencesPopover' "$ROOT_DIR/SpotifyLyrics/Views/MainWindow/MainLyricsWindowView.swift"

# Main-window refinement contract: keep these visual affordances explicit in source
# so a later regression cannot silently fall back to the original test-panel shell.
grep -q 'TrackArtworkView' "$ROOT_DIR/SpotifyLyrics/Views/Components/TrackHeaderView.swift"
rg -q 'backward.fill' "$ROOT_DIR/SpotifyLyrics/Views/MainWindow/MainLyricsWindowView.swift" "$ROOT_DIR/SpotifyLyrics/Views/Components/PlaybackControlsView.swift"
rg -q 'forward.fill' "$ROOT_DIR/SpotifyLyrics/Views/MainWindow/MainLyricsWindowView.swift" "$ROOT_DIR/SpotifyLyrics/Views/Components/PlaybackControlsView.swift"
grep -q 'GeometryReader' "$ROOT_DIR/SpotifyLyrics/Views/Components/LyricsCanvasView.swift"
grep -q 'blurRadius: 0.6' "$ROOT_DIR/SpotifyLyrics/Design/LyricsDesignTokens.swift"
grep -q 'blurRadius: 1.8' "$ROOT_DIR/SpotifyLyrics/Design/LyricsDesignTokens.swift"
grep -q '窗口模式' "$ROOT_DIR/SpotifyLyrics/Views/MainWindow/MainLyricsWindowView.swift"
grep -q 'help("窗口模式' "$ROOT_DIR/SpotifyLyrics/Views/MainWindow/MainLyricsWindowView.swift"

printf '%s\n' 'phase-1 UI contract passed'

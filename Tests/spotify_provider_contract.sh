#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

required_files='
SpotifyLyrics/Providers/PlaybackProvider.swift
SpotifyLyrics/Providers/SpotifyDesktopProvider.swift
SpotifyLyrics/Providers/MockPlaybackProvider.swift
SpotifyLyrics/Providers/ArtworkImageLoader.swift
SpotifyLyrics/SpotifyLyrics.entitlements'

for relative_path in $required_files; do
    test -f "$ROOT_DIR/$relative_path" || {
        printf 'missing Spotify provider file: %s\n' "$relative_path" >&2
        exit 1
    }
done

test -d /Applications/Spotify.app || {
    printf '%s\n' 'Spotify.app is required for the desktop provider contract' >&2
    exit 1
}

spotify_dictionary=$(sdef /Applications/Spotify.app)
printf '%s' "$spotify_dictionary" | grep -q 'property name="current track"'
printf '%s' "$spotify_dictionary" | grep -q 'property name="player position"'
printf '%s' "$spotify_dictionary" | grep -q 'property name="artwork url"'
printf '%s' "$spotify_dictionary" | grep -q 'command name="previous track"'
printf '%s' "$spotify_dictionary" | grep -q 'command name="next track"'

grep -q 'protocol PlaybackProvider' "$ROOT_DIR/SpotifyLyrics/Providers/PlaybackProvider.swift"
grep -q 'SpotifyDesktopProvider' "$ROOT_DIR/SpotifyLyrics/Providers/SpotifyDesktopProvider.swift"
grep -q 'artworkURL' "$ROOT_DIR/SpotifyLyrics/Models/Models.swift"
grep -q 'PlaybackProvider' "$ROOT_DIR/SpotifyLyrics/Services/PlaybackState.swift"
grep -q 'NSAppleEventsUsageDescription' "$ROOT_DIR/SpotifyLyrics.xcodeproj/project.pbxproj"
grep -q 'CODE_SIGN_ENTITLEMENTS' "$ROOT_DIR/SpotifyLyrics.xcodeproj/project.pbxproj"
grep -q 'com.apple.security.automation.apple-events' "$ROOT_DIR/SpotifyLyrics/SpotifyLyrics.entitlements"
grep -q 'providerStatus' "$ROOT_DIR/SpotifyLyrics/Views/MainWindow/MainLyricsWindowView.swift"

printf '%s\n' 'Spotify desktop provider contract passed'

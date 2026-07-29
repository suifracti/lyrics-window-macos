#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STORE="$ROOT/SpotifyLyrics/Settings/AppSettingsStore.swift"
PROVIDERS="$ROOT/SpotifyLyrics/Settings/LyricsProviderConfiguration.swift"
SETTINGS="$ROOT/SpotifyLyrics/Views/Settings/SettingsRootView.swift"
MANAGER="$ROOT/SpotifyLyrics/Lyrics/LyricsSearchManager.swift"
REPOSITORY="$ROOT/SpotifyLyrics/Persistence/LyricsRepository.swift"
WINDOWS="$ROOT/SpotifyLyrics/Settings/WindowStatePersistence.swift"

test -f "$STORE"
test -f "$PROVIDERS"
test -f "$SETTINGS"
test -f "$WINDOWS"
grep -Eq 'mainWindowLayoutStyle|spotify\.clientID' "$STORE"
grep -Eq 'display\.kanaDisplayMode|display\.assistantFontSize|display\.rubyFontSize' "$STORE"
grep -Eq 'lyrics\.providers\.enabled|lyrics\.providers\.order' "$STORE"
grep -Eq 'LyricsProviderID' "$PROVIDERS"
grep -Eq 'updateProviders|providerSnapshot' "$MANAGER"
grep -Eq 'statistics\(\)|createBackup|clearLyricsCache' "$REPOSITORY"
grep -Eq 'NavigationSplitView|SettingsCategory' "$SETTINGS"
grep -Eq 'SettingsWindowBehavior|canJoinAllApplications' "$WINDOWS"
grep -Eq 'SettingsWindowBehavior' "$SETTINGS"

echo 'settings contract passed'

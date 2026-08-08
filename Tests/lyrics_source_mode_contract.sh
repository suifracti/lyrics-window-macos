#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STORE="$ROOT/SpotifyLyrics/Settings/AppSettingsStore.swift"
PROVIDERS="$ROOT/SpotifyLyrics/Settings/LyricsProviderConfiguration.swift"
SETTINGS="$ROOT/SpotifyLyrics/Views/Settings/SettingsRootView.swift"
PLAYBACK="$ROOT/SpotifyLyrics/Services/PlaybackState.swift"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/lyrics-source-mode-contract.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

# Stable IDs and mode model
grep -Eq 'lyricsSourceMode\.standardFree\.v1' "$PROVIDERS"
grep -Eq 'lyricsSourceMode\.experimentalFree\.v1' "$PROVIDERS"
grep -Eq 'enum LyricsSourceMode' "$PROVIDERS"
grep -Eq 'orderedEnabledIDs\(for mode' "$PROVIDERS"
grep -Eq 'LyricsProviderCapabilityClass' "$PROVIDERS"
grep -Eq 'discoveryOnly|experimentalFree|openFree|userContent' "$PROVIDERS"
grep -Eq 'LyricsUserContentPolicy' "$PROVIDERS"
grep -Eq 'enum LyricsDiscoverySite' "$PROVIDERS"
grep -Eq 'allowsLyricsBody: false' "$PROVIDERS"

# Single UserDefaults setting
grep -Eq 'lyrics\.sourceMode' "$STORE"
grep -Eq 'lyricsSourceModeRawValue|restoreDefaultLyricsSourceMode' "$STORE"
grep -Eq 'LyricsSourceMode\.default' "$STORE"

# Runtime chain rebuild on mode + configuration
grep -Eq 'orderedEnabledIDs\(for: mode\)' "$PLAYBACK"
grep -Eq 'lyricsSourceModeRawValue' "$PLAYBACK"
grep -Eq 'makeDefaultLyricsProviders' "$PLAYBACK"
grep -Eq 'NetEaseExperimentalLyricsProvider|QQExperimentalLyricsProvider' "$PLAYBACK"

# Settings UI: single mode control + experimental banner + restore default
grep -Eq 'lyricsSourceMode\.picker' "$SETTINGS"
grep -Eq 'lyricsSourceMode\.restoreDefault' "$SETTINGS"
grep -Eq 'lyricsSourceMode\.experimentalBanner' "$SETTINGS"
grep -Eq 'LyricsSourceMode\.allCases' "$SETTINGS"
grep -Eq 'LyricsDiscoverySite\.allCases' "$SETTINGS"
grep -Eq 'Uta-Net|UtaTime|AWA' "$SETTINGS"
grep -Eq 'currentSong\.lyricsSourceMode\.readonly|歌词来源：' \
  "$ROOT/SpotifyLyrics/Views/Components/CurrentSongOperationsView.swift"

# No paid API surface
! grep -Eiq 'musixmatch|付费套餐|subscription.*lyrics' "$PROVIDERS" "$SETTINGS" || {
  echo "paid lyrics surface must not appear" >&2
  exit 1
}

# No kugou implementation in app sources
if grep -RIn --include='*.swift' -E 'Kugou|KuGou|kugou' "$ROOT/SpotifyLyrics" >/dev/null 2>&1; then
  echo "unexpected kugou symbols in SpotifyLyrics" >&2
  exit 1
fi

swiftc -parse-as-library \
  "$PROVIDERS" \
  "$ROOT/Tests/lyrics_source_mode_contract.swift" \
  -o "$TMP_DIR/lyrics_source_mode_contract"
"$TMP_DIR/lyrics_source_mode_contract"

echo "lyrics_source_mode_contract: PASS"

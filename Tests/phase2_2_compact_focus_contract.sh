#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SETTINGS="$ROOT/SpotifyLyrics/Settings/AppSettingsStore.swift"
V3="$ROOT/SpotifyLyrics/Views/MainWindow/AppleMusicImmersiveV3WindowView.swift"
MAIN="$ROOT/SpotifyLyrics/Views/MainWindow/MainLyricsWindowView.swift"

require() {
  local pattern="$1"
  local file="$2"
  grep -Eq "$pattern" "$file" || {
    echo "FAIL: missing /$pattern/ in $file" >&2
    exit 1
  }
}

require_in_block() {
  local pattern="$1"
  local block="$2"
  local label="$3"
  printf '%s\n' "$block" | grep -Eq "$pattern" || {
    echo "FAIL: missing $label /$pattern/ in compact lyrics focus layout" >&2
    exit 1
  }
}

# The setting is a single persisted AppSettingsStore property and remains
# conservative for existing users who do not have the key yet.
require 'public static let automaticCompactLyricsFocus = "general\.automaticCompactLyricsFocus"' "$SETTINGS"
require '@Published public var automaticCompactLyricsFocus: Bool' "$SETTINGS"
require 'automaticCompactLyricsFocus = defaults\.object\(forKey: Key\.automaticCompactLyricsFocus\) as\? Bool \?\? false' "$SETTINGS"
if [[ "$(grep -Ec 'public static let automaticCompactLyricsFocus' "$SETTINGS")" -ne 1 ]]; then
  echo 'FAIL: automatic compact focus must have exactly one AppSettingsStore key' >&2
  exit 1
fi
if [[ "$(grep -Ec '@Published public var automaticCompactLyricsFocus: Bool' "$SETTINGS")" -ne 1 ]]; then
  echo 'FAIL: automatic compact focus must have exactly one published AppSettingsStore property' >&2
  exit 1
fi

# Only V3 reads the automatic setting. MainLyricsWindowView passes the shared
# layout binding and environment through; the compact projection never writes
# the selected layout family.
require 'enum MainWindowResponsiveThresholds' "$V3"
require 'compactLyricsFocus\(in geometry: GeometryProxy\)' "$V3"
require 'isAutomaticCompactLyricsFocus\(in geometry: GeometryProxy\)' "$V3"
require 'private func compactLyricsFocusLayout\(in geometry: GeometryProxy\)' "$V3"
require '@EnvironmentObject private var settings: AppSettingsStore' "$V3"
require 'settings\.automaticCompactLyricsFocus' "$V3"
require 'if layoutStyle == \.appleMusicImmersiveV3' "$MAIN"
require 'layoutStyleRawValue: layoutStyleBinding' "$MAIN"
if grep -Eq 'automaticCompactLyricsFocus' "$MAIN" SpotifyLyrics/Views/MainWindow/ImmersiveSplitWindowView.swift SpotifyLyrics/Views/LyricsViews.swift; then
  echo 'FAIL: automatic compact focus must remain a V3-only projection' >&2
  exit 1
fi

compact_layout="$(sed -n '/^    private func compactLyricsFocusLayout(in geometry: GeometryProxy)/,/^    private func adaptiveSplitLayout/p' "$V3")"
if printf '%s\n' "$compact_layout" | grep -Eq '(mainWindow)?layoutStyleRawValue[[:space:]]*='; then
  echo 'FAIL: automatic compact focus must not mutate the selected layout family' >&2
  exit 1
fi
require_in_block 'lyricsColumn\(' "$compact_layout" 'lyricsColumn'
require_in_block 'AppleMusicImmersiveV3FocusTransportControls\(' "$compact_layout" 'minimal focus transport controls'
require_in_block 'searchButton' "$compact_layout" 'search access'
require_in_block 'preferencesButton' "$compact_layout" 'settings access'
if printf '%s\n' "$compact_layout" | grep -Eq 'providerStatusMenu|AppleMusicImmersiveV3TransportControls\('; then
  echo 'FAIL: compact lyrics focus must not expose the provider/tool-panel or full transport layout' >&2
  exit 1
fi
require 'Button\("重试 Spotify"\)' "$V3"

# The projection is a pure live-state view: no second timer, provider,
# playback/session controller, or resize-triggered task is introduced.
for file in "$V3" "$MAIN"; do
  if grep -Eq 'Timer\.scheduledTimer|DispatchSourceTimer|LyricsSessionController|TranslationSessionController|PlaybackProvider|PlaybackState\(|URLSession' "$file"; then
    echo "FAIL: compact focus added a second timer/provider/session path in $file" >&2
    exit 1
  fi
done
if printf '%s\n' "$compact_layout" | grep -Eq '\.task|\.onAppear|\.onChange'; then
  echo 'FAIL: compact focus layout must not attach resize-triggered lifecycle work' >&2
  exit 1
fi

# Manual Lyrics Focus is still a separate persisted layout branch, not the
# temporary V3 projection.
require 'case \.lyricsFocus:' "$MAIN"
require 'private var lyricsFocusLayout' "$MAIN"
require 'case \.appleMusicImmersiveV3:' "$MAIN"
# The V3 file may name its temporary projection compactLyricsFocusLayout; the
# prohibited coupling is an actual persisted MainWindowLayoutStyle case, not
# the projection's descriptive function name.
if grep -Eq 'case[[:space:]]+\\.lyricsFocus|MainWindowLayoutStyle\\.lyricsFocus' "$V3"; then
  echo 'FAIL: V3 automatic compact focus must remain distinct from manual Lyrics Focus' >&2
  exit 1
fi

echo "phase2.2 compact lyrics focus contract passed"

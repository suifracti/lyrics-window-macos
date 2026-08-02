#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
V3="$ROOT/SpotifyLyrics/Views/MainWindow/AppleMusicImmersiveV3WindowView.swift"
MANUAL="$ROOT/SpotifyLyrics/Views/Components/ManualLyricsActionsView.swift"

require() {
  local needle="$1"
  local file="$2"
  grep -Fq "$needle" "$file" || {
    echo "FAIL: missing '$needle' in $file" >&2
    exit 1
  }
}

focus_layout="$(sed -n '/^    private func compactLyricsFocusLayout(in geometry: GeometryProxy)/,/^    private func wideLayout/p' "$V3")"

# Lyrics Focus must expose only the weak search/settings group at the top;
# the provider/status menu belongs to the normal toolbar, not the reading view.
if printf '%s\n' "$focus_layout" | grep -Fq 'providerStatusMenu'; then
  echo 'FAIL: Lyrics Focus must not place provider status controls at top-left' >&2
  exit 1
fi
require 'searchButton' "$V3"
require 'preferencesButton' "$V3"

# Focus has a dedicated centered empty state and a compact playback projection;
# it must not reuse the full transport/tool-panel presentation.
require 'private var focusEmptyState: some View' "$V3"
require 'AppleMusicImmersiveV3FocusTransportControls' "$V3"
if printf '%s\n' "$focus_layout" | grep -Fq 'AppleMusicImmersiveV3TransportControls('; then
  echo 'FAIL: Lyrics Focus must not use the full transport controls' >&2
  exit 1
fi
require 'lyricsFocus: true' "$V3"
require 'onSearch:' "$V3"

# Low-frequency recovery actions remain in one compact menu rather than four
# persistent text buttons, while the menu can use a short focus label.
require 'compactLabel' "$MANUAL"
require 'compactLabel: "导入"' "$V3"

echo "phase2.3 lyrics focus contract: PASS"

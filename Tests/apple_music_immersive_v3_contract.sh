#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

WINDOW="SpotifyLyrics/Views/MainWindow/AppleMusicImmersiveV3WindowView.swift"
BACKDROP="SpotifyLyrics/Views/Components/AppleMusicImmersiveV3BackdropView.swift"
STYLE="SpotifyLyrics/Design/MainWindowLayoutStyle.swift"
MAIN="SpotifyLyrics/Views/MainWindow/MainLyricsWindowView.swift"
SETTINGS="SpotifyLyrics/Settings/AppSettingsStore.swift"

for file in "$WINDOW" "$BACKDROP" "$STYLE" "$MAIN" "$SETTINGS"; do
  test -f "$file" || { echo "missing V3 file: $file" >&2; exit 1; }
done

grep -q 'case appleMusicImmersiveV3' "$STYLE"
grep -q 'AppleMusicImmersiveV3WindowView' "$MAIN"
grep -q 'AppleMusicImmersiveV3WindowView.swift' SpotifyLyrics.xcodeproj/project.pbxproj
grep -q 'AppleMusicImmersiveV3BackdropView.swift' SpotifyLyrics.xcodeproj/project.pbxproj

# Responsive V3 remains one canvas with dynamic track/lyrics columns.
grep -q 'let leftRatio = 0.45 \* scale' "$WINDOW"
grep -q 'let rightWidth = max(1, contentWidth - leftWidth - columnGap)' "$WINDOW"
grep -q 'technicalMinimumSize = LyricsDesignTokens.technicalMinimumMainWindowSize' "$WINDOW"
grep -q 'comfortableMinimumSize = LyricsDesignTokens.comfortableMainWindowSize' "$WINDOW"
grep -q 'wideBreakpoint: CGFloat = 1_080' "$WINDOW"
grep -q 'onContinuousHover' "$WINDOW"

# Lyrics use token-aligned ruby, safe seeking, and current-line scrolling.
grep -q 'RubyLineView' "$WINDOW"
grep -q 'LyricsTimeline.validSeekTimestamp' "$WINDOW"
grep -q 'scrollTo(id, anchor: UnitPoint(x: 0.5, y: 0.47))' "$WINDOW"
! grep -q 'LyricsCanvasView' "$WINDOW"
grep -q 'shouldShowRuby' "$WINDOW"
grep -q 'distance <= 1' "$WINDOW"

# Backdrop work remains track-bound/cached and exposes three real renderers.
grep -q 'task(id: requestKey)' "$BACKDROP"
grep -q 'Task.detached(priority: .utility)' "$BACKDROP"
grep -q 'noiseData' "$BACKDROP"
grep -q 'maxPixel: 640' "$BACKDROP"
grep -q 'maxPixel: 48' "$BACKDROP"
grep -q 'switch settings.v3ArtworkPresentation' "$BACKDROP"
grep -q 'ambientArtworkLayers' "$BACKDROP"
grep -q 'stageArtworkLayers' "$BACKDROP"
grep -q 'legacyArtworkLayers' "$BACKDROP"

# Stage removes the duplicate foreground card and the choice is persistent.
grep -q 'showsForegroundArtwork' "$WINDOW"
grep -q 'Picker("背景构图"' "$WINDOW"
grep -q 'v3ArtworkPresentationRawValue' "$SETTINGS"

grep -q '.defaultSize(width: 1152, height: 720)' SpotifyLyrics/Main.swift

echo "Apple Music immersive V3 contract passed"

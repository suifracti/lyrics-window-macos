#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root_dir"

window_file="SpotifyLyrics/Views/MainWindow/AppleMusicImmersiveV3WindowView.swift"
backdrop_file="SpotifyLyrics/Views/Components/AppleMusicImmersiveV3BackdropView.swift"
style_file="SpotifyLyrics/Design/MainWindowLayoutStyle.swift"
main_file="SpotifyLyrics/Views/MainWindow/MainLyricsWindowView.swift"

for file in "$window_file" "$backdrop_file" "$style_file" "$main_file"; do
  test -f "$file" || { echo "missing V3 file: $file" >&2; exit 1; }
done

grep -q 'case appleMusicImmersiveV3' "$style_file"
grep -q 'AppleMusicImmersiveV3WindowView' "$main_file"
grep -q 'AppleMusicImmersiveV3WindowView.swift' SpotifyLyrics.xcodeproj/project.pbxproj
grep -q 'AppleMusicImmersiveV3BackdropView.swift' SpotifyLyrics.xcodeproj/project.pbxproj

grep -q 'contentWidth \* 0.45' "$window_file"
grep -q 'contentWidth \* 0.55' "$window_file"
grep -q 'technicalMinimumSize = LyricsDesignTokens.technicalMinimumMainWindowSize' "$window_file"
grep -q 'comfortableMinimumSize = LyricsDesignTokens.comfortableMainWindowSize' "$window_file"
grep -q 'wideBreakpoint: CGFloat = 1_080' "$window_file"
grep -q 'onContinuousHover' "$window_file"
grep -q 'RubyLineView' "$window_file"
grep -q 'LyricsTimeline.validSeekTimestamp' "$window_file"
grep -q 'scrollTo(id, anchor: UnitPoint(x: 0.5, y: 0.47))' "$window_file"
# V3 must not reuse the V2 status panel or its fake-current-line behavior.
! grep -q 'LyricsCanvasView' "$window_file"
grep -q 'distance > 1' "$window_file"
grep -q 'distance == 1 ? 0' "$window_file"

grep -q 'task(id: requestKey)' "$backdrop_file"
grep -q 'Task.detached(priority: .utility)' "$backdrop_file"
grep -q 'noiseData' "$backdrop_file"
grep -q 'maxPixel: 320' "$backdrop_file"
grep -q 'UnitPoint(x: 0.16, y: 0.52)' "$backdrop_file"
# Background parameters live in the semantic presentation style rather than
# being duplicated as view literals. Keep the original V3 calibration values
# as contract data while allowing the renderer to select a preset.
grep -q 'artworkScreenBlur: 24' SpotifyLyrics/Design/BackdropPalette.swift
grep -q 'artworkBlur: 72' SpotifyLyrics/Design/BackdropPalette.swift
grep -q 'artworkScreenOpacity: 0.62' SpotifyLyrics/Design/BackdropPalette.swift
grep -q 'artworkOpacity: 0.72' SpotifyLyrics/Design/BackdropPalette.swift
grep -q 'glowIntensity: LyricsDesignTokens.Backdrop.glowIntensity' SpotifyLyrics/Design/BackdropPalette.swift
grep -q 'lyricVeilMultiplier: LyricsDesignTokens.Backdrop.lyricVeilMultiplier' SpotifyLyrics/Design/BackdropPalette.swift

# Visual calibration guardrails: keep the cover readable, keep ruby subordinate,
# and make the unsynchronised path a plain reading surface rather than a fake
# timeline.
grep -q 'cornerRadiusRatio: 0.04' "$window_file"
grep -q 'font(.system(size: 22, weight: .semibold))' "$window_file"
grep -q 'frame(width: 40, height: 40)' "$window_file"
grep -q 'font(.system(size: 20, weight: .semibold))' "$window_file"
grep -q 'frame(width: 40, height: 40)' "$window_file"
grep -q 'let verticalPadding = synchronized' "$window_file"
grep -q ': 28.0' "$window_file"
# Ruby size is scaled by the shared display preference while keeping the
# same subordinate base ratio.
grep -q 'baseSize \* 0.34' "$window_file"
grep -q 'min(compact ? 16 : 18' "$window_file"
grep -q 'rubyColor: .white.opacity(rubyOpacity)' "$window_file"
grep -q 'rubySpacing: 1' "$window_file"
grep -q 'tokenVerticalSpacing: 3' "$window_file"
grep -q 'case 1: return 0.44' "$window_file"
grep -q 'case 2: return 0.24' "$window_file"
grep -q 'case 2: return 1.1' "$window_file"
grep -q 'min(2.0' "$window_file"
grep -q 'shouldShowRuby' "$window_file"
grep -q 'shouldShowRomaji' "$window_file"
grep -q 'distance <= 1' "$window_file"
grep -q 'HStack(spacing: LyricsDesignTokens.Spacing.md + 2)' "$window_file"
grep -q 'frame(width: 44, height: 44)' "$window_file"
grep -q 'frame(width: 40, height: 40)' "$window_file"

# V3 keeps the cached 320px artwork but exposes a second, lower-radius texture
# layer so the cover does not collapse into a single theme-color wash.
grep -q 'blur(radius: style.artworkScreenBlur)' "$backdrop_file"
grep -q 'blendMode(.screen)' "$backdrop_file"
grep -q 'style.artworkScreenOpacity' "$backdrop_file"

grep -q '.defaultSize(width: 1152, height: 720)' SpotifyLyrics/Main.swift

echo "Apple Music immersive V3 contract passed"

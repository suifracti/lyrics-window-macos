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
grep -q 'minimumWidth: CGFloat = 800' "$window_file"
grep -q 'minimumHeight: CGFloat = 600' "$window_file"
grep -q 'wideBreakpoint: CGFloat = 1_080' "$window_file"
grep -q 'onContinuousHover' "$window_file"
grep -q 'RubyLineView' "$window_file"
grep -q 'LyricsTimeline.validSeekTimestamp' "$window_file"
grep -q 'scrollTo(id, anchor: .center)' "$window_file"
# V3 must not reuse the V2 status panel or its fake-current-line behavior.
! grep -q 'LyricsCanvasView' "$window_file"
grep -q 'distance > 1' "$window_file"
grep -q 'distance == 1 ? 0' "$window_file"

grep -q 'task(id: requestKey)' "$backdrop_file"
grep -q 'Task.detached(priority: .utility)' "$backdrop_file"
grep -q 'blur(radius: 120)' "$backdrop_file"
grep -q 'noiseData' "$backdrop_file"
grep -q 'maxPixel: 320' "$backdrop_file"

grep -q '.defaultSize(width: 1152, height: 720)' SpotifyLyrics/Main.swift

echo "Apple Music immersive V3 contract passed"

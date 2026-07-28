#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LINE="$ROOT/SpotifyLyrics/Views/Components/LyricLineView.swift"
LEGACY="$ROOT/SpotifyLyrics/Views/LyricsViews.swift"
V3="$ROOT/SpotifyLyrics/Views/MainWindow/AppleMusicImmersiveV3WindowView.swift"
MAIN="$ROOT/SpotifyLyrics/Views/MainWindow/MainLyricsWindowView.swift"
CANVAS="$ROOT/SpotifyLyrics/Views/Components/LyricsCanvasView.swift"
ROMANIZER="$ROOT/SpotifyLyrics/Lyrics/JapaneseRomanizer.swift"

require() {
  local file="$1"
  local pattern="$2"
  local label="$3"
  grep -Eq "$pattern" "$file" || {
    echo "FAIL: $label ($file does not contain /$pattern/)" >&2
    exit 1
  }
}

# Ruby must normalize provider readings for display and expose enough width for
# a long reading; it must never be clipped at the left edge of a lyric row.
require "$ROMANIZER" 'displayKana' 'hiragana display normalization helper'
require "$LINE" 'contentWidth' 'ruby layout width includes reading overhang'
require "$LINE" 'baseX' 'ruby base text is centered inside the expanded block'
require "$LINE" 'displayKana' 'ruby and kana-primary views normalize display text'
require "$LINE" 'distinctRomaji' 'legacy lyric rows suppress duplicated kana romaji'
require "$LINE" 'displayRubyText' 'katakana tokens expose hiragana ruby'
require "$LEGACY" 'displayKana' 'floating and full-screen rows normalize kana display'
require "$LEGACY" 'distinctRomaji' 'floating and full-screen rows suppress duplicated romaji'

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/lyrics-display-contract.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT
cat > "$TMP_DIR/main.swift" <<'SWIFT'
import Foundation

@main
struct DisplayKanaContract {
    static func main() {
        precondition(JapaneseRomanizer.displayKana("ココロ SNS １２３") == "こころ SNS １２３")
        precondition(JapaneseRomanizer.displayKana("LOVE / Bad day") == "LOVE / Bad day")
        print("display kana behavior passed")
    }
}
SWIFT
swiftc -parse-as-library "$ROMANIZER" "$TMP_DIR/main.swift" -o "$TMP_DIR/display-kana-contract"
"$TMP_DIR/display-kana-contract"

# V3 must honor all three independent modes instead of always rendering Ruby.
require "$V3" 'kanaDisplayMode' 'V3 consumes the selected kana mode'
require "$V3" 'independentLine' 'V3 independent kana line'
require "$V3" 'inlineRuby' 'V3 inline Ruby mode'
require "$V3" 'kanaReplacement' 'V3 kana replacement mode'
require "$V3" 'inlineRubyTokens' 'V3 inline Ruby fallback preserves kana without tokens'
require "$V3" 'shouldRenderInlineRuby' 'V3 only uses inline Ruby for readable Japanese surfaces'

# A single AppStorage binding owns layout selection so switching into/out of V3
# cannot be reset by a second view-local default value.
require "$MAIN" 'layoutStyleRawValue: \$layoutStyleRawValue' 'V3 receives the shared layout binding'
! grep -q '@AppStorage("mainWindowLayoutStyle")' "$V3"

# Legacy/focus scrolling derives the active line from the published playback
# clock, rather than observing a computed property that SwiftUI may not track.
require "$CANVAS" 'onChange\(of: state\.currentTime\)' 'focus mode observes playback time'
require "$CANVAS" 'lastScrolledLineIndex' 'focus mode de-duplicates line scrolls'

echo "lyrics display regression contract passed"

#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

swiftc \
  "$ROOT/SpotifyLyrics/Lyrics/LyricsLanguageGate.swift" \
  "$ROOT/Tests/phase2_1_language_gate_contract.swift" \
  -o "$ROOT/.phase2_1_language_gate_contract"
"$ROOT/.phase2_1_language_gate_contract"
rm -f "$ROOT/.phase2_1_language_gate_contract"

require() {
  local file="$1"
  local pattern="$2"
  if ! grep -Fq "$pattern" "$ROOT/$file"; then
    echo "FAIL: $file is missing: $pattern" >&2
    exit 1
  fi
}

require "SpotifyLyrics/Lyrics/LyricsModels.swift" "case noSelection(TrackIdentity)"
require "SpotifyLyrics/Services/LyricsSessionController.swift" "public private(set) var isNoSelection"
require "SpotifyLyrics/Services/LyricsSessionController.swift" "func selectNoVersion"
require "SpotifyLyrics/Services/TranslationSessionController.swift" "func selectNone"
require "SpotifyLyrics/Services/TranslationSessionController.swift" "manualNoSelection"
require "SpotifyLyrics/Services/PlaybackState.swift" "liveLyricsLanguage"
require "SpotifyLyrics/Services/PlaybackState.swift" "selectNoLyricsVersion"
require "SpotifyLyrics/Services/PlaybackState.swift" "selectNoTranslationVersion"
require "SpotifyLyrics/Views/Components/LyricsCanvasView.swift" "state.liveLyrics"
require "SpotifyLyrics/Views/MainWindow/AppleMusicImmersiveV3WindowView.swift" "state.liveLyrics"
require "SpotifyLyrics/Views/Components/LyricLineView.swift" "LyricsLanguageGate"
require "SpotifyLyrics/Views/MainWindow/AppleMusicImmersiveV3WindowView.swift" "language: state.liveLyricsLanguage"
require "SpotifyLyrics/Models/Models.swift" "TrackArtistLink"
require "SpotifyLyrics/Search/TrackSearchModels.swift" "albumURI"
require "SpotifyLyrics/Spotify/SpotifyAPIModels.swift" "let uri: String?"
require "SpotifyLyrics/Views/Components/SongSearchPopover.swift" "spotifyAuthorizationManager.authorize()"
require "SpotifyLyrics/Views/Components/TrackMetadataView.swift" "NSWorkspace.shared.open"
require "SpotifyLyrics/Services/TranslationSessionController.swift" "if isNoSelection"
require "SpotifyLyrics/Services/PlaybackState.swift" "translationSelectionIsEmpty"
require "SpotifyLyrics/Views/Components/LyricsCanvasView.swift" "Menu(\"歌词版本\")"
require "SpotifyLyrics/Views/Components/LyricLineView.swift" "preferences.showTranslation"
for file in \
  SpotifyLyrics/Views/Floating/FloatingLyricsView.swift \
  SpotifyLyrics/Views/Capsule/CapsuleLyricsView.swift \
  SpotifyLyrics/Views/Fullscreen/FullScreenLyricsView.swift; do
  require "$file" "state.liveLyrics"
  if grep -Fq "state.lyrics" "$ROOT/$file"; then
    echo "FAIL: auxiliary live view still reads preview-capable state: $file" >&2
    exit 1
  fi
done

if grep -Fq "state.lyricsState" "$ROOT/SpotifyLyrics/Views/MainWindow/AppleMusicImmersiveV3WindowView.swift"; then
  echo "FAIL: V3 formal view still reads preview-capable lyricsState" >&2
  exit 1
fi
if grep -Fq "state.lyricsState" "$ROOT/SpotifyLyrics/Views/Components/LyricsCanvasView.swift"; then
  echo "FAIL: lyrics focus formal view still reads preview-capable lyricsState" >&2
  exit 1
fi

echo "phase2_1_contract: PASS"

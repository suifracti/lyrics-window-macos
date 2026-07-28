#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCES=(
  "$ROOT_DIR/SpotifyLyrics/Models/Models.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/TrackIdentity.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LyricsModels.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/AlignmentModels.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LRCParser.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LyricsMatcher.swift"
  "$ROOT_DIR/Tests/lyrics_core_test.swift"
)

for source in "${SOURCES[@]}"; do
  if [[ ! -f "$source" ]]; then
    echo "missing production/test source: $source" >&2
    exit 1
  fi
done

TMP_DIR="$(mktemp -d)"
trap 'rm -f "$TMP_DIR"/* 2>/dev/null; rmdir "$TMP_DIR" 2>/dev/null || true' EXIT

cp "$ROOT_DIR/Tests/lyrics_core_test.swift" "$TMP_DIR/main.swift"
COMPILE_SOURCES=(
  "$ROOT_DIR/SpotifyLyrics/Models/Models.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/TrackIdentity.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LyricsModels.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/AlignmentModels.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LRCParser.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LyricsMatcher.swift"
  "$TMP_DIR/main.swift"
)
swiftc "${COMPILE_SOURCES[@]}" -o "$TMP_DIR/lyrics-core-contract"
"$TMP_DIR/lyrics-core-contract"

required_sources=(
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LocalLyricsProvider.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LRCLIBLyricsProvider.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/CompositeLyricsProvider.swift"
)
for source in "${required_sources[@]}"; do
  if [[ ! -f "$source" ]]; then
    echo "missing required slice source: $source" >&2
    exit 1
  fi
done

cp "$ROOT_DIR/Tests/local_provider_test.swift" "$TMP_DIR/LocalProviderMain.swift"
LOCAL_SOURCES=(
  "$ROOT_DIR/SpotifyLyrics/Models/Models.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/TrackIdentity.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LyricsModels.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/AlignmentModels.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LRCParser.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LyricsMatcher.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/TrackAlias.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/TrackMetadata.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/TrackTextNormalizer.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/JapaneseRomanizer.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/JapaneseReadingPipeline.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/JapaneseKanaGenerator.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LyricsQueryPlanner.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LyricsSafeMatcher.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LyricsRecoveryModels.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LyricsE2ELog.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/AlignmentService.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/AudioPCMConverter.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LineForcedAligner.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/SpeechForcedAlignmentService.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LocalAlignedLyricsStore.swift"
  "$ROOT_DIR/SpotifyLyrics/Search/LocalLyricsIndex.swift"
  "$ROOT_DIR/SpotifyLyrics/Search/SongSearchModels.swift"
  "$ROOT_DIR/SpotifyLyrics/Search/TrackSearchModels.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LocalLyricsProvider.swift"
  "$TMP_DIR/LocalProviderMain.swift"
)
swiftc -parse-as-library "${LOCAL_SOURCES[@]}" -o "$TMP_DIR/local-provider-contract"
"$TMP_DIR/local-provider-contract"

cp "$ROOT_DIR/Tests/lrclib_provider_test.swift" "$TMP_DIR/LRCLIBProviderMain.swift"
LRCLIB_SOURCES=(
  "$ROOT_DIR/SpotifyLyrics/Models/Models.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/TrackIdentity.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LyricsModels.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/AlignmentModels.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LRCParser.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LyricsMatcher.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/TrackAlias.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/TrackMetadata.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/TrackTextNormalizer.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/JapaneseRomanizer.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/JapaneseReadingPipeline.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/JapaneseKanaGenerator.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LyricsQueryPlanner.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LyricsSafeMatcher.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LyricsRecoveryModels.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LyricsE2ELog.swift"
  "$ROOT_DIR/SpotifyLyrics/Search/LocalLyricsIndex.swift"
  "$ROOT_DIR/SpotifyLyrics/Search/SongSearchModels.swift"
  "$ROOT_DIR/SpotifyLyrics/Search/TrackSearchModels.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LocalLyricsProvider.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LRCLIBLyricsProvider.swift"
  "$ROOT_DIR/SpotifyLyrics/Providers/NetEaseExperimentalLyricsProvider.swift"
  "$ROOT_DIR/SpotifyLyrics/Providers/QQExperimentalLyricsProvider.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LocalAudioASRService.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LyricsSearchManager.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/CompositeLyricsProvider.swift"
  "$TMP_DIR/LRCLIBProviderMain.swift"
)
swiftc -parse-as-library "${LRCLIB_SOURCES[@]}" -o "$TMP_DIR/lrclib-provider-contract"
"$TMP_DIR/lrclib-provider-contract"

cp "$ROOT_DIR/Tests/lyrics_session_test.swift" "$TMP_DIR/LyricsSessionMain.swift"
SESSION_SOURCES=(
  "$ROOT_DIR/SpotifyLyrics/Models/Models.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/TrackIdentity.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LyricsModels.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/AlignmentModels.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LRCParser.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LyricsMatcher.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/TrackAlias.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/TrackMetadata.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/TrackTextNormalizer.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/JapaneseRomanizer.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/JapaneseReadingPipeline.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/JapaneseKanaGenerator.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LyricsQueryPlanner.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LyricsSafeMatcher.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LyricsRecoveryModels.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LyricsE2ELog.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LyricsSearchManager.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/CompositeLyricsProvider.swift"
  "$ROOT_DIR/SpotifyLyrics/Services/LyricsSessionController.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LocalAlignedLyricsStore.swift"
  "$ROOT_DIR/SpotifyLyrics/Search/LocalLyricsIndex.swift"
  "$ROOT_DIR/SpotifyLyrics/Search/SongSearchModels.swift"
  "$ROOT_DIR/SpotifyLyrics/Search/TrackSearchModels.swift"
  "$TMP_DIR/LyricsSessionMain.swift"
)
swiftc -parse-as-library "${SESSION_SOURCES[@]}" -o "$TMP_DIR/lyrics-session-contract"
"$TMP_DIR/lyrics-session-contract"

cp "$ROOT_DIR/Tests/lyrics_correctness_test.swift" "$TMP_DIR/LyricsCorrectnessMain.swift"
CORRECTNESS_SOURCES=(
  "$ROOT_DIR/SpotifyLyrics/Models/Models.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/TrackIdentity.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LyricsModels.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/AlignmentModels.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LRCParser.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LyricsMatcher.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/TrackAlias.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/TrackMetadata.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/TrackTextNormalizer.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/JapaneseRomanizer.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/JapaneseReadingPipeline.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/JapaneseKanaGenerator.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LyricsQueryPlanner.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LyricsSafeMatcher.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LyricsRecoveryModels.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LyricsE2ELog.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LRCLIBLyricsProvider.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LyricsSearchManager.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/CompositeLyricsProvider.swift"
  "$ROOT_DIR/SpotifyLyrics/Services/LyricsSessionController.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LocalAlignedLyricsStore.swift"
  "$ROOT_DIR/SpotifyLyrics/Search/LocalLyricsIndex.swift"
  "$ROOT_DIR/SpotifyLyrics/Search/SongSearchModels.swift"
  "$ROOT_DIR/SpotifyLyrics/Search/TrackSearchModels.swift"
  "$TMP_DIR/LyricsCorrectnessMain.swift"
)
swiftc -parse-as-library "${CORRECTNESS_SOURCES[@]}" -o "$TMP_DIR/lyrics-correctness-contract"
"$TMP_DIR/lyrics-correctness-contract"

cp "$ROOT_DIR/Tests/playback_state_contract.swift" "$TMP_DIR/PlaybackStateMain.swift"
PLAYBACK_SOURCES=(
  "$ROOT_DIR/SpotifyLyrics/Models/Models.swift"
  "$ROOT_DIR/SpotifyLyrics/Services/MockData.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/TrackIdentity.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LyricsModels.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/AlignmentModels.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LRCParser.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LyricsMatcher.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/TrackAlias.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/TrackMetadata.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/TrackTextNormalizer.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/JapaneseRomanizer.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/JapaneseReadingPipeline.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/JapaneseKanaGenerator.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LyricsQueryPlanner.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LyricsSafeMatcher.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LyricsRecoveryModels.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LyricsE2ELog.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/AlignmentService.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/AudioPCMConverter.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LineForcedAligner.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/SpeechForcedAlignmentService.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LocalAlignedLyricsStore.swift"
  "$ROOT_DIR/SpotifyLyrics/Search/LocalLyricsIndex.swift"
  "$ROOT_DIR/SpotifyLyrics/Search/TrackSearchModels.swift"
  "$ROOT_DIR/SpotifyLyrics/Search/TrackSearchProvider.swift"
  "$ROOT_DIR/SpotifyLyrics/Search/TrackSearchManager.swift"
  "$ROOT_DIR/SpotifyLyrics/Search/CurrentTrackResolver.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LocalLyricsProvider.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LRCLIBLyricsProvider.swift"
  "$ROOT_DIR/SpotifyLyrics/Providers/NetEaseExperimentalLyricsProvider.swift"
  "$ROOT_DIR/SpotifyLyrics/Providers/QQExperimentalLyricsProvider.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LocalAudioASRService.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/LyricsSearchManager.swift"
  "$ROOT_DIR/SpotifyLyrics/Lyrics/CompositeLyricsProvider.swift"
  "$ROOT_DIR/SpotifyLyrics/Services/LyricsSessionController.swift"
  "$ROOT_DIR/SpotifyLyrics/Providers/PlaybackProvider.swift"
  "$ROOT_DIR/SpotifyLyrics/Providers/SpotifyDesktopProvider.swift"
  "$ROOT_DIR/SpotifyLyrics/Search/SongSearchModels.swift"
  "$ROOT_DIR/SpotifyLyrics/Search/SongSearchProvider.swift"
  "$ROOT_DIR/SpotifyLyrics/Search/LocalSearchProvider.swift"
  "$ROOT_DIR/SpotifyLyrics/Search/SpotifyCurrentTrackProvider.swift"
  "$ROOT_DIR/SpotifyLyrics/Search/LRCLIBProvider.swift"
  "$ROOT_DIR/SpotifyLyrics/Search/SongSearchManager.swift"
  "$ROOT_DIR/SpotifyLyrics/Services/PlaybackState.swift"
  "$TMP_DIR/PlaybackStateMain.swift"
)
swiftc -parse-as-library -framework AppKit -framework Network -framework AVFoundation -framework Speech -framework CoreMedia "${PLAYBACK_SOURCES[@]}" -o "$TMP_DIR/playback-state-contract"
"$TMP_DIR/playback-state-contract"

cp "$ROOT_DIR/Tests/backdrop_palette_test.swift" "$TMP_DIR/BackdropPaletteMain.swift"
PALETTE_SOURCES=(
  "$ROOT_DIR/SpotifyLyrics/Design/BackdropPalette.swift"
  "$TMP_DIR/BackdropPaletteMain.swift"
)
swiftc -parse-as-library -framework AppKit "${PALETTE_SOURCES[@]}" -o "$TMP_DIR/backdrop-palette-contract"
"$TMP_DIR/backdrop-palette-contract"

ui_sources=(
  "$ROOT_DIR/SpotifyLyrics/Services/LyricsSessionController.swift"
  "$ROOT_DIR/SpotifyLyrics/Views/Components/TrackBackdropView.swift"
  "$ROOT_DIR/SpotifyLyrics/Design/BackdropPalette.swift"
)
for source in "${ui_sources[@]}"; do
  if [[ ! -f "$source" ]]; then
    echo "missing required UI slice source: $source" >&2
    exit 1
  fi
done

rg -q 'Mock Preview|enterMockPreview|exitMockPreview' "$ROOT_DIR/SpotifyLyrics/Services/PlaybackState.swift"
rg -q '暂未找到歌词|LyricsLoadState|loading|candidates|failed' "$ROOT_DIR/SpotifyLyrics/Views/Components/LyricsCanvasView.swift"
rg -q 'https://lrclib.net/api|syncedLyrics|plainLyrics' "$ROOT_DIR/SpotifyLyrics/Lyrics/LRCLIBLyricsProvider.swift"
rg -q 'Music/SpotifyLyrics/Lyrics|Application Support/SpotifyLyrics/Lyrics' "$ROOT_DIR/SpotifyLyrics/Lyrics/LocalLyricsProvider.swift" "$ROOT_DIR/SpotifyLyrics/Search/LocalLyricsIndex.swift"
rg -q 'Task.isCancelled|TrackIdentity|artwork' "$ROOT_DIR/SpotifyLyrics/Views/Components/TrackBackdropView.swift"
rg -q 'PlainLyricsListView|!state.lyricsAreSynchronized' "$ROOT_DIR/SpotifyLyrics/Views/LyricsViews.swift"
rg -q 'validSeekTimestamp' "$ROOT_DIR/SpotifyLyrics/Lyrics/LyricsModels.swift"
rg -q 'source: "lyric-line"' "$ROOT_DIR/SpotifyLyrics/Views/Components/LyricsCanvasView.swift"
if rg -q 'state\.seek\(to: line\.timestamp' "$ROOT_DIR/SpotifyLyrics"; then
  echo "unvalidated lyric timestamp seek source remains" >&2
  exit 1
fi
rg -q 'retryAfterNetworkRecovery' "$ROOT_DIR/SpotifyLyrics/Services/LyricsSessionController.swift"
rg -q 'NWPathMonitor|network-recovery' "$ROOT_DIR/SpotifyLyrics/Services/PlaybackState.swift"

echo "real track lyrics contract passed"

#!/usr/bin/env bash
# Build offline S2 full-pipeline harness (DEBUG sources, no App UI, no SQLite).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${1:-$ROOT/Tools/s2_full_pipeline/.build/s2_full_pipeline}"
mkdir -p "$(dirname "$OUT")"

SDK="$(xcrun --sdk macosx --show-sdk-path)"
swiftc -parse-as-library -O -DDEBUG \
  -sdk "$SDK" \
  -target arm64-apple-macos14.0 \
  -framework Foundation -framework AVFoundation -framework Speech -framework CoreMedia \
  \
  "$ROOT/SpotifyLyrics/Models/Models.swift" \
  "$ROOT/SpotifyLyrics/Lyrics/TrackIdentity.swift" \
  "$ROOT/SpotifyLyrics/Lyrics/LyricsModels.swift" \
  "$ROOT/SpotifyLyrics/Lyrics/AlignmentModels.swift" \
  "$ROOT/SpotifyLyrics/Lyrics/JapaneseRomanizer.swift" \
  "$ROOT/SpotifyLyrics/Lyrics/LyricsLanguageGate.swift" \
  "$ROOT/SpotifyLyrics/Lyrics/TimedTranscript.swift" \
  "$ROOT/SpotifyLyrics/Lyrics/LineForcedAligner.swift" \
  "$ROOT/Tools/s2_full_pipeline/SpeechTimedTranscriptProvider.swift" \
  \
  "$ROOT/SpotifyLyrics/Capture/CaptureContinuityPolicy.swift" \
  "$ROOT/SpotifyLyrics/Capture/CapturedAudioModels.swift" \
  "$ROOT/SpotifyLyrics/Capture/PartialAlignmentModels.swift" \
  "$ROOT/SpotifyLyrics/Capture/AlignmentLocaleRecommender.swift" \
  "$ROOT/SpotifyLyrics/Capture/AlignmentAnchor.swift" \
  "$ROOT/SpotifyLyrics/Capture/AnchorAlignmentPolicy.swift" \
  "$ROOT/SpotifyLyrics/Capture/AnchorConstrainedAligner.swift" \
  "$ROOT/SpotifyLyrics/Capture/AssistedAlignmentDraft.swift" \
  "$ROOT/SpotifyLyrics/Capture/AssistedCandidateMerger.swift" \
  "$ROOT/SpotifyLyrics/Capture/SpeechEngine.swift" \
  "$ROOT/SpotifyLyrics/Capture/AppleSpeechEngine.swift" \
  "$ROOT/SpotifyLyrics/Capture/WhisperCLISpeechEngine.swift" \
  "$ROOT/SpotifyLyrics/Capture/SegmentPartialAlignmentPipeline.swift" \
  \
  "$ROOT/Tools/s2_full_pipeline/SCKSpikeLogStub.swift" \
  "$ROOT/Tools/s2_full_pipeline/main.swift" \
  -o "$OUT"

echo "built $OUT"

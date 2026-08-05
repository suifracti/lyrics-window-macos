#!/usr/bin/env bash
# Capture/alignment product sources compile without whole-file #if DEBUG.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CAP="$ROOT/SpotifyLyrics/Capture"
# Core product files must not be wrapped as whole-file DEBUG
for f in CapturedAudioModels.swift LiveCaptureCoordinator.swift SpeechEngine.swift \
         WhisperCLISpeechEngine.swift AppleSpeechEngine.swift SegmentPartialAlignmentPipeline.swift \
         AssistedCandidateMerger.swift AutomaticAlignmentJobController.swift \
         AutomaticAlignmentQualityGate.swift AutomaticAlignmentProgressStore.swift; do
  path="$CAP/$f"
  test -f "$path"
  # First non-empty non-comment line should not be #if DEBUG only wrapping whole file
  first=$(grep -vE '^\s*$|^\s*//' "$path" | head -1 || true)
  if [[ "$first" == "#if DEBUG" ]]; then
    echo "$f must not be whole-file #if DEBUG" >&2
    exit 1
  fi
done
# Settings UI product toggle
grep -Eq '自动为未排轴歌词生成时间轴' "$ROOT/SpotifyLyrics/Views/Settings/SettingsRootView.swift"
grep -Eq 'automaticAlignment\.enabled\.v1' "$ROOT/SpotifyLyrics/Settings/AppSettingsStore.swift"
# Product UI status vocabulary (no Whisper/S3 jargon)
OPS="$ROOT/SpotifyLyrics/Views/Components/CurrentSongOperationsView.swift"
grep -Eq '正在生成时间轴|已保存部分进度|等待继续播放|引擎尚未准备好' "$OPS"
if grep -Eq 'Whisper|ggml|S3A|S3B|CapturedSegment|confidence' "$OPS" | grep -v '//' | grep -Eq 'Whisper|ggml|S3A'; then
  echo "product UI must not expose engine jargon" >&2
  exit 1
fi
echo "automatic_alignment_product_path_contract: PASS"

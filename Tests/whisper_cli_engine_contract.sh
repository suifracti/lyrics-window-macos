#!/usr/bin/env bash
# Phase 2.11C-S1: WhisperCLISpeechEngine experimental DEBUG path
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WHISPER="$ROOT/SpotifyLyrics/Capture/WhisperCLISpeechEngine.swift"
ENGINE="$ROOT/SpotifyLyrics/Capture/SpeechEngine.swift"
PB="$ROOT/SpotifyLyrics/Services/PlaybackState.swift"
SHEET="$ROOT/SpotifyLyrics/Views/Components/AssistExplainSheet.swift"

test -f "$WHISPER"
grep -Eq 'struct WhisperCLISpeechEngine: LyricsSpeechEngine' "$WHISPER"
grep -Eq 'speechEngine\.whisperCLI\.experimental\.v1' "$ENGINE"
grep -Eq 'SPOTIFYLYRICS_WHISPER_CLI|SPOTIFYLYRICS_WHISPER_MODEL' "$WHISPER"
grep -Eq 'isAvailable|SpeechEngineError\.unavailable' "$WHISPER"
grep -Eq 'parseWhisperJSON|normalizeLanguage' "$WHISPER"
grep -Eq 'terminate|timeout|SpeechEngineError\.timeout|SpeechEngineError\.cancelled' "$WHISPER"
# Must not auto-download models or embed bundle paths for 466MB weights
if grep -Eiq 'URLSession|download|Bundle\.main.*ggml|ggml-small\.bin\"' "$WHISPER"; then
  # allow default *candidate* path under home, but not Bundle.main
  if grep -Eq 'Bundle\.main' "$WHISPER"; then
    echo "Whisper must not load model from App Bundle" >&2
    exit 1
  fi
fi
if grep -Eiq 'URLSession\(|downloadTask|curl |wget ' "$WHISPER"; then
  echo "Whisper must not auto-download models" >&2
  exit 1
fi
# No product UI surface for whisper/ggml/cli
if grep -Eiq 'whisper|ggml|whisper-cli' "$PB" "$SHEET" 2>/dev/null; then
  echo "Ordinary Assist UI must not mention whisper/ggml" >&2
  exit 1
fi
# No second alignment stack
if grep -Eq 'LineForcedAligner|AssistedCandidateMerger|AssistedAlignmentDraft' "$WHISPER"; then
  echo "Whisper engine must not reimplement S3A/S3B/Merger" >&2
  exit 1
fi

echo "whisper_cli_engine_contract: PASS"

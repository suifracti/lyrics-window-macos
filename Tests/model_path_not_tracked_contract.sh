#!/usr/bin/env bash
# Phase 2.11C-S2: ggml models not in git; gitignored paths
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GI="$ROOT/.gitignore"
# Models directory ignored
grep -Eq 'whisper-models|s0-5-engine-viability/whisper-models' "$GI"
# Ensure no ggml bin tracked
if git -C "$ROOT" ls-files | grep -Eiq 'ggml-.*\.bin$'; then
  echo "ggml model bins must not be tracked" >&2
  exit 1
fi
# Whisper engine still requires external path (no Bundle.main model)
WHISPER="$ROOT/SpotifyLyrics/Capture/WhisperCLISpeechEngine.swift"
if grep -Eq 'Bundle\.main' "$WHISPER"; then
  echo "Whisper must not load model from App Bundle" >&2
  exit 1
fi
echo "model_path_not_tracked_contract: PASS"

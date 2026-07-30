#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
converter="$ROOT_DIR/SpotifyLyrics/Lyrics/AudioPCMConverter.swift"
grep -q 'AudioInputMetadata' "$converter"
grep -q 'FileHandle' "$converter"
grep -q 'withTaskCancellationHandler' "$converter"
grep -q 'sourceSampleRate\|inputSampleRate' "$converter"
echo "audio PCM lifecycle wiring contract passed"

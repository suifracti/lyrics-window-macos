#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
service="$ROOT_DIR/SpotifyLyrics/Lyrics/SpeechForcedAlignmentService.swift"
protocol="$ROOT_DIR/SpotifyLyrics/Lyrics/TimedTranscript.swift"
grep -q 'TimedTranscriptProvider' "$protocol"
grep -q 'transcriptProvider' "$service"
grep -q 'SpeechTimedTranscriptProvider' "$service"
grep -q 'func transcribe(' "$service"
echo "timed transcript wiring contract passed"

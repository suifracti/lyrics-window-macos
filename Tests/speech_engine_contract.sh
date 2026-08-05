#!/usr/bin/env bash
# Phase 2.11C-S1: engine-agnostic LyricsSpeechEngine protocol + registry
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENGINE="$ROOT/SpotifyLyrics/Capture/SpeechEngine.swift"
PIPE="$ROOT/SpotifyLyrics/Capture/SegmentPartialAlignmentPipeline.swift"
APPLE="$ROOT/SpotifyLyrics/Capture/AppleSpeechEngine.swift"
WHISPER="$ROOT/SpotifyLyrics/Capture/WhisperCLISpeechEngine.swift"

test -f "$ENGINE" && test -f "$APPLE" && test -f "$WHISPER" && test -f "$PIPE"

grep -Eq 'protocol LyricsSpeechEngine' "$ENGINE"
grep -Eq 'struct SpeechEngineResult|struct SpeechEngineSegment' "$ENGINE"
grep -Eq 'speechEngine\.apple\.v1|speechEngine\.whisperCLI\.experimental\.v1' "$ENGINE"
grep -Eq 'enum SpeechEngineRegistry|SPOTIFYLYRICS_SPEECH_ENGINE|debug\.speechEngineID' "$ENGINE"
grep -Eq 'func asTimedTranscript' "$ENGINE"
grep -Eq 'SpeechEngineError' "$ENGINE"

# Pipeline consumes registry only — no SFSpeech / whisper-cli in S3A body.
grep -Eq 'SpeechEngineRegistry\.resolve' "$PIPE"
if grep -Eiq 'SFSpeechRecognizer|whisper-cli|-oj |ggml-' "$PIPE"; then
  echo "S3A pipeline must not know engine subprocess details" >&2
  exit 1
fi

# No duplicated aligner / merger / draft for engines.
for f in "$ENGINE" "$APPLE" "$WHISPER"; do
  if grep -Eq 'struct LineForcedAligner|AssistedCandidateMerger|AssistedAlignmentDraft|PartialAlignmentReport' "$f"; then
    echo "Speech engines must not reimplement alignment stack: $f" >&2
    exit 1
  fi
done

echo "speech_engine_contract: PASS"

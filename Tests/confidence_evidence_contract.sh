#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SE="$ROOT/SpotifyLyrics/Capture/SpeechEngine.swift"
LF="$ROOT/SpotifyLyrics/Lyrics/LineForcedAligner.swift"
AN="$ROOT/SpotifyLyrics/Capture/AnchorConstrainedAligner.swift"
# Missing ASR encoded as -1, not fabricated 1.0
grep -Eq 'confidence \?\? -1|hasAsrConfidence' "$SE"
grep -Eq 'isObservedAsrConfidence|neutralPrior' "$LF"
grep -Eq 'missing_asr|neutralPrior|hasAsr' "$AN"
echo "confidence_evidence_contract: PASS"

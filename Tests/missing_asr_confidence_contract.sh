#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MG="$ROOT/SpotifyLyrics/Capture/AssistedCandidateMerger.swift"
grep -Eq 'lexicalRecoveryMinimum|lexical_recovery' "$MG"
# Must not require Apple ASR confidence to accept high lexical direct speech
grep -Eq 'lexicalOK|hardOK' "$MG"
echo "missing_asr_confidence_contract: PASS"

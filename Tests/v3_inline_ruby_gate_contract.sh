#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VIEW="$ROOT/SpotifyLyrics/Views/MainWindow/AppleMusicImmersiveV3WindowView.swift"

grep -q 'let tokens = inlineRubyTokens' "$VIEW" || {
  echo 'FAIL: V3 inline ruby can fall back to a whole-line kana annotation' >&2
  exit 1
}

grep -q '!tokens.isEmpty' "$VIEW" || {
  echo 'FAIL: V3 inline ruby does not require a non-empty per-token mapping' >&2
  exit 1
}

echo 'V3 inline ruby gate contract: PASS'

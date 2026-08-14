#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VIEW="$ROOT/SpotifyLyrics/Views/MainWindow/AppleMusicImmersiveV3WindowView.swift"

grep -q 'providerRubyTokens ?? automaticRubyTokens ?? reliableRubyTokens' "$VIEW" || {
  echo 'FAIL: V3 does not prioritize token-aligned provider ruby over local ambiguity' >&2
  exit 1
}

grep -q 'reading.isTokenAligned else { return nil }' "$VIEW" || {
  echo 'FAIL: V3 can still render whole-line automatic ruby when token boundaries are unproven' >&2
  exit 1
}

grep -q 'guard storedKanaText == nil, let reading = automaticReading, reading.isTokenAligned else { return nil }' "$VIEW" || {
  echo 'FAIL: V3 can replace an unprojectable provider reading with a conflicting local ruby' >&2
  exit 1
}

grep -q 'guard storedKanaText == nil, let tokens = line.rubyTokens' "$VIEW" || {
  echo 'FAIL: V3 can fall back to stale persisted ruby after provider kana is present' >&2
  exit 1
}

echo 'V3 local ruby priority contract: PASS'

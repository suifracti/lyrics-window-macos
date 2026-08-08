#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VIEW="$ROOT/SpotifyLyrics/Views/MainWindow/AppleMusicImmersiveV3WindowView.swift"
METADATA="$ROOT/SpotifyLyrics/Views/Components/TrackMetadataView.swift"

grep -q 'availableWidth: max(1, width -' "$VIEW" || {
  echo 'FAIL: V3 lyric viewport has no readable width policy' >&2
  exit 1
}

grep -q 'availableWidth: availableWidth' "$VIEW" || {
  echo 'FAIL: V3 lyric rows do not receive the viewport width proposal' >&2
  exit 1
}

grep -q '\.frame(maxWidth: \.infinity, alignment: \.leading)' "$VIEW" || {
  echo 'FAIL: V3 lyric rows are not constrained by the lyric viewport' >&2
  exit 1
}

grep -q 'LyricsDesignTokens.readableLyricLineMaxWidth' "$VIEW" || {
  echo 'FAIL: V3 lyric rows can still grow beyond a comfortable reading measure' >&2
  exit 1
}

grep -q 'V3LyricDisplayLineBreaker' "$VIEW" \
  && grep -q 'semanticDisplayText' "$VIEW" || {
  echo 'FAIL: long plain lyrics have no display-only semantic line breaker' >&2
  exit 1
}

grep -q 'RubyLineView(' "$VIEW" || {
  echo 'FAIL: V3 inline ruby renderer is missing' >&2
  exit 1
}

grep -q 'KanaReplacementLineView(' "$VIEW" || {
  echo 'FAIL: V3 kana replacement renderer is missing' >&2
  exit 1
}

grep -q 'presentation: \.v3Immersive' "$VIEW" &&
grep -q 'HStack(spacing: 6)' "$METADATA" || {
  echo 'FAIL: V3 metadata still uses three stacked rows' >&2
  exit 1
}

grep -q 'baseSize \* 0\.44' "$VIEW" || {
  echo 'FAIL: V3 ruby annotation remains too small' >&2
  exit 1
}

grep -q 'private var reliableRubyTokens' "$VIEW" || {
  echo 'FAIL: V3 does not have a reliable ruby-token gate' >&2
  exit 1
}

grep -q 'private var providerRubyTokens' "$VIEW" || {
  echo 'FAIL: V3 does not derive partial ruby tokens from a confirmed line-level kana layer' >&2
  exit 1
}

grep -q 'private var automaticReading' "$VIEW" || {
  echo 'FAIL: V3 does not generate a reading when the lyric line has no kana layer' >&2
  exit 1
}

grep -q 'private var storedKanaText' "$VIEW" || {
  echo 'FAIL: V3 does not normalize empty kana payloads to missing readings' >&2
  exit 1
}

grep -Fq 'storedKanaText ?? automaticReading?.kanaText' "$VIEW" || {
  echo 'FAIL: V3 display kana still ignores generated readings' >&2
  exit 1
}

if grep -q 'private var shouldRenderKanaFallback' "$VIEW"; then
  echo 'FAIL: V3 still renders an entire line of kana as a fallback' >&2
  exit 1
fi

grep -q 'tokens: inlineRubyTokens' "$VIEW" || {
  echo 'FAIL: V3 kana replacement still bypasses the trusted ruby-token mapping' >&2
  exit 1
}

grep -q 'let tokens = inlineRubyTokens' "$VIEW" || {
  echo 'FAIL: V3 inline ruby can fall back to a whole-line kana annotation' >&2
  exit 1
}

grep -q '!tokens.isEmpty' "$VIEW" || {
  echo 'FAIL: V3 inline ruby does not require a non-empty per-token mapping' >&2
  exit 1
}

echo 'V3 lyric readability contract: PASS'

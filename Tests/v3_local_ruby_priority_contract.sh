#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VIEW="$ROOT/SpotifyLyrics/Views/MainWindow/AppleMusicImmersiveV3WindowView.swift"

grep -q 'automaticRubyTokens ?? providerRubyTokens ?? reliableRubyTokens' "$VIEW" || {
  echo 'FAIL: V3 still prioritizes stale/provider ruby over local token-aligned reading' >&2
  exit 1
}

echo 'V3 local ruby priority contract: PASS'

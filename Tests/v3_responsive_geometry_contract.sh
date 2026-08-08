#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP_BIN="$(mktemp -t v3-responsive-geometry.XXXXXX)"
trap 'rm -f "$TMP_BIN"' EXIT

swiftc \
  "$ROOT/SpotifyLyrics/Design/V3ResponsiveGeometry.swift" \
  "$ROOT/Tests/v3_responsive_geometry_contract.swift" \
  -o "$TMP_BIN"

"$TMP_BIN"

#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/alignment-session.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT
swiftc -parse-as-library \
  "$ROOT_DIR/SpotifyLyrics/Models/Models.swift" \
  "$ROOT_DIR/SpotifyLyrics/Lyrics/TrackIdentity.swift" \
  "$ROOT_DIR/SpotifyLyrics/Lyrics/AlignmentSessionGuard.swift" \
  "$ROOT_DIR/Tests/alignment_session_contract.swift" \
  -o "$TMP_DIR/alignment-session-contract"
"$TMP_DIR/alignment-session-contract"

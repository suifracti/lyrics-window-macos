#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/debug-database-safety-contract.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

swiftc -D DEBUG -parse-as-library \
  "$ROOT_DIR/SpotifyLyrics/DebugDatabaseSafety.swift" \
  "$ROOT_DIR/Tests/debug_database_safety_contract.swift" \
  -o "$TMP_DIR/debug-database-safety-contract"

"$TMP_DIR/debug-database-safety-contract"

if ! rg -n 'failClosedForCommandLineV4IfNeeded|SPOTIFYLYRICS_DATABASE_PATH' \
  "$ROOT_DIR/SpotifyLyrics/Main.swift" >/dev/null; then
  echo "Main.swift must invoke the debug database preflight" >&2
  exit 1
fi

if ! rg -n 'DebugDatabaseSafety.*menu|menu.*DebugDatabaseSafety|refusalMessage' \
  "$ROOT_DIR/SpotifyLyrics/Main.swift" >/dev/null; then
  echo "Debug capsule menu must use the database safety guard" >&2
  exit 1
fi

if ! rg -n 'logRepositoryOpen' \
  "$ROOT_DIR/SpotifyLyrics/Persistence/SQLiteLyricsRepository.swift" >/dev/null; then
  echo "SQLite repository must report its debug database path" >&2
  exit 1
fi

echo "debug database safety static contract: PASS"

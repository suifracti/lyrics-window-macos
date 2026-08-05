#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
grep -Eq 's4-5-real-song-gate/local-real-songs|s4-5-real-song-gate/runs' "$ROOT/.gitignore"
if git -C "$ROOT" ls-files | grep -Eiq 's4-5-real-song-gate/local-real-songs/.*\.(wav|mp3|m4a)$'; then
  echo "commercial audio tracked" >&2
  exit 1
fi
echo "commercial_audio_not_tracked_contract: PASS"

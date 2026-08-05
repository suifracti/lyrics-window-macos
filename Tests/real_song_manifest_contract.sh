#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$ROOT/docs/phase-2-11c-zero-operation-alignment/s4-5-real-song-gate/anonymous_manifest.template.json"
S="$ROOT/Tools/s45_real_song_gate/select_candidates.py"
test -f "$T" && test -f "$S"
grep -Eq 'local-real-songs|manifest|script_lang|structure_tag' "$S"
grep -Eq 's4-5-real-song-gate/local-real-songs' "$ROOT/.gitignore"
echo "real_song_manifest_contract: PASS"

#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
P="$ROOT/docs/phase-2-11c-zero-operation-alignment/s4-repeated-sections/real-songs/PROTOCOL.md"
I="$ROOT/docs/phase-2-11c-zero-operation-alignment/s4-repeated-sections/real-songs/inventory.json"
test -f "$P" && test -f "$I"
grep -Eq 'wrong_occurrence|human|local-real-songs' "$P"
grep -Eq 'RS-JP|missing_local_wav|auto_gate_eligible' "$I"
echo "real_song_evaluation_contract: PASS"

#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOC="$ROOT/docs/phase-2-11c-zero-operation-alignment/S4_5_REAL_SONG_GATE.md"
SUM="$ROOT/docs/phase-2-11c-zero-operation-alignment/s4-5-real-song-gate/summary.json"
test -f "$DOC" && test -f "$SUM"
grep -Eq '最终路线|ROUTE|D\.|route' "$DOC"
python3 - <<'PY'
import json
from pathlib import Path
s=json.loads(Path('docs/phase-2-11c-zero-operation-alignment/s4-5-real-song-gate/summary.json').read_text())
assert s.get('route') in ('A','B','C','D')
assert 'route_reason' in s
print('route', s['route'])
PY
# no algorithm source edits required in this phase — tools only under Tools/s45
echo "real_song_gate_contract: PASS"

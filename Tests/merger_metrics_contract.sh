#!/usr/bin/env bash
# Phase 2.11C-S2: merger metrics recorded (not transcript-only comparison)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MAIN="$ROOT/Tools/s2_full_pipeline/main.swift"
RUN="$ROOT/Tools/s2_full_pipeline/run_matrix.py"
ROWS="$ROOT/docs/phase-2-11c-zero-operation-alignment/s2-whisper-full-pipeline/metrics/rows.json"

grep -Eq 'final_suggestions|suggestion_coverage|from_anchor' "$MAIN"
grep -Eq 'wrong_suggestions|token_hit|s3a_coverage|s3b_anchors' "$RUN"
test -f "$ROWS"
# rows must include merger + s3 fields
python3 - "$ROWS" <<'PY'
import json,sys
from pathlib import Path
rows=json.loads(Path(sys.argv[1]).read_text())
assert rows, 'empty rows'
need={'suggestions','s3a_coverage','s3b_anchors','pieces','token_hit_rate'}
for r in rows:
    missing=need-set(r)
    assert not missing, missing
print('merger_metrics_contract: rows OK', len(rows))
PY
echo "merger_metrics_contract: PASS"

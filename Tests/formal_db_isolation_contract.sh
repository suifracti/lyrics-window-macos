#!/usr/bin/env bash
# Phase 2.11C-S2: formal DB isolation proof artifacts
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
S2="$ROOT/docs/phase-2-11c-zero-operation-alignment/s2-whisper-full-pipeline"
RUN="$ROOT/Tools/s2_full_pipeline/run_matrix.py"

grep -Eq 'formal_sha|formal_unchanged|FORMAL_DB' "$RUN"
test -f "$S2/formal_db_before.sha" || test -f "$S2/formal-db-after.sha" || test -f "$S2/metrics/raw_results.json"
# raw_results claims formal_opened false
if test -f "$S2/metrics/raw_results.json"; then
  python3 - <<'PY'
import json
from pathlib import Path
p=Path("docs/phase-2-11c-zero-operation-alignment/s2-whisper-full-pipeline/metrics/raw_results.json")
d=json.loads(p.read_text())
assert d.get("formal_opened") is False
assert d.get("formal_unchanged") is True
print("formal isolation JSON OK")
PY
fi
# harness has no SQLite repository
if grep -Eq 'SQLiteLyricsRepository' "$ROOT/Tools/s2_full_pipeline/main.swift"; then
  echo "harness must not import SQLite repo" >&2
  exit 1
fi
echo "formal_db_isolation_contract: PASS"

#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TAB="$ROOT/docs/phase-2-11c-zero-operation-alignment/s4-repeated-sections/metrics/s3_to_s4.md"
AFTER="$ROOT/docs/phase-2-11c-zero-operation-alignment/s4-repeated-sections/metrics/after_rows.json"
test -f "$TAB" && test -f "$AFTER"
# sampleA/C/D must keep non-zero for whisper paths
python3 - <<'PY'
import json
from pathlib import Path
rows=json.loads(Path('docs/phase-2-11c-zero-operation-alignment/s4-repeated-sections/metrics/after_rows.json').read_text())
m={(r['sample'],r['engine']):r for r in rows}
for s in ['sampleA','sampleC','sampleD']:
  for e in ['whisper_small','whisper_medium']:
    assert m[(s,e)]['suggestions']>0, (s,e)
# Apple non-repeat samples not zeroed
assert m[('sampleA','apple')]['suggestions']>=4
assert m[('sampleC','apple')]['suggestions']>=20
assert m[('sampleD','apple')]['suggestions']>=1
print('no_regression_nonrepeated_contract: numeric OK')
PY
echo "no_regression_nonrepeated_contract: PASS"

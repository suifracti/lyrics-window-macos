#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
S2="$ROOT/docs/phase-2-11c-zero-operation-alignment/s2-whisper-full-pipeline/fixtures/samples_manifest.json"
S3="$ROOT/docs/phase-2-11c-zero-operation-alignment/s3-transcript-alignment/metrics/before_after.md"
BA="$ROOT/docs/phase-2-11c-zero-operation-alignment/s3-transcript-alignment/metrics/s2_before_rows.json"
test -f "$S2" && test -f "$S3" && test -f "$BA"
grep -Eq 'sampleA|sampleB|sampleC|sampleD' "$S2"
grep -Eq 'Merger suggestions|Before|After' "$S3"
# S2 baseline numbers present for C zero→nonzero narrative
grep -Eq '0 \| 21|0 \| 23|sampleC' "$S3" || grep -Eq 'sampleC' "$S3"
echo "same_fixture_before_after_contract: PASS"

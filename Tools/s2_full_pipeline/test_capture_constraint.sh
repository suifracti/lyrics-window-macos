#!/usr/bin/env bash
# S4 unit check: capture window must reject times outside absolute range.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$ROOT/Tools/s2_full_pipeline/.build/s2_full_pipeline"
S2="$ROOT/docs/phase-2-11c-zero-operation-alignment/s2-whisper-full-pipeline/fixtures"
MODEL="$ROOT/docs/phase-2-11c-zero-operation-alignment/s0-5-engine-viability/whisper-models/ggml-small.bin"
OUT="/tmp/s4-capture-constraint"
rm -rf "$OUT" && mkdir -p "$OUT"

export SPOTIFYLYRICS_WHISPER_CLI="${SPOTIFYLYRICS_WHISPER_CLI:-/opt/homebrew/bin/whisper-cli}"
export SPOTIFYLYRICS_WHISPER_MODEL="$MODEL"
export SPOTIFYLYRICS_WHISPER_LANGUAGE=ja

# Simulate capture deep in a long track: WAV relative 0 maps to absolute 120s.
# Suggestions must not land near absolute 0–40 (first-chorus domain).
"$BIN" \
  --wav "$S2/audio/sampleA.wav" \
  --lyrics "$S2/sampleA_plain.txt" \
  --out "$OUT" \
  --engine whisper_small \
  --lang ja \
  --title "capture-constraint" \
  --artist "test" \
  --position-start 120 \
  --position-end 160 \
  --track-duration 200 \
  2>"$OUT/stderr.txt"

python3 - <<'PY'
import json,sys
m=json.load(open("/tmp/s4-capture-constraint/metrics.json"))
rep=json.load(open("/tmp/s4-capture-constraint/alignment_report.json"))
# All timed S3B lines must be >= ~119
bad=[]
for line in rep["candidate"]["lines"]:
    t=line.get("startTime")
    if t is None: continue
    if t < 119 or t > 161:
        bad.append((line["sourceLineIndex"], t, line.get("evidenceKind")))
print("suggestions", m["merger"]["final_suggestions"])
print("capture", m.get("capture"))
print("repeated", m.get("repeated"))
print("out_of_window", len(bad), bad[:5])
if bad:
    sys.exit(1)
# Capture constraint file
res=json.load(open("/tmp/s4-capture-constraint/repeated_resolution.json"))
outside=[r for r in res if "outside_capture" in r.get("reason","")]
print("outside_capture_rejections", len(outside))
print("capture_constraint_ok")
PY
echo "test_capture_constraint: PASS"

#!/usr/bin/env bash
# Partial suggestions must not auto-adopt full timeline.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GATE="$ROOT/SpotifyLyrics/Capture/AutomaticAlignmentQualityGate.swift"
JOB="$ROOT/SpotifyLyrics/Capture/AutomaticAlignmentJobController.swift"
# completeAndAdopt only at full coverage (or harness force)
grep -Eq 'coverage >= 0\.98 && timedRequired\.count == required\.count' "$GATE"
# accumulate path must not call adoptPersisted
python3 - <<'PY'
from pathlib import Path
text = Path("SpotifyLyrics/Capture/AutomaticAlignmentJobController.swift").read_text()
# Extract accumulate branch roughly
idx = text.find("case .accumulate:")
if idx < 0: raise SystemExit("missing accumulate branch")
chunk = text[idx:idx+500]
if "adoptPersisted" in chunk or "saveAlignedVersion" in chunk:
    raise SystemExit("accumulate must not adopt/save formal version")
print("accumulate branch clean")
PY
echo "automatic_alignment_no_partial_adopt_contract: PASS"

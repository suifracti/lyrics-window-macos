#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PERSISTENCE="$ROOT/SpotifyLyrics/Windows/CapsuleLyricsWindowPersistence.swift"
CONTROLLER="$ROOT/SpotifyLyrics/Windows/CapsuleLyricsWindowController.swift"
MANAGER="$ROOT/SpotifyLyrics/Windows/WindowManager.swift"
MAIN="$ROOT/SpotifyLyrics/Main.swift"

require() {
  local pattern="$1"
  local file="$2"
  grep -Eq "$pattern" "$file" || {
    echo "FAIL: missing /$pattern/ in $file" >&2
    exit 1
  }
}

require '#if DEBUG' "$PERSISTENCE"
require 'enum[[:space:]]+CapsuleDebugAnchor' "$PERSISTENCE"
require 'case[[:space:]]+topLeft' "$PERSISTENCE"
require 'case[[:space:]]+topCenter' "$PERSISTENCE"
require 'case[[:space:]]+topRight' "$PERSISTENCE"
require 'visibleFrame' "$PERSISTENCE"
require 'setCapsuleDebugAnchor' "$MANAGER"
require 'setDebugAnchor' "$CONTROLLER"
require 'Debug' "$MAIN"
require 'topCenter' "$MAIN"
require 'debugAnchor' "$CONTROLLER"
require 'debugAnchor:[[:space:]]*CapsuleDebugAnchor' "$PERSISTENCE"
require 'resolvedAnchor' "$PERSISTENCE"
require 'return[[:space:]]+\.topCenter' "$PERSISTENCE"

if grep -Eq 'capsule.*Anchor|anchor.*capsule' "$ROOT/SpotifyLyrics/Settings/AppSettingsStore.swift"; then
  echo 'FAIL: debug anchor must not become a persisted user setting' >&2
  exit 1
fi

require 'horizontalOffset' "$PERSISTENCE"
require 'clampTopFrame' "$PERSISTENCE"

# The comparison command and the controller hook must be Debug-only.  This is
# intentionally checked structurally rather than accepting a comment or a
# runtime boolean that would still ship a Release menu/API.
python3 - "$MANAGER" "$MAIN" <<'PY'
from pathlib import Path
import sys

def require_debug_scoped(path: Path, needle: str) -> None:
    depth = 0
    found = False
    for line in path.read_text().splitlines():
        stripped = line.strip()
        if stripped.startswith("#if DEBUG"):
            depth += 1
        elif stripped.startswith("#if "):
            depth += 1
        elif stripped.startswith("#endif"):
            depth = max(0, depth - 1)
        if needle in line and depth > 0:
            found = True
    if not found:
        raise SystemExit(f"FAIL: {needle} must be inside #if DEBUG in {path}")

require_debug_scoped(Path(sys.argv[1]), "setCapsuleDebugAnchor")
require_debug_scoped(Path(sys.argv[2]), "setCapsuleDebugAnchor")
PY

# Debug anchor selection must not become a persisted AppSettingsStore key or
# be coupled to the user's normal horizontal-offset/frame recovery fields.
if grep -Eq 'capsule.*Anchor|anchor.*capsule' "$ROOT/SpotifyLyrics/Settings/AppSettingsStore.swift"; then
  echo 'FAIL: debug anchor must not become a persisted user setting' >&2
  exit 1
fi

if grep -Eq 'capsuleWindowHorizontalOffset.*debug|debug.*capsuleWindowHorizontalOffset' "$CONTROLLER" "$PERSISTENCE"; then
  echo 'FAIL: applying a debug anchor must not rewrite the saved horizontal offset' >&2
  exit 1
fi

echo "phase2.2 capsule debug anchor contract passed"

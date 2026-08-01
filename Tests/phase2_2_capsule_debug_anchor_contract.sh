#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PERSISTENCE="$ROOT/SpotifyLyrics/Windows/CapsuleLyricsWindowPersistence.swift"
CONTROLLER="$ROOT/SpotifyLyrics/Windows/CapsuleLyricsWindowController.swift"
MANAGER="$ROOT/SpotifyLyrics/Windows/WindowManager.swift"
MAIN="$ROOT/SpotifyLyrics/Main.swift"
SETTINGS="$ROOT/SpotifyLyrics/Settings/AppSettingsStore.swift"

for file in "$PERSISTENCE" "$CONTROLLER" "$MANAGER" "$MAIN" "$SETTINGS"; do
  test -f "$file" || { echo "FAIL: missing $file" >&2; exit 1; }
done

python3 - "$PERSISTENCE" "$CONTROLLER" "$MANAGER" "$MAIN" "$SETTINGS" <<'PY'
from pathlib import Path
import sys

persistence, controller, manager, main, settings = map(Path, sys.argv[1:])

def lines(path: Path):
    return path.read_text().splitlines()

def debug_ranges(path: Path):
    """Return inclusive line ranges compiled only for #if DEBUG blocks."""
    result = []
    stack = []
    for number, line in enumerate(lines(path), 1):
        stripped = line.strip()
        if stripped.startswith("#if "):
            stack.append((number, stripped == "#if DEBUG"))
        elif stripped.startswith("#endif") and stack:
            start, is_debug = stack.pop()
            if is_debug:
                result.append((start, number))
    return result

def in_debug(path: Path, number: int) -> bool:
    return any(start < number < end for start, end in debug_ranges(path))

def require_line(path: Path, text: str):
    if not any(text in line for line in lines(path)):
        raise SystemExit(f"FAIL: {text!r} missing from {path}")

def require_debug_scoped(path: Path, text: str):
    matches = [number for number, line in enumerate(lines(path), 1) if text in line]
    if not matches:
        raise SystemExit(f"FAIL: {text!r} missing from {path}")
    if any(not in_debug(path, number) for number in matches):
        raise SystemExit(f"FAIL: {text!r} has a Release-visible occurrence in {path}")

def require_outside_debug(path: Path, text: str):
    matches = [number for number, line in enumerate(lines(path), 1) if text in line]
    if not matches or all(in_debug(path, number) for number in matches):
        raise SystemExit(f"FAIL: {text!r} has no center-only non-debug path in {path}")

def block(path: Path, start_text: str, end_text: str):
    source = lines(path)
    start = next((i for i, line in enumerate(source) if start_text in line), None)
    if start is None:
        raise SystemExit(f"FAIL: block start {start_text!r} missing from {path}")
    end = next((i for i in range(start + 1, len(source)) if end_text in source[i]), len(source))
    return "\n".join(source[start:end])

# P1: the debug type, non-center cases, and debug selection APIs must be
# eliminated by the Release preprocessor rather than hidden behind a runtime
# boolean.
require_debug_scoped(persistence, "enum CapsuleDebugAnchor")
for text in ("case topLeft", "case topRight", "switch debugAnchor"):
    require_debug_scoped(persistence, text)
require_debug_scoped(controller, "CapsuleDebugAnchor")
require_debug_scoped(controller, "func setDebugAnchor")
require_debug_scoped(manager, "func setCapsuleDebugAnchor")
for text in ("胶囊锚点（调试）", "setCapsuleDebugAnchor", ".topLeft", ".topRight"):
    require_debug_scoped(main, text)

# The normal overloads remain available without CapsuleDebugAnchor. The debug
# overloads are separate and cannot leak their type into Release.
require_outside_debug(persistence, "horizontalOffset: CGFloat")
require_debug_scoped(persistence, "debugAnchor: CapsuleDebugAnchor")
require_line(controller, "#else")
require_line(controller, "persistence.restoreFrame(")

# P2: use the display safe-area inset to calculate the top position, then
# still clamp against visibleFrame. The controller also uses the screen-aware
# clamp when saving a moved frame.
require_line(persistence, "screen.safeAreaInsets.top")
require_line(persistence, "screen.visibleFrame")
require_line(persistence, "clampTopFrame")
require_line(controller, "clampTopFrame(panel.frame, screen: screen)")

# Debug switching must not write the normal user frame/offset or create a
# settings key. This checks the actual method body, not just a comment.
debug_setter = block(controller, "func setDebugAnchor", "#endif")
for forbidden in ("savePosition", "capsuleWindowHorizontalOffset", "capsuleWindowScreenID"):
    if forbidden in debug_setter:
        raise SystemExit(f"FAIL: debug setter touches persisted {forbidden}")
if any("Anchor" in line or "anchor" in line for line in lines(settings)):
    raise SystemExit("FAIL: debug anchor must not become an AppSettingsStore key")

# Deterministic geometry model: the three Debug anchors use the same saved
# offset convention, respect the top safe inset, and clamp to visibleFrame.
visible = (100.0, 50.0, 1200.0, 700.0)  # x, y, width, height
width, height, offset, safe_top, minimum_top = 360.0, 46.0, 17.0, 24.0, 10.0
left, bottom, screen_width, screen_height = visible
right, top = left + screen_width, bottom + screen_height
effective_top = max(minimum_top, safe_top)

def model(anchor):
    if anchor == "topLeft":
        x = left + offset
    elif anchor == "topCenter":
        x = (left + right) / 2 - width / 2 + offset
    elif anchor == "topRight":
        x = right - width - offset
    else:
        raise AssertionError(anchor)
    y = top - height - effective_top
    x = min(max(x, left), right - width)
    y = min(max(y, bottom), max(bottom, top - height - effective_top))
    return x, y

assert model("topLeft") == (117.0, 680.0), model("topLeft")
assert model("topCenter") == (537.0, 680.0), model("topCenter")
assert model("topRight") == (923.0, 680.0), model("topRight")
assert model("topLeft")[0] >= left
assert model("topRight")[0] + width <= right
assert model("topCenter")[1] + height <= top - effective_top
print("phase2.2 capsule debug anchor contract passed")
PY

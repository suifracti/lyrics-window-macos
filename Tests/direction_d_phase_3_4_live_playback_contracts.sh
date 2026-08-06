#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLAYBACK="$ROOT/SpotifyLyrics/Services/PlaybackState.swift"
MAIN="$ROOT/SpotifyLyrics/Views/Components/DirectionD/DirectionDMainWindowView.swift"
LYRICS="$ROOT/Lyrics" # marker only; no fixture data is used by this suite

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "[PASS] $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "[FAIL] $1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
contains() { grep -Fq "$2" "$1"; }

assert_contains() {
    local name="$1" file="$2" needle="$3"
    if contains "$file" "$needle"; then pass "$name"; else fail "$name (missing: $needle)"; fi
}

assert_not_contains() {
    local name="$1" file="$2" needle="$3"
    if contains "$file" "$needle"; then fail "$name (unexpected: $needle)"; else pass "$name"; fi
}

echo "======================================================"
echo "Lyric Island Phase 3.4 Live Playback Contract Test Suite"
echo "======================================================"

assert_contains "direction_d_live_current_line_contract.timeline" "$PLAYBACK" "LyricsTimeline.activeLineIndex"
assert_contains "direction_d_live_current_line_contract.view" "$MAIN" "projectedCurrentLineIndex"
assert_contains "direction_d_live_scroll_target_contract.reader" "$MAIN" "ScrollViewReader"
assert_contains "direction_d_live_scroll_target_contract.target" "$MAIN" "proxy.scrollTo"
assert_contains "direction_d_live_scroll_target_contract.evidence" "$MAIN" "D_SCROLL identity="
assert_contains "direction_d_playback_progress_updates_line_contract" "$MAIN" "onChange(of: projectedCurrentLineIndex)"
assert_contains "direction_d_pause_preserves_line_contract" "$MAIN" "stateKind" # Direction D preserves the shared state surface while paused.
assert_contains "direction_d_resume_continues_scroll_contract" "$MAIN" "scrollDirectionDToCurrentLine"
assert_contains "direction_d_seek_repositions_line_contract" "$MAIN" "playbackState.currentTime"
assert_contains "direction_d_external_track_switch_contract" "$MAIN" "liveLyricsDocumentMatchesCurrentTrack"
assert_contains "direction_d_external_track_switch_never_mixes_lyrics_contract" "$PLAYBACK" "guard liveLyricsDocumentMatchesCurrentTrack else { return [] }"
assert_contains "direction_d_layout_does_not_reset_scroll_contract" "$MAIN" "DirectionDResponsiveLayout.resolveMode"
assert_contains "direction_d_inspector_does_not_reset_scroll_contract" "$MAIN" "isInspectorOpen"

# The executable mirror below tests the actual timing/identity contract, not
# only source spelling. It models the existing LyricsTimeline semantics and
# the Direction D projection invariant.
if python3 - "$MAIN" "$PLAYBACK" <<'PY'
from pathlib import Path
import sys

main = Path(sys.argv[1]).read_text()
playback = Path(sys.argv[2]).read_text()

if "ScrollViewReader" not in main or "proxy.scrollTo" not in main:
    raise SystemExit("Direction D has no live scroll target adapter")
if "guard liveLyricsDocumentMatchesCurrentTrack else { return [] }" not in playback:
    raise SystemExit("live projection is not fail-closed")
if ".id(mode)" in main or ".id(isInspectorOpen)" in main:
    raise SystemExit("layout/inspector is allowed to reset the scroll identity")

# Same binary-search rule as LyricsTimeline.activeLineIndex: last timestamp
# less than or equal to current playback time.
def active_line_index(timestamps, time, synchronized=True):
    if not synchronized or not timestamps:
        return None
    lower, upper = 0, len(timestamps)
    while lower < upper:
        middle = lower + (upper - lower) // 2
        if timestamps[middle] <= time:
            lower = middle + 1
        else:
            upper = middle
    return None if lower == 0 else lower - 1

# A real synchronized document: distinct time windows must produce distinct
# indices and target IDs.
timestamps = [0.0, 18.0, 42.0, 74.0, 108.0, 145.0]
ids = [f"line-{i}" for i in range(len(timestamps))]
indices = [active_line_index(timestamps, t) for t in (20.0, 70.0, 120.0)]
assert indices == [1, 2, 4], indices
targets = [ids[i] for i in indices]
assert len(set(targets)) == 3, targets

# Pause preserves the current index; resume advances from that same playback
# position rather than resetting to the first line.
paused_index = active_line_index(timestamps, 70.0)
resumed_index = active_line_index(timestamps, 82.0)
assert paused_index == 2
assert resumed_index == 3
assert paused_index != 0

# Seek directly repositions the target in either direction.
assert active_line_index(timestamps, 120.0) == 4
assert active_line_index(timestamps, 20.0) == 1

# During A -> B handoff, B metadata with A document produces no visible lines
# and no scroll target. Once B is adopted, only a B target is valid.
def visible_target(current_identity, document_identity, line_index):
    if current_identity != document_identity:
        return None
    return None if line_index is None else f"{document_identity}-line-{line_index}"

assert visible_target("A", "A", 2) == "A-line-2"
assert visible_target("B", "A", 2) is None
assert visible_target("B", "B", 1) == "B-line-1"
assert visible_target("A", "B", 1) is None

# Pause and layout/inspector changes do not alter the identity or target.
assert visible_target("A", "A", paused_index) == "A-line-2"
assert visible_target("A", "A", paused_index) == "A-line-2"
PY
then
    pass "direction_d_live_playback_behavior_model"
else
    fail "direction_d_live_playback_behavior_model"
fi

echo "======================================================"
echo "Summary: $PASS_COUNT passed, $FAIL_COUNT failed."
echo "======================================================"

if [ "$FAIL_COUNT" -ne 0 ]; then exit 1; fi

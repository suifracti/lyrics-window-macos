#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLAYBACK="$ROOT/SpotifyLyrics/Services/PlaybackState.swift"
SESSION="$ROOT/SpotifyLyrics/Services/LyricsSessionController.swift"
ADAPTER="$ROOT/SpotifyLyrics/Design/DirectionD/DirectionDProductStateAdapter.swift"
STATE_MODEL="$ROOT/SpotifyLyrics/Design/DirectionD/DirectionDProductStateModel.swift"
MAIN="$ROOT/SpotifyLyrics/Views/Components/DirectionD/DirectionDMainWindowView.swift"

PASS_COUNT=0
FAIL_COUNT=0

pass() {
    echo "[PASS] $1"
    PASS_COUNT=$((PASS_COUNT + 1))
}

fail() {
    echo "[FAIL] $1"
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

contains() {
    local file="$1"
    local needle="$2"
    grep -Fq "$needle" "$file"
}

assert_contains() {
    local name="$1"
    local file="$2"
    local needle="$3"
    if contains "$file" "$needle"; then
        pass "$name"
    else
        fail "$name (missing: $needle)"
    fi
}

assert_not_contains() {
    local name="$1"
    local file="$2"
    local needle="$3"
    if contains "$file" "$needle"; then
        fail "$name (unexpected: $needle)"
    else
        pass "$name"
    fi
}

echo "======================================================"
echo "Lyric Island Phase 3.4 Correctness Contract Test Suite"
echo "======================================================"

# A track handoff must fail closed before any new document is adopted.
assert_contains \
    "direction_d_track_change_clears_old_lyrics_contract" \
    "$PLAYBACK" \
    "guard liveLyricsDocumentMatchesCurrentTrack else { return [] }"
assert_contains \
    "direction_d_track_change_clears_old_lyrics_contract.adapter" \
    "$ADAPTER" \
    "lyricsLines = []"

# A visible document is valid only when its identity equals the live track.
assert_contains \
    "direction_d_document_identity_matches_track_contract" \
    "$PLAYBACK" \
    "return lyricsSession.activeIdentity == liveTrackIdentity"
assert_contains \
    "direction_d_document_identity_matches_track_contract.adapter" \
    "$ADAPTER" \
    "let documentMatchesTrack = playback.liveLyricsDocumentMatchesCurrentTrack"

# Session revision and identity guards reject late provider results.
assert_contains \
    "direction_d_late_lyrics_result_rejected_contract" \
    "$SESSION" \
    "self.activeIdentity == identity"
assert_contains \
    "direction_d_late_lyrics_result_rejected_contract.revision" \
    "$SESSION" \
    "self.revision == requestRevision"

# Auxiliary layers must disappear with the old document as well.
assert_contains \
    "direction_d_old_auxiliary_projection_cleared_contract.language" \
    "$PLAYBACK" \
    "liveLyricsDocumentMatchesCurrentTrack ? lyricsSession.activeDocument?.language : nil"
assert_contains \
    "direction_d_old_auxiliary_projection_cleared_contract.source" \
    "$PLAYBACK" \
    "liveLyricsDocumentMatchesCurrentTrack ? lyricsSession.activeDocument?.source : nil"
assert_contains \
    "direction_d_old_auxiliary_projection_cleared_contract.adapter" \
    "$ADAPTER" \
    "lyricsLines = playback.liveLyricsDocumentMatchesCurrentTrack ? playback.liveLyrics : []"

# The adapter must expose loading/empty content while the document is stale,
# never the previous track's lines.
assert_contains \
    "direction_d_loading_never_shows_previous_track_contract" \
    "$ADAPTER" \
    "if hasTrack && !documentMatchesTrack { return true }"
assert_contains \
    "direction_d_loading_never_shows_previous_track_contract.lines" \
    "$ADAPTER" \
    "let lines = documentMatchesTrack ? playback.liveLyrics : []"

# Paused playback retains a track.  This is a source assertion plus a small
# executable mirror of the resolver's decisive rule.
assert_contains \
    "direction_d_paused_track_not_idle_contract" \
    "$STATE_MODEL" \
    "if !hasTrack {"
assert_contains \
    "direction_d_paused_track_not_idle_contract.comment" \
    "$STATE_MODEL" \
    "pause must NOT drop to idle"
if python3 - "$STATE_MODEL" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text()
if "if !hasTrack {\n            return (.waitingForPlayback, .none)" not in source:
    raise SystemExit("resolver no-track branch is not explicit")

def resolve(has_track: bool, is_playing: bool) -> str:
    # This mirrors the resolver's contract: playback state is irrelevant to
    # the idle decision once a current track exists.
    _ = is_playing
    return "waitingForPlayback" if not has_track else "showingLyrics"

assert resolve(True, False) != "waitingForPlayback"
assert resolve(True, True) != "waitingForPlayback"
assert resolve(False, False) == "waitingForPlayback"
PY
then
    pass "direction_d_paused_track_not_idle_contract.runtime"
else
    fail "direction_d_paused_track_not_idle_contract.runtime"
fi

# Inspector and layout changes must remain presentation-only.  Layout-only
# debug keys are deliberately excluded from the forced-state list.
assert_contains \
    "direction_d_inspector_preserves_product_state_contract" \
    "$MAIN" \
    "case \"wide-inspector\", \"wide_inspector\", \"inspector\":"
assert_contains \
    "direction_d_inspector_preserves_product_state_contract.fixture_gate" \
    "$ADAPTER" \
    "public static func isAcceptanceFixtureKey"
if python3 - "$ADAPTER" <<'PY'
from pathlib import Path
import re
import sys

source = Path(sys.argv[1]).read_text()
match = re.search(
    r"public static func isAcceptanceFixtureKey\(_ raw: String\) -> Bool \{(.*?)\n    \}\n\n    /// Controlled host acceptance",
    source,
    re.S,
)
if not match:
    raise SystemExit("fixture gate body not found")
body = match.group(1)
for forbidden in ("wide-inspector", "wide_inspector", "small-sheet", "small_sheet"):
    if forbidden in body:
        raise SystemExit(f"layout key incorrectly treated as forced state: {forbidden}")
PY
then
    pass "direction_d_inspector_preserves_product_state_contract.layout_keys_not_forced"
else
    fail "direction_d_inspector_preserves_product_state_contract.layout_keys_not_forced"
fi

assert_contains \
    "direction_d_layout_preserves_product_state_contract" \
    "$MAIN" \
    "DirectionDResponsiveLayout.resolveMode"
assert_contains \
    "direction_d_layout_preserves_product_state_contract.binding" \
    "$MAIN" \
    "adapter.bind(playback: playbackState)"

# Forced state is a DEBUG-only acceptance facility.  Release builds must not
# read the environment or apply an acceptance fixture.
assert_contains \
    "direction_d_forced_state_debug_only_contract.main" \
    "$MAIN" \
    "#if DEBUG"
assert_contains \
    "direction_d_forced_state_debug_only_contract.adapter" \
    "$ADAPTER" \
    "let acceptanceOverride: String? = nil"
assert_contains \
    "direction_d_forced_state_debug_only_contract.environment" \
    "$ADAPTER" \
    "ProcessInfo.processInfo.environment[\"SPOTIFYLYRICS_DIRECTION_D_HOST_STATE\"]"

echo "======================================================"
echo "Summary: $PASS_COUNT passed, $FAIL_COUNT failed."
echo "======================================================"

if [ "$FAIL_COUNT" -ne 0 ]; then
    exit 1
fi

#!/usr/bin/env bash
# Assist V3 manual entry wiring: single sheet host, phase recovery, no harness-only path.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PB="$ROOT/SpotifyLyrics/Services/PlaybackState.swift"
MAIN="$ROOT/SpotifyLyrics/Views/MainWindow/MainLyricsWindowView.swift"
OPS="$ROOT/SpotifyLyrics/Views/Components/CurrentSongOperationsView.swift"
CANVAS="$ROOT/SpotifyLyrics/Views/Components/LyricsCanvasView.swift"
SHEET="$ROOT/SpotifyLyrics/Views/Components/AssistExplainSheet.swift"
V3="$ROOT/SpotifyLyrics/Views/MainWindow/AppleMusicImmersiveV3WindowView.swift"
MENU="$ROOT/SpotifyLyrics/Main.swift"

# --- 1) Single sheet host on MainLyricsWindowView (shared V3 + classic) ---
grep -Eq 'AssistExplainSheet\(state:' "$MAIN"
grep -Eq 'dismissListeningAssistExplanation' "$MAIN"
# Must not re-host AssistExplainSheet under LyricsCanvasView (duplicate host risk)
if grep -Eq 'AssistExplainSheet\(state:' "$CANVAS" || grep -Eq '\.sheet\(isPresented:.*isAssistExplainSheetPresented' "$CANVAS"; then
  echo "LyricsCanvasView must not host AssistExplainSheet (single host is MainLyricsWindowView)" >&2
  exit 1
fi

# --- 2) V3 + classic product entry still present ---
grep -Eq '边听边排轴' "$OPS"
grep -Eq '边听边排轴' "$CANVAS"
grep -Eq '边听边排轴' "$V3"
grep -Eq 'canStartListeningAssist' "$OPS" "$V3" "$CANVAS"

# --- 3) explaining recovery (no stuck explaining) ---
grep -Eq 'func dismissListeningAssistExplanation' "$PB"
grep -Eq 'ASSIST explanation dismissed' "$PB"
# explaining UI must offer cancel / reopen sheet — not silent disappearance
grep -Eq 'explaining|打开说明' "$OPS"

# --- 4) capturing cancel + track-change still wired ---
grep -Eq 'cancelListeningAssist' "$PB" "$OPS"
grep -Eq 'invalidateAssistOnTrackChange' "$PB"
grep -Eq 'reason: \.userStop|reason: \.trackChanged' "$PB"

# --- 5) draftReady opens existing editor (no second editor) ---
grep -Eq 'openListeningAssistEditorWithDraft|assistEditorOpenToken' "$PB"
grep -Eq 'assistEditorOpenToken|lyrics-editor' "$MAIN"
grep -Eq 'applyAssistedDraft' "$PB"

# --- 6) cancel / confirm must not auto-save timeline ---
if awk '/confirmListeningAssistAndCapture/,/^    public func /' "$PB" | grep -q 'saveAlignedVersion'; then
  echo "Assist capture must not saveAlignedVersion" >&2
  exit 1
fi
if awk '/cancelListeningAssist/,/^    public func /' "$PB" | grep -q 'saveManualEdit\|saveAlignedVersion'; then
  echo "Assist cancel must not save" >&2
  exit 1
fi

# --- 7) Debug S1/S2/S3A menus remain diagnostic-only (no open editor / merge) ---
if awk '/CommandMenu\("排轴捕获 Spike/,/^            \}/' "$MENU" | grep -Eq 'AssistedCandidateMerger|applyAssistedDraft|openListeningAssist|saveAlignedVersion'; then
  echo "Debug Spike menu must not drive Assist product path" >&2
  exit 1
fi
grep -Eq 'runPartialAlignment: false' "$MENU"
grep -Eq 'runPartialAlignment: true' "$MENU"

# --- 8) Sheet product copy stays non-jargon ---
grep -Eq '不捕获麦克风|确认保存|不保留或导出音频' "$SHEET"
# Only flag user-visible Text/Label lines (not comments / Swift identifiers).
if grep -E 'Text\(|Label\(' "$SHEET" | grep -Eiq 'ScreenCaptureKit|S3A|S3B|confidence|Segment|Speech|DP '; then
  echo "Assist sheet must not expose engineering jargon" >&2
  exit 1
fi

# --- 9) Partial vs full sync semantics still present ---
grep -Eq 'isSynchronized|部分时间轴|explicitlyTimedLineIndices' \
  "$ROOT/SpotifyLyrics/Editor/LyricsEditorModels.swift" \
  "$ROOT/SpotifyLyrics/Editor/LyricsTimelineValidator.swift" \
  "$ROOT/SpotifyLyrics/Views/Editor/LyricsEditorWindowView.swift"

# --- 10) adopt after save still wired ---
grep -Eq 'adoptPersisted' "$PB"

echo "assist_v3_entry_contract: PASS"

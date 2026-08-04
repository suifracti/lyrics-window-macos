#!/usr/bin/env bash
# Assist MVP: entry, capture session, no auto-save, track-change drop
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PB="$ROOT/SpotifyLyrics/Services/PlaybackState.swift"
CANVAS="$ROOT/SpotifyLyrics/Views/Components/LyricsCanvasView.swift"
MAIN="$ROOT/SpotifyLyrics/Views/MainWindow/MainLyricsWindowView.swift"
OPS="$ROOT/SpotifyLyrics/Views/Components/CurrentSongOperationsView.swift"
SHEET="$ROOT/SpotifyLyrics/Views/Components/AssistExplainSheet.swift"
MERGE="$ROOT/SpotifyLyrics/Capture/AssistedCandidateMerger.swift"

grep -Eq 'presentListeningAssistExplanation|confirmListeningAssistAndCapture|cancelListeningAssist|invalidateAssistOnTrackChange' "$PB"
grep -Eq 'dismissListeningAssistExplanation' "$PB"
# DEBUG acceptance harness tokens (E2E only; not product UI)
grep -Eq 'assist_start|assist_cancel|assist_save|assist_mark|acceptanceAssistMark' "$PB"
grep -Eq 'canStartListeningAssist|AssistedCandidateMerger|AlignmentSessionGuard' "$PB"
# Product entry strings: canvas (classic) + current-song panel (V3) + sheet
grep -Eq '边听边排轴' "$CANVAS" "$OPS" "$SHEET"
# Single sheet host on main window
grep -Eq 'AssistExplainSheet' "$MAIN"
grep -Eq '不捕获麦克风|确认保存|不保留或导出音频' "$SHEET"
# Assist confirmListeningAssist must not call saveAlignedVersion
if awk '/confirmListeningAssistAndCapture/,/^    public func /' "$PB" | grep -q 'saveAlignedVersion'; then
  echo "Assist capture must not saveAlignedVersion" >&2
  exit 1
fi
grep -Eq 'invalidateAssistOnTrackChange' "$PB"
grep -Eq 'AssistedCandidateMerger.merge' "$PB"
# explaining must not be a permanent trap
grep -Eq 'assistPhase = \.idle|dismissListeningAssistExplanation' "$PB"
# No S3C / Whisper
if grep -Eiq 'whisper|demucs|spleeter|S3C' "$PB" "$SHEET" "$MERGE"; then
  echo "Assist must not introduce S3C/whisper" >&2
  exit 1
fi
echo "assist_session_contract: PASS"

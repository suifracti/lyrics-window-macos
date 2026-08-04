#!/usr/bin/env bash
# Assist MVP: editor mark / jump / partial save / keyboard
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ED="$ROOT/SpotifyLyrics/Views/Editor/LyricsEditorWindowView.swift"
SESS="$ROOT/SpotifyLyrics/Services/LyricsEditorSessionController.swift"
DRAFT="$ROOT/SpotifyLyrics/Editor/LyricsEditorModels.swift"

grep -Eq 'jumpToNextUntimed|markFocusedLineAtCurrentTime|assistAutoAdvance|下一条未排' "$ED"
grep -Eq 'onKeyPress\(\.space\)|keyboardShortcut\("z"' "$ED"
grep -Eq '建议|未排' "$ED"
grep -Eq 'nextUntimedLineID|timedNonBlankLineCount|untimedNonBlankLineCount' "$DRAFT"
grep -Eq 'confirmPartialSave|applyAssistedDraft|markLineAtPlayback|assistSuggestedLineIDs' "$SESS"
grep -Eq '部分时间轴' "$ED" || grep -Eq '部分时间轴' "$SESS" || grep -Eq '部分时间轴' "$ROOT/SpotifyLyrics/Editor/LyricsTimelineValidator.swift"

# Space is used for mark in editor (play uses button, not Space)
grep -Eq 'onKeyPress\(\.space\)' "$ED"

echo "assist_editor_contract: PASS"

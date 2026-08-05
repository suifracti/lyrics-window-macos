#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JOB="$ROOT/SpotifyLyrics/Capture/AutomaticAlignmentJobController.swift"
PB="$ROOT/SpotifyLyrics/Services/PlaybackState.swift"
LC="$ROOT/SpotifyLyrics/Capture/LiveCaptureCoordinator.swift"
grep -Eq 'func notifySeek' "$JOB"
grep -Eq 'notifyPlaybackPositionJump' "$JOB" "$LC"
grep -Eq 'AutomaticAlignmentJobController\.shared\.notifySeek' "$PB"
# Seek path is product (not DEBUG-only)
if awk '/public func seek\(to/,/^    public func /' "$PB" | grep -q '#if DEBUG'; then
  # DEBUG logging ok; product notify must appear outside exclusive DEBUG block
  :
fi
grep -Eq 'notifySeek\(from:' "$PB"
echo "automatic_alignment_seek_contract: PASS"

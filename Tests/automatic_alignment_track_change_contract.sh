#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JOB="$ROOT/SpotifyLyrics/Capture/AutomaticAlignmentJobController.swift"
PB="$ROOT/SpotifyLyrics/Services/PlaybackState.swift"
grep -Eq 'func notifyTrackChanged' "$JOB"
grep -Eq 'cancelCurrentJob|generation' "$JOB"
grep -Eq 'AutomaticAlignmentJobController\.shared\.notifyTrackChanged' "$PB"
# Late results must not cross identity
grep -Eq 'currentTrackIdentity\?\.stableKey == identity\.stableKey' "$JOB"
echo "automatic_alignment_track_change_contract: PASS"

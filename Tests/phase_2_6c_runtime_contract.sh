#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

grep -q "public let readingSession: ReadingSessionController" "$ROOT_DIR/SpotifyLyrics/Services/PlaybackState.swift"
grep -q "readingSession.project(onto: translated)" "$ROOT_DIR/SpotifyLyrics/Services/PlaybackState.swift"
grep -q "func selectNoReadingVersion" "$ROOT_DIR/SpotifyLyrics/Services/PlaybackState.swift"
grep -q "reading.preferences.v1" "$ROOT_DIR/SpotifyLyrics/Settings/AppSettingsStore.swift"
grep -q "isPinyinProjection" "$ROOT_DIR/SpotifyLyrics/Views/MainWindow/AppleMusicImmersiveV3WindowView.swift"
grep -q "preferences.showPinyin" "$ROOT_DIR/SpotifyLyrics/Views/MainWindow/AppleMusicImmersiveV3WindowView.swift"
grep -q "line.kanaText = nil" "$ROOT_DIR/SpotifyLyrics/Lyrics/ReadingSessionController.swift"
grep -q "readingSurfaceText" "$ROOT_DIR/SpotifyLyrics/Views/Components/LyricLineView.swift"
grep -q "AIReadingCandidateService" "$ROOT_DIR/SpotifyLyrics/Lyrics/ReadingSessionController.swift"
grep -q "aiCandidateOnly" "$ROOT_DIR/SpotifyLyrics/Lyrics/ReadingSessionController.swift"
! grep -Eq "Timer|DispatchSourceTimer|CADisplayLink" "$ROOT_DIR/SpotifyLyrics/Lyrics/ReadingSessionController.swift"
! grep -Eq "SPOTIFYLYRICS_DATABASE_PATH.*formal|defaultDatabaseURL.*reading" "$ROOT_DIR/SpotifyLyrics/Lyrics/ReadingSessionController.swift"

bash "$ROOT_DIR/Tests/phase_2_6b_engines_contract.sh"
echo "phase 2.6C runtime wiring contract passed"

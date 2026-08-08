#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
V3="$ROOT/SpotifyLyrics/Views/MainWindow/AppleMusicImmersiveV3WindowView.swift"

grep -q 'static func reading(for text: String, engineID: ReadingEngineID)' "$V3" || {
  echo "V3 reading cache must accept the selected Japanese engine" >&2
  exit 1
}
grep -q 'engineID.rawValue' "$V3" || {
  echo "V3 reading cache must include the engine in its cache key" >&2
  exit 1
}
grep -q 'settings.readingPreferences.japaneseEngineID' "$V3" || {
  echo "V3 lyric rows must honor the reading engine setting" >&2
  exit 1
}
grep -q 'JapaneseReadingPipeline.analyzeContextually' "$V3" || {
  echo "V3 contextual engine must use the contextual pipeline" >&2
  exit 1
}

echo "V3 Japanese engine contract passed"

#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# plain.txt / gt under local-real-songs must not be tracked
if git -C "$ROOT" ls-files | grep -Eiq 's4-5-real-song-gate/local-real-songs/.*/(plain\.txt|gt\.tsv)$'; then
  echo "copyrighted lyrics fixture tracked" >&2
  exit 1
fi
# tracked report must not dump long lyric blocks
if grep -R "ねえ　忘れたいのに" "$ROOT/docs/phase-2-11c-zero-operation-alignment/S4_5_REAL_SONG_GATE.md" 2>/dev/null; then
  echo "full lyric line leaked into report" >&2
  exit 1
fi
echo "copyrighted_lyrics_not_tracked_contract: PASS"

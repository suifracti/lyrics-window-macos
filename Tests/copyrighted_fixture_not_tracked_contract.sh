#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GI="$ROOT/.gitignore"
grep -Eq 's4-repeated-sections/local-real-songs|s4-repeated-sections/runs' "$GI"
# No tracked commercial wav under s4 local
if git -C "$ROOT" ls-files | grep -Eiq 's4-repeated-sections/local-real-songs/.*\.(wav|mp3|m4a)$'; then
  echo "Commercial audio must not be tracked" >&2
  exit 1
fi
echo "copyrighted_fixture_not_tracked_contract: PASS"

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VIEW="$ROOT_DIR/SpotifyLyrics/Views/Capsule/CapsuleLyricsView.swift"

# The reference pass requires a top-attached shoulder rather than a flat
# rectangle, a restrained spring for the island morph, and a short content
# cross-fade so the shared anchor does not pop between states.
grep -F 'topAttachedCornerRadius' "$VIEW" >/dev/null
grep -F '.spring(response: 0.32, dampingFraction: 0.86' "$VIEW" >/dev/null
grep -F '.transition(.opacity)' "$VIEW" >/dev/null

echo "capsule v4 reference motion contract passed"

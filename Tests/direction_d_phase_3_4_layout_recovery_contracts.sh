#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODEL_BIN="/tmp/direction-d-layout-recovery-contract-$$"
trap 'rm -f "$MODEL_BIN"' EXIT

echo "======================================================"
echo "Lyric Island Phase 3.4 Layout Recovery Contracts"
echo "======================================================"

swiftc "$ROOT/Tests/DirectionDLayoutRecoveryModel.swift" -o "$MODEL_BIN"
"$MODEL_BIN"

grep -q 'case directionDV4 = "directionD"' "$ROOT/SpotifyLyrics/Design/MainWindowLayoutStyle.swift"
echo "[PASS] main-window V4 has an independent raw layout value"
grep -q 'mainWindow.directionD.v4' "$ROOT/SpotifyLyrics/Design/PresentationCatalog.swift"
echo "[PASS] main-window V4 has an independent catalog stable ID"
grep -q 'layoutStyle == \.directionDV4' "$ROOT/SpotifyLyrics/Views/MainWindow/MainLyricsWindowView.swift"
echo "[PASS] V4 is selected without entering the V3 branch"
grep -q 'mainWindow.appleMusicImmersiveV3.v3' "$ROOT/SpotifyLyrics/Design/PresentationCatalog.swift"
echo "[PASS] V3 catalog identity remains present"
grep -q 'DirectionDDesignTokens.Spacing.windowSmall' "$ROOT/SpotifyLyrics/Views/Components/DirectionD/DirectionDMainWindowView.swift"
echo "[PASS] V4 keeps a bounded technical envelope"
grep -q 'directionDReadingTargetID' "$ROOT/SpotifyLyrics/Views/Components/DirectionD/DirectionDMainWindowView.swift"
echo "[PASS] current line scrolls through a stable row-derived target ID"
if grep -q 'frame(height: max(' "$ROOT/SpotifyLyrics/Views/Components/DirectionD/DirectionDMainWindowView.swift" || grep -q 'directionDScrollAnchorID' "$ROOT/SpotifyLyrics/Views/Components/DirectionD/DirectionDMainWindowView.swift"; then
    echo "[FAIL] old large active-row spacer anchor remains"
    exit 1
fi
grep -q 'frame(height: 1)' "$ROOT/SpotifyLyrics/Views/Components/DirectionD/DirectionDMainWindowView.swift"
echo "[PASS] active-row marker is bounded and cannot create a lyric gap"

echo "Summary: layout recovery contracts PASS"

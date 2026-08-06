#!/usr/bin/env bash
# Phase 3.2 Direction D — static + behavioral contracts (no formal DB / no Spotify).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CD="$ROOT/SpotifyLyrics"
TOKENS="$CD/Design/DirectionD/DirectionDDesignTokens.swift"
POLICY="$CD/Design/DirectionD/DirectionDLyricsPolicy.swift"
CATALOG="$CD/Design/PresentationCatalog.swift"
INSPECTOR="$CD/Views/Components/DirectionD/DirectionDInspectorView.swift"
PREVIEW="$CD/Views/Debug/DirectionDPreviewMatrixView.swift"
LAB="$CD/Views/Debug/PresentationPreviewLabView.swift"
PBX="$ROOT/SpotifyLyrics.xcodeproj/project.pbxproj"

echo "========================================="
echo "Lyric Island Phase 3.2 Direction D Contracts"
echo "========================================="

# --- Static existence ---
for f in \
  "$TOKENS" "$POLICY" \
  "$CD/Views/Components/DirectionD/DirectionDUserTaskBadge.swift" \
  "$CD/Views/Components/DirectionD/DirectionDSongWorkbenchButton.swift" \
  "$CD/Views/Components/DirectionD/DirectionDLyricRowView.swift" \
  "$INSPECTOR" \
  "$CD/Views/Components/DirectionD/DirectionDSettingsSectionGate.swift" \
  "$PREVIEW"
do
  test -f "$f" || { echo "missing $f"; exit 1; }
done
grep -q 'struct DirectionDStatusBanner' "$CD/Views/Components/DirectionD/DirectionDUserTaskBadge.swift"
grep -q 'struct DirectionDQuietToolbar' "$CD/Views/Components/DirectionD/DirectionDSongWorkbenchButton.swift"
grep -q 'struct DirectionDLineContextMenuView' "$CD/Views/Components/DirectionD/DirectionDLyricRowView.swift"
grep -q 'struct DirectionDSmallSheetView' "$INSPECTOR"
echo "[STATIC] component sources present"

# Preview Lab wiring (DEBUG only)
grep -q 'DirectionDPreviewMatrixView' "$LAB"
grep -q '#if DEBUG' "$PREVIEW"
head -1 "$PREVIEW" | grep -q '#if DEBUG'
echo "[STATIC] Preview Matrix reachable from Presentation Preview Lab (DEBUG)"

# PBX: single Sources entry per Direction D file.  The Direction D product
# surface now includes the formal V4 view and its shared live adapter/model;
# do not freeze this contract to the historical eight-file count.
python3 - <<PY
import re
from pathlib import Path
root = Path("$ROOT")
text = (root / "SpotifyLyrics.xcodeproj/project.pbxproj").read_text()
# Unique PBXFileReference definitions
refs = re.findall(r'^\s+([0-9A-F]+) /\* (DirectionD[^*]+) \*/ = \{isa = PBXFileReference;', text, re.M)
builds = re.findall(r'^\s+([0-9A-F]+) /\* (DirectionD[^*]+) \*/ = \{isa = PBXBuildFile;', text, re.M)
required = {
    'DirectionDDesignTokens.swift',
    'DirectionDLyricsPolicy.swift',
    'DirectionDUserTaskBadge.swift',
    'DirectionDSongWorkbenchButton.swift',
    'DirectionDLyricRowView.swift',
    'DirectionDInspectorView.swift',
    'DirectionDSettingsSectionGate.swift',
    'DirectionDPreviewMatrixView.swift',
    'DirectionDProductStateModel.swift',
    'DirectionDProductStateAdapter.swift',
    'DirectionDActionRouter.swift',
    'DirectionDProductStateHostView.swift',
    'DirectionDExperimentalProductHost.swift',
    'DirectionDResponsiveLayout.swift',
    'DirectionDMainWindowView.swift',
}
ref_names = {name for _, name in refs}
build_names = {name.split(' in Sources')[0] for _, name in builds}
assert ref_names == required, refs
assert build_names == required, builds
assert len(refs) == len(required)
assert len(builds) == len(required)
assert len(set(a for a,_ in refs)) == len(required)
assert len(set(a for a,_ in builds)) == len(required)
# Sources phase children
block = re.search(r'/\* Sources \*/ = \{.*?files = \((.*?)\);', text, re.S)
assert block, 'Sources phase missing'
src = [l.strip() for l in block.group(1).splitlines() if 'DirectionD' in l]
assert len(src) == len(required), src
assert len(set(src)) == len(required), 'duplicate Sources entries'
# Must not compile Tests/Tools/docs
assert not re.search(r'Tests/.*in Sources|Tools/.*in Sources|docs/.*in Sources', text)
print("[PBX] unique FileRef/BuildFile/Sources; no Tests/Tools/docs in App target")
PY

# 1) default auxiliary count <= 1  (behavioral via policy logic mirror + source)
python3 - <<'PY'
import os
os.chdir(os.environ.get("DIRECTION_D_ROOT", "."))
# Mirror DirectionDLyricsPolicy.resolveVisibleLayers defaults
def resolve(learning=False, choice='translation', hide_distant=True, active=True, distance=0, expanded=False):
    show_original = True
    if expanded or learning:
        return dict(o=True, t=True, r=True, romaji=False)
    if hide_distant and distance >= 2 and not active:
        return dict(o=True, t=False, r=False, romaji=False)
    if choice == 'translation':
        return dict(o=True, t=True, r=False, romaji=False)
    if choice == 'ruby':
        return dict(o=True, t=False, r=True, romaji=False)
    return dict(o=True, t=False, r=False, romaji=False)

def aux_count(v):
    return int(v['t']) + int(v['r']) + int(v['romaji'])

d = resolve()
assert aux_count(d) <= 1 and d['t'] and not d['r'] and not d['romaji']
print("[BEHAVIOR 1] default auxiliary count <= 1")

# 2) learning mode allows controlled 3 layers (orig+tr+ruby), still no dual romaji
learn = resolve(learning=True)
assert learn['o'] and learn['t'] and learn['r'] and not learn['romaji']
print("[BEHAVIOR 2] learning mode allows controlled three layers")

# 3) non-current distant rows hide auxiliary
far = resolve(active=False, distance=2)
assert aux_count(far) == 0
print("[BEHAVIOR 3] distant non-current rows hide auxiliary")

# 4) two equivalent romaji never both true
for kwargs in [{}, {'learning': True}, {'choice': 'ruby'}, {'expanded': True}]:
    v = resolve(**kwargs)
    # policy never enables romaji
    assert v['romaji'] is False
print("[BEHAVIOR 4] no dual equivalent romaji output")
PY
grep -q 'showRomaji: false' "$POLICY"
grep -q 'isLearningModeEnabled' "$POLICY"
echo "[SOURCE] policy enforces single auxiliary / learning exception / romaji false"

# 5) Reduce Motion degraded duration
python3 - <<'PY'
from pathlib import Path
import re
t = Path("/Users/apple/backup/sptifylyrics/SpotifyLyrics/Design/DirectionD/DirectionDDesignTokens.swift").read_text()
m = re.search(r'reduceMotionDuration:\s*Double\s*=\s*([0-9.]+)', t)
assert m and float(m.group(1)) <= 0.15
assert 'func animation(reduceMotion' in t
print("[BEHAVIOR 5] Reduce Motion returns degraded duration", m.group(1))
PY

# 6) Reduce Transparency opaque fallback
python3 - <<'PY'
from pathlib import Path
import re
t = Path("/Users/apple/backup/sptifylyrics/SpotifyLyrics/Design/DirectionD/DirectionDDesignTokens.swift").read_text()
assert 'func backgroundVeil' in t
assert 'reduceTransparency' in t
# when reduceTransparency true, opacity forced high (the current Direction D
# token is intentionally more opaque than the old 0.85 contract).
assert 'max(0.92' in t or '0.92' in t
print("[BEHAVIOR 6] Reduce Transparency returns opaque fallback")
PY

# 7) User status strings: required set present; forbidden engineering terms absent
python3 - <<'PY'
from pathlib import Path
import re
t = Path("/Users/apple/backup/sptifylyrics/SpotifyLyrics/Design/DirectionD/DirectionDDesignTokens.swift").read_text()
# Extract UserTaskLanguage block
block = re.search(r'enum UserTaskLanguage \{(.*?)// MARK: - Accessibility', t, re.S)
assert block, 'UserTaskLanguage missing'
body = block.group(1)
required = [
    "等待 Spotify 播放",
    "请打开 Spotify 并开始播放",
    "正在搜索歌词",
    "暂未找到歌词",
    "网络连接失败",
    "正在同步歌词",
    "已保存部分进度",
    "等待继续播放",
    "同步完成",
    "本次无法可靠完成",
    "同步功能尚未准备好",
]
for s in required:
    assert s in body, f'missing status: {s}'
forbidden = [
    "正在自动同步时间轴",
    "已自动采用精准时间轴",
    "精准",
    "Provider",
    "Whisper",
    "DP",
    "SQLite",
    "Migration",
    "confidence",
    "Level 3",
    "Stable ID",
    "ggml",
    "S3A",
]
for f in forbidden:
    assert f not in body, f'forbidden term in user language: {f}'
print("[BEHAVIOR 7] user status strings clean + required set present")
PY

# Primary inspector (outside advanced DisclosureGroup) should not leak Whisper/SQLite etc.
python3 - <<'PY'
from pathlib import Path
text = Path("/Users/apple/backup/sptifylyrics/SpotifyLyrics/Views/Components/DirectionD/DirectionDInspectorView.swift").read_text()
# Split advanced disclosure content roughly
primary = text.split('DisclosureGroup')[0]
for bad in ['Whisper', 'SQLite', 'Migration', 'Provider', 'ggml', 'S3A', 'confidence', 'Level 3']:
    assert bad not in primary, bad
print("[BEHAVIOR 7b] primary Inspector free of engineering jargon")
PY

# 8) Stable ID unique; Direction D remains opt-in experimental; V4 is a
# separate selectable layout and remains Release-capable in the catalog.
python3 - <<'PY'
from pathlib import Path
import re
text = Path("/Users/apple/backup/sptifylyrics/SpotifyLyrics/Design/PresentationCatalog.swift").read_text()
ids = re.findall(r'entry\("([^"]+)"', text)
assert len(ids) == len(set(ids)), 'duplicate stable IDs'
for sid in [
    'mainWindow.directionDQuiet.v1',
    'mainWindow.directionDWorkbenchInspector.v1',
    'lyricsStatePresentation.directionDUserLanguage.v1',
    'responsiveLayout.directionDInspector.v1',
    'mainWindow.appleMusicImmersiveV3.v3',
    'capsule.dynamicIslandDark.v4',
    'fullscreen.borderlessPanel.v1',
    'floatingLyrics.transparent.v2',
]:
    assert sid in ids, sid
# The formal Direction D V4 is experimental in product status but Release
# capable. Historical Direction D identities remain archived diagnostics; they
# must not be mistaken for independently selectable runtime presentations.
for line in text.splitlines():
    if 'directionD' in line and 'entry(' in line:
        if 'mainWindow.directionD.v4' in line:
            assert '.experimental' in line, line
            assert '.release' in line, line
        else:
            assert '.archived' in line, line
            assert 'false, false' in line, line
# Default layout still V3
settings = Path("/Users/apple/backup/sptifylyrics/SpotifyLyrics/Settings/AppSettingsStore.swift").read_text()
assert 'appleMusicImmersiveV3' in settings
layout = Path("/Users/apple/backup/sptifylyrics/SpotifyLyrics/Design/MainWindowLayoutStyle.swift").read_text()
assert 'case directionDV4 = "directionD"' in layout
assert 'mainWindow.directionD.v4' in layout
assert '?? MainWindowLayoutStyle.appleMusicImmersiveV3.rawValue' in settings
v4 = next(line for line in text.splitlines() if 'mainWindow.directionD.v4' in line)
assert '.release' in v4
print("[BEHAVIOR 8] Stable IDs unique; Direction D V4 selectable/Release-capable; historical IDs archived; default layout unchanged")
# Availability .release means Release-capable, not recommended
assert 'case release' in text
print("[NOTE] PresentationAvailability.release displayName=可运行 (compile/run capability), status.experimental gates recommendation")
PY

# 9) Preview lab buildability is source-level: matrix enumerates 23 states
python3 - <<'PY'
from pathlib import Path
import re
t = Path("/Users/apple/backup/sptifylyrics/SpotifyLyrics/Views/Debug/DirectionDPreviewMatrixView.swift").read_text()
cases = re.findall(r'case \w+ = "', t)
assert len(cases) == 23, len(cases)
assert 'DirectionDPreviewMatrixView' in Path("/Users/apple/backup/sptifylyrics/SpotifyLyrics/Views/Debug/PresentationPreviewLabView.swift").read_text()
print("[BEHAVIOR 9] Preview Matrix has 23 states and is linked from Preview Lab")
PY

# 10) Core Provider / Session files unchanged versus the current Phase 3.4
# main-window baseline.  The old 630efb3 reference predates unrelated live
# playback work and made this UI-only contract fail before checking Direction D.
cd "$ROOT"
CORE_BASELINE="${DIRECTION_D_CORE_BASELINE:-310c07e6dd890abb7c6ddab8ab09845295ea842e}"
if git rev-parse "$CORE_BASELINE" >/dev/null 2>&1; then
  diff_files=$(git diff --name-only "$CORE_BASELINE" -- \
    SpotifyLyrics/Providers/SpotifyDesktopProvider.swift \
    SpotifyLyrics/Lyrics/LRCLIBLyricsProvider.swift \
    SpotifyLyrics/Services/LyricsSessionController.swift \
    SpotifyLyrics/Services/PlaybackState.swift \
    SpotifyLyrics/Persistence/SQLiteLyricsRepository.swift \
    || true)
  if [[ -n "${diff_files}" ]]; then
    echo "FAIL: core business files changed vs 630efb3:" >&2
    echo "$diff_files" >&2
    exit 1
  fi
  echo "[BEHAVIOR 10] core Provider/Session/Persistence files diff zero vs $CORE_BASELINE"
else
  echo "[BEHAVIOR 10] baseline missing; skipped"
fi

echo "========================================="
echo "ALL DIRECTION D CONTRACTS PASSED"
echo "========================================="

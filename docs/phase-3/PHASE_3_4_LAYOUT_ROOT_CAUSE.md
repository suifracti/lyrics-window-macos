# Phase 3.4 Layout Root Cause and Version Boundary

## Scope

This note records the layout causes found before the Direction D V4 recovery
work. `mainWindow.appleMusicImmersiveV3.v3` remains the existing V3
presentation and remains the default. Direction D is a separate, switchable
V4 presentation; it does not rename, replace, or copy the V3 implementation.

## Version boundary audit

Before this correction, the maintained Direction D view was reachable through
DEBUG-only `mainWindow.directionDQuiet.v1` / `mainWindow.directionDWorkbenchInspector.v1`
identities and the normal main-window selection could only resolve the three
V3/classic layout values. The catalog therefore described Direction D but did
not expose it as a formal main-window V4 choice.

The corrected boundary is:

- `mainWindow.appleMusicImmersiveV3.v3` → existing V3, unchanged and default.
- `mainWindow.directionD.v4` → formal V4 Direction D layout, independently
  selectable and persistable.
- `mainWindow.directionDQuiet.v1` and
  `mainWindow.directionDWorkbenchInspector.v1` → retained as historical
  Direction D internal presentation identities for compatibility and debug
  evidence; they are not aliases for V3 and are not the formal V4 selection.

## Layout root causes

### 1. Wide left content falls toward the bottom

`DirectionDMainWindowView.renderWideLayout` wrapped the left player group in
an outer `VStack` with `Spacer` values and then gave that stack an infinite
height with a top-leading alignment. The artwork, metadata, progress and
controls consequently participated in the parent’s greedy vertical proposal
instead of being placed from a bounded vertical budget. At some heights the
group was pushed down or compressed near the bottom.

The recovery uses one bounded left-column geometry budget and centers one
complete player group inside it. It does not use bottom alignment or a second
player group.

### 2. Controls and time labels clip

The old left column combined a near-maximum artwork size, vertical padding,
metadata spacing, slider labels and controls without reserving their total
height. The controls were the first content to be compressed or clipped.

The recovery derives artwork size from the available height after reserving
metadata, progress and control space, with a hard upper bound. The group is
allowed to shrink before controls are removed.

### 3. Wide current line is not held near the reading anchor

The lyric canvas inserted a large clear view *after every active line* and
scrolled to that synthetic view. This made the target depend on an artificial
post-row gap rather than on the stable lyric row itself. Toolbars, banners and
changing row heights then moved the visual target unpredictably. The recovered
path keeps one continuous lyric stream and uses only a one-point, view-only
marker after the active row so macOS lazy layout has a concrete target; it does
not render a second hero or carry a second line model.

The recovery keeps one continuous lyric stream, scrolls directly to the active
row ID, and uses only edge insets for first/last-row reachability. No spacer is
inserted between lyric rows.

### 4. First Love shows a large gap between lyric blocks

The same active-row post-spacer was proportional to the canvas height. When a
line changed, that proportional block remained in the document and appeared
as a large blank gap. This is a layout artifact, not missing lyric data. The
replacement marker is one point and cannot create a visual paragraph gap.

### 5. Small Sheet has a gray strip on the left

`DirectionDInspectorView` imposed a fixed 360-point width internally while the
small bottom sheet wrapped it in a wider, centered container. The sheet and
the inspector therefore had different width contracts, exposing the parent
background as a side strip.

The recovery moves width ownership to the callers: wide Inspector keeps its
fixed side-column width, while Small Sheet owns a bounded full-width sheet and
the Inspector fills it.

### 6. Lyrics Focus and duplicate-stream audit

The formal `DirectionDMainWindowView` did not intentionally render a separate
hero lyric list; its focus path and wide path both use `renderLyricsSurface`.
The visible gap was caused by the same synthetic active-row spacer. The older
`DirectionDProductStateHostView` and Preview Matrix are separate experimental
surfaces and are not the V4 product path. The recovery keeps the formal V4
path to one lyric stream and does not merge or alter V3’s lyric surface.

### 7. Small toolbar overflow

The small top bar forced the full quiet toolbar with its normal horizontal
padding after the title and play button. Long title/artist content could leave
no width for the toolbar, so the right edge was clipped.

The recovery gives the small toolbar an explicit compact presentation with
fixed hit targets and icon-only controls. It does not change the toolbar’s
commands or create another state source.

## Non-goals

This recovery does not modify Provider behavior, Track Identity, the shared
PlaybackState, LyricsSession, current-line calculation, database schema,
automatic alignment, the V3 view, or the capsule V4 implementation.

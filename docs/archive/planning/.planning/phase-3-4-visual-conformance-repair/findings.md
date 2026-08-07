# Findings — Phase 3.4 Visual Conformance Repair

## Source of truth
- User attachment: frozen Direction D visual requirements
- docs/phase-3/PHASE_3_1_FINAL_DIRECTION.md
- docs/phase-3/PHASE_3_1_VISUAL_DIRECTIONS.md
- docs/phase-3/phase-3-1-mockups/index.html
- docs/phase-3/PHASE_3_2_DESIGN_SYSTEM.md
- docs/phase-3/phase-3-3-product-states/REFERENCE_NOTES.md
- docs/phase-3/phase-3-4-live-playback-acceptance/

## Decisions
- Preserve shared live projection and scroll coordinator.
- Use existing artwork/backdrop pipeline; no second color pipeline.
- Keep Direction D experimental and product title user-facing.

## Gap matrix
- The current real Direction D screenshot confirms the visible gaps: `Direction D Main Window` title, persistent blue focus ring around workbench button, flat navy backdrop, 180pt cover with large lower-left void, distant lyric blur, saturated cyan Ruby, and card/badge-heavy Inspector.
- The existing V3/fullscreen backdrop already uses `AppleMusicImmersiveV3BackdropCache`; Direction D can consume that existing track-bound presentation without a new loader or palette cache.

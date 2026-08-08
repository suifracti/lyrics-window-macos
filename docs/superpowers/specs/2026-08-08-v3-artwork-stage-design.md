# V3 Artwork Presentation Design

## Status

Approved by the user on 2026-08-08. This extends V3 only. Direction D / V4 remains untouched.

## Goal

Give V3 three visibly different, reversible artwork compositions instead of treating a blur change as a new background:

1. **Album Ambient** — foreground cover plus abstract album color field (current recommended behavior).
2. **Artwork Stage** — no foreground cover; the recognizable artwork becomes the visual stage, with edge extension, a controlled full-art plane, and a lyrics-side readability veil.
3. **Classic Wallpaper** — foreground cover plus the legacy large blurred crop.

## Stable selection and migration

Add `V3ArtworkPresentation` with stable persisted IDs:

- `v3ArtworkPresentation.ambient.v1`
- `v3ArtworkPresentation.stage.v1`
- `v3ArtworkPresentation.classic.v1`

Existing `v3AmbientBackdropEnabled == true` migrates to Ambient. `false` migrates to Classic. The legacy Boolean remains readable during migration but the new enum becomes the single runtime source.

## Artwork Stage composition

- A low-frequency artwork derivative fills the window and extends edge color.
- A recognizable full-resolution artwork plane uses aspect-fit, not an uncontrolled full-window crop.
- The artwork plane is aligned opposite the lyrics reading area and feathered into the color field; it must not look like a second floating card.
- The foreground `ArtworkView` is omitted only in Stage.
- Track title, artist/album, progress, and transport remain in a compact bottom dock on the artwork side.
- Search, no-lyrics, and version-selection states retain their functional foreground surfaces.
- The lyrics-side veil is independent of artwork blur and maintains readable white text on bright covers.

## Controls

The V3 tuning popover exposes a segmented presentation picker. Blur remains live and mode-aware:

- Ambient: controls low-frequency diffusion.
- Stage: controls stage-detail softening while retaining the full composition.
- Classic: controls legacy crop blur.

Artwork position and scale remain live. In Stage they control the integrated artwork plane. In Ambient and Classic they control the foreground artwork/light anchor as today.

## V1 / V2 boundary

Do not delete or rewrite V1/V2 in this change. V3 already owns responsive wide/medium/small/lyrics-focus projections. A later compatibility cleanup may expose one user-facing Classic family while retaining old stable IDs. V4 is not modified.

## Acceptance

- All three modes switch immediately and persist across relaunch.
- Ambient and Classic remain visually and architecturally unchanged except for enum routing.
- Stage shows no duplicate foreground cover.
- Stage preserves substantially more of the complete cover than Classic on square art.
- Bright, dark, monochrome, portrait, illustration, and missing-artwork cases remain readable.
- Debug build and V3 contracts pass.

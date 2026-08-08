# V3 Artwork Presentation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use test-driven-development and executing-plans.

**Goal:** Add three persistent V3 artwork presentations—Ambient, Artwork Stage, and Classic—with a working switch and a coverless stage composition.

**Architecture:** Replace the legacy ambient boolean with a stable enum and migrate the stored preference. The shared backdrop renders the selected strategy. Stage keeps recognizable artwork integrated into the background, removes the duplicate foreground cover, and leaves metadata/progress/transport as a compact dock.

**Tech Stack:** SwiftUI, AppKit image rendering, AppSettingsStore, shell contract tests.

## Tasks

1. Add failing contracts for stable mode IDs, migration, picker wiring, and stage foreground-cover suppression.
2. Add the presentation enum and settings migration.
3. Implement Ambient, Stage, and Classic rendering in the shared V3 backdrop.
4. Adapt V3 track layout for Stage while preserving existing responsive layouts.
5. Replace the boolean toggle with a segmented presentation picker.
6. Run V3 contracts, Debug build, and visually inspect representative bright, portrait, and illustration covers.

## Acceptance

- Switching modes changes actual rendering and persists.
- Stage shows one recognizable artwork composition, not a foreground cover plus wallpaper duplicate.
- Ambient and Classic preserve the existing blur slider semantics.
- V4 and its files are untouched.

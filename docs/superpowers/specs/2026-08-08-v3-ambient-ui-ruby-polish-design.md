# V3 Ambient Background, Ruby, and Track Controls Design

## Scope

This work keeps Apple Music Immersive V3 as the only delivery surface. It does not modify Direction D/V4, providers, playback state, SQLite, Xcode targets, or project generation.

The user approved the visual direction represented by `/Users/apple/.codex/generated_images/019fd5b5-08e4-7ec3-8bce-c9446b4f9b91/exec-882d2ba7-23d7-44e6-92ec-6b8a4b20092e.png`.

## 1. Album ambient background

- The foreground artwork remains the only recognizable cover.
- The new default backdrop derives color temperature, low-frequency light, and subtle grain from the album without showing a recognizable face, character outline, text, or duplicate cover.
- Bright covers are luminance-clamped so the window never becomes white-on-white.
- The lyrics side receives a directional graphite veil; the cover side retains gentle album-colored illumination.
- The existing blur control remains reactive, but controls diffusion of the ambient texture rather than exposing a sharp giant cover.
- A persistent `v3AmbientBackdropEnabled` switch defaults to on. Turning it off restores the exact legacy enlarged-artwork renderer.
- Track-bound caching and transitions remain; playback time is not added to the cache key.

## 2. Repeated-kanji ruby correction

MeCab parses `手手手手` as `テ + シュ + シュ + シュ` because later identical tokens are classified as suffix nouns. For a consecutive run of the same single-Han surface and lemma, if the first token has a normal reading and later tokens are suffix classifications, the later tokens inherit the first reading. This is a morphology repair rule, not a hard-coded replacement for `手`.

Provider-official kana remains authoritative. Unknown readings continue to fail closed.

## 3. V3 track presentation

- Keep title as the strongest metadata line.
- Render artist and album on one line with white hierarchy rather than low-contrast blue-gray; use a subtle separator and preserve clickability.
- Use familiar SF Symbols for previous, play/pause, and next.
- Give the primary play/pause action a thin material circular surface. Side controls remain quieter and reveal a subtle material hover state.
- Use a thin progress track with a clear leading fill, a larger invisible hit target, and a thumb that appears on hover/drag.
- Add concise macOS hover help.
- Do not wrap metadata in another permanent glass card.

These decisions follow Apple's guidance to use familiar symbols, reserve material for interactive hierarchy, keep controls predictable, and use a clearly filled leading slider track:

- https://developer.apple.com/design/human-interface-guidelines/materials
- https://developer.apple.com/design/human-interface-guidelines/buttons
- https://developer.apple.com/design/human-interface-guidelines/sliders
- https://developer.apple.com/design/human-interface-guidelines/playing-audio

## Acceptance

- New ambient background is the default and the legacy renderer can be restored immediately with one switch.
- `0/25/60/100` background values are visibly distinct without revealing a giant sharp artwork crop.
- White, monochrome, portrait, illustration, warm, and cool artwork preserve foreground readability.
- `手手手手` produces `てててて` and existing ruby contracts remain green.
- Artist and album remain readable on warm and light backgrounds; progress and transport remain seekable/clickable and keyboard-accessible.


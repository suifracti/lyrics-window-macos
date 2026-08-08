# Japanese Context Reading Correction Design

## Status

Approved by the user on 2026-08-08.

## Problem

IPADIC parses `満を持して` as the personal name `ミツル` followed by `を 持 し て`, producing incorrect ruby. The current `JapaneseContextualReadingEngine` does not perform contextual disambiguation; it runs the same per-line pipeline as dictionary v1 and only changes the context hash/source label.

## Decision

Context v2 becomes a deterministic phrase-aware layer over morphology. AI remains optional and candidate-only; it is not called during rendering or automatic playback.

## Phrase-aware correction

Add a focused contextual resolver that:

- Receives the complete lyric line and MeCab tokens.
- Matches known multi-token expressions before token readings become display ruby.
- Rewrites only the ambiguous morphology token readings, preserving original surface offsets and all unaffected tokens.
- Starts with `満を持して`: `満 -> マン`; existing particle and `持/し/て` readings remain morphology-derived, yielding display kana `まんおじして` under the app's lyric-particle convention and ruby `まん` above `満`, `じ` above `持`.
- Is extensible through explicit phrase rules and user dictionary corrections; it never replaces all occurrences of a single kanji globally.

## Engine distinction

- Dictionary v1 remains raw MeCab/IPADIC plus existing safety normalization.
- Context v2 applies phrase-aware corrections and uses nearby/full-line context in its version hash.
- V3's local ruby cache includes the selected engine ID in its key and routes through the selected engine behavior, so changing the setting has visible effect without restarting.

## Confidence and AI

- A recognized deterministic phrase rule is high confidence and auto-adoptable.
- Proper-name readings outside a recognized phrase remain lower confidence.
- AI may later propose a corrected version only when explicitly enabled; it must be previewed/adopted and never silently overwrite original text or a locked reading.

## Acceptance

- Context v2 reads `満を持して` with `まん` over `満`, not `みつる`.
- Dictionary v1 continues to expose the raw IPADIC result for comparison.
- `手手手手 -> てててて` remains correct.
- No whole-sentence kana line is rendered as ruby; ruby remains aligned only to Han spans.
- Switching reading engines invalidates/rekeys the V3 local cache and visibly changes the result.
- Reading and V3 ruby contracts pass.

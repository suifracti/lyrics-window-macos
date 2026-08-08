# Japanese Context Reading Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use test-driven-development and executing-plans.

**Goal:** Make Context Reading v2 genuinely context-sensitive and render `満を持して` with `まん` above `満`, while Dictionary Reading v1 remains the raw local morphology baseline.

**Architecture:** Add a deterministic, token-aligned phrase resolver after local morphology and before ruby construction. Route both the reading engine registry and V3's synchronous cache through the selected engine ID; cache by engine plus text.

**Tech Stack:** Swift 5.9, MeCab bridge, shell/Swift contract tests.

## Tasks

1. Extend the Japanese reading contract with `満を持して` and prove the contextual path is missing.
2. Add an extensible contextual phrase-rule stage to `JapaneseReadingPipeline` without changing the dictionary path.
3. Route `JapaneseContextualReadingEngine` to the contextual pipeline.
4. Make V3 honor `japaneseEngineID` and include it in the cache key.
5. Run Japanese reading, engine, and V3 contracts.

## Acceptance

- Context v2 produces `まん` only above `満` in `満を持して`.
- Dictionary v1 remains the uncorrected local dictionary baseline.
- V3 engine selection visibly changes the path used.
- Existing repeated-kanji ruby behavior remains intact.

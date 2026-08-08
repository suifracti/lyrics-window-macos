# Japanese Repeated Ruby Repair Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render the repeated lyric `手手手手` as `てててて` without hard-coding a character-wide dictionary exception.

**Architecture:** Normalize only consecutive identical single-Han morphology tokens when the first token is a normal lexical token and later identical tokens are suffix classifications with the same lemma. Provider-official kana and all existing unknown/fail-closed behavior remain unchanged.

**Tech Stack:** Swift, MeCab/IPADIC, existing executable contracts.

## Global Constraints

- Do not change Provider payloads or persisted lyric versions.
- Do not globally force `手` to one reading.
- Existing Japanese and ruby contracts must remain green.

---

### Task 1: Repair repeated suffix readings

**Files:**
- Modify: `Tests/japanese_reading_contract.swift`
- Modify: `SpotifyLyrics/Lyrics/JapaneseReadingPipeline.swift`

**Interfaces:**
- Consumes: `[JapaneseMorphologyToken]`
- Produces: normalized morphology readings before `JapaneseReadingToken` projection

- [ ] **Step 1: Add the failing regression**

Add `JapaneseReadingPipeline.analyze(originalText: "手手手手")` and assert `kanaText == "てててて"` plus four ruby tokens with reading `て`.

- [ ] **Step 2: Run and verify RED**

Run: `bash Tests/japanese_reading_contract.sh`

Expected: FAIL with current `てしゅしゅしゅ` output.

- [ ] **Step 3: Add the minimal morphology normalization**

Normalize later suffix tokens only when surface, lemma, and single-Han shape match the immediately preceding repeated run's lexical head. Preserve token boundaries and parts of speech.

- [ ] **Step 4: Verify GREEN**

Run:

```bash
bash Tests/japanese_reading_contract.sh
bash Tests/ruby_layout_contract.sh
bash Tests/v3_local_ruby_priority_contract.sh
```

Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add SpotifyLyrics/Lyrics/JapaneseReadingPipeline.swift Tests/japanese_reading_contract.swift
git commit -m "fix(reading): normalize repeated kanji suffix readings"
```

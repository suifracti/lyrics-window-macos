# Phase 3.4 Visual Conformance Repair

## Goal
根据冻结 Direction D 规范，对真实 Direction D 主窗口进行纯视觉修复，并产出 READY FOR USER REVIEW 证据；不改变播放、歌词身份、Provider、数据库或 current-line 业务逻辑。

## Phases
- [complete] 1. Read frozen docs and write gap matrix
- [in_progress] 2. Audit current Direction D visual code and isolate minimal fixes
- [pending] 3. Implement quiet toolbar/title/background/left pane/lyrics/inspector refinements
- [pending] 4. Add structural visual contracts and build with temporary database
- [pending] 5. Capture real Spotify evidence and write before/after + review candidate report
- [pending] 6. Commit changes and stop before Phase 3.5

## Guardrails
- Do not modify Provider, LyricsSearchManager, Track Identity, schema, auto-alignment, current-line algorithm, playback commands, or create parallel color/scroll pipelines.
- Do not make Direction D default.
- Use real Spotify songs for product screenshots; no preview fixture as product evidence.
- Formal database must not be opened.

## Errors Encountered
| Error | Attempt | Resolution |
|---|---|---|

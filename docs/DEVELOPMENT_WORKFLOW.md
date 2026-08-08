# Development Workflow

This document defines the durable repository workflow. Product direction and stage priority come from the latest top-level Craft execution board; exact source identity comes from Git.

## Repository layout

Tracked project files stay in the formal root:

```text
SpotifyLyrics/                 Swift and SwiftUI source
SpotifyLyrics.xcodeproj/       Xcode project
Tests/                         Shell contracts and test sources
Tools/                         Deliberate research and validation tools
Scripts/                       Repeatable project scripts
docs/                          Current documentation, evidence, research, and archive
README.md                      Short project entry point
AGENTS.md                      AI handoff rules
LICENSE                        Repository usage rights
docs/STATUS.md                 Honest implementation and maturity snapshot
docs/SUBMISSION_BASELINE.md    Commit and handoff verification checklist
generate_xcodeproj.py          Legacy generator; do not run without explicit authorization
```

Do not create additional top-level project directories for local state, builds, backups, or reference repositories.

## `.local/` boundary

`.local/` is ignored by Git and is never the current source tree:

```text
.local/
├── backups/              complete local snapshots only
├── patches/              local recovery or review patches only
├── reference-projects/   external projects used for research only
└── builds/               optional preserved `.app` builds only
```

`builds/` does not need to exist until a build is explicitly worth preserving. Do not use anything in `.local/` as an automatic source recovery mechanism, and do not upload it as part of the repository.

## DerivedData and builds

DerivedData is temporary and belongs under `/tmp`, never in the project root or `.local/`. The standard Debug build is:

```sh
xcodebuild -project SpotifyLyrics.xcodeproj \
  -scheme SpotifyLyrics \
  -configuration Debug \
  -derivedDataPath /tmp/lyrics-window-macos-deriveddata \
  CODE_SIGNING_ALLOWED=NO build
```

For parallel or repeated work, use a task-specific `/tmp` path. Temporary DerivedData and ordinary build products do not need to be saved.

Only a user-requested and accepted `.app` should be preserved. Store it as:

```text
.local/builds/<YYYY-MM-DD>-<label>-<short-sha>/
├── SpotifyLyrics.app
└── BUILD_INFO.md
```

`BUILD_INFO.md` must record:

- full commit SHA
- branch
- build configuration
- exact build command
- date
- purpose or label
- user acceptance status

The modification time or folder name of an `.app` or DerivedData directory is never a source-version signal. The commit SHA is the version identity.

## Tests

Use the repository's existing contract scripts; do not invent an aggregate test command. The documented core entry point is:

```sh
bash Tests/v3_lyric_readability_contract.sh
```

Run additional focused scripts from `Tests/` when the changed area requires them. Record the exact commands and results in the handoff or commit context.

## Branches, commits, and releases

- `main` is the confirmed baseline and default starting point.
- `codex/<topic>` is for Codex work.
- `antigravity/<topic>` is for Antigravity/Gemini work.
- Other agents use `<agent>/<topic>`.
- Start new work from `main` unless the user explicitly identifies another current branch.
- A runnable, reviewable small stage should end with an intentional commit and push.
- Use clear Conventional Commit messages and never force-push or rewrite shared history.
- Create a tag only at a user-confirmed important milestone.
- There is currently no formal SemVer release or release tag. Do not invent `v1.0.0` or another version now.
- After formal releases exist, use immutable `vMAJOR.MINOR.PATCH` tags pointing to the exact released commit.

## Handoff identity

When handing work to another AI, report:

1. project root;
2. current branch;
3. `git rev-parse HEAD`;
4. whether the worktree is clean;
5. any base SHA plus uncommitted changes;
6. exact tests/builds run;
7. whether an accepted `.app` archive exists.

Craft decides what should be done next. Git identifies exactly what source was used.

# AI Handoff Rules

## Project boundary

The only formal project root is:

`/Users/apple/backup/sptifylyrics`

The checked-out Git working tree is the source of truth. When the worktree is clean, `HEAD` is the exact source version. When it is dirty, report the base `HEAD` plus the uncommitted changes; never call an older backup or build product the latest source.

`main` is the confirmed baseline and the default starting point for new work. Normally create a task branch from `main`.

## Sources of truth

- Craft's latest top execution board is authoritative for product direction, priority, and stage decisions.
- Git `HEAD` is authoritative for the exact source version.
- `docs/archive/` and old reports are historical evidence only; they must not override Craft's latest decision.
- `.local/` is never a source tree. Its `backups/`, `patches/`, `reference-projects/`, and `builds/` contain local history or reference material only. Do not automatically restore or overwrite source from `.local/`.

## Before starting work

At minimum, inspect:

```sh
git status
git branch --show-current
git rev-parse HEAD
git log -5 --oneline
```

Also read the latest Craft execution board before deciding the product scope. For a substantial change, create a reversible checkpoint commit and push it before proceeding.

## Prohibited without explicit authorization

- `git reset --hard`
- `git clean`
- `git restore` when it would overwrite current changes
- force push
- rebase or other history rewriting
- inferring the latest version from an old branch, DerivedData directory, old `.app`, backup, or file modification time
- running `generate_xcodeproj.py`

Do not discard user changes or switch to a historical version to satisfy an old report.

See [`docs/DEVELOPMENT_WORKFLOW.md`](docs/DEVELOPMENT_WORKFLOW.md) for build, archive, branch, commit, and release rules.
Before staging, committing, or pushing, follow [`docs/SUBMISSION_BASELINE.md`](docs/SUBMISSION_BASELINE.md).

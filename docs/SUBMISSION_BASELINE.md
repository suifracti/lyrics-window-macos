# Submission Baseline

This is the required local checklist for any AI or collaborator preparing a commit, push, handoff, or accepted build. It complements `AGENTS.md` and `DEVELOPMENT_WORKFLOW.md`; it does not replace the latest Craft execution board.

## 1. Identify the source exactly

Run before editing and again before handoff:

```sh
git status --short
git branch --show-current
git rev-parse HEAD
git log -5 --oneline
git remote -v
```

When an upstream exists, also run:

```sh
git rev-parse '@{upstream}'
```

- Clean worktree: the full `HEAD` SHA is the exact source identity.
- Dirty worktree: report `base HEAD + uncommitted changes` and list the changed paths.
- `main` is the confirmed default baseline, not proof that another explicitly selected feature branch is obsolete.
- Never use a DerivedData folder, `.app`, `.local/` backup, screenshot, old report, or modification date to decide which source is newest.

## 2. Protect the intended scope

- Read `AGENTS.md`, the latest Craft execution board, and `docs/STATUS.md`.
- Confirm which changes belong to the current task with `git status` and `git diff`.
- Do not stage unrelated user changes.
- Before a substantial or risky modification, create and push a reversible checkpoint commit.
- Never recover files from `.local/` or history unless the user explicitly requests that exact recovery.

## 3. Verify before committing

- Review the full diff and run `git diff --check`.
- Run the focused contracts for the changed area.
- Run the standard Debug build for source, project, resource, or build-setting changes.
- Documentation-only changes do not require a rebuild, but links, commands, and repository state still require verification.
- Update `docs/STATUS.md` when a capability changes maturity; do not describe experimental code as stable.
- Check that credentials, databases, user data, generated artifacts, and `.local/` are not staged.

## 4. Commit and push intentionally

```sh
git diff --cached --stat
git diff --cached
git commit -m "<conventional commit message>"
git push -u origin "$(git branch --show-current)"
```

Use explicit paths when staging. Do not force-push, rebase shared history, or rewrite commits without explicit authorization.

## 5. Verify the published baseline

After pushing:

```sh
git status --short
git rev-parse HEAD
git rev-parse '@{upstream}'
```

The handoff must report:

- project root;
- branch;
- full `HEAD` SHA;
- whether `HEAD` matches its upstream;
- clean or dirty worktree;
- exact build/test commands and results;
- any intentionally uncommitted files;
- whether the change is on `main`, a feature branch, or both.

Commit SHA is the version identity. An archived accepted `.app`, if one exists, must record that SHA in `.local/builds/.../BUILD_INFO.md` and must never become a substitute source tree.

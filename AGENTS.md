# AGENTS.md: notes for anyone working in this repo

Generic binding rules and operating workflow live in `../workflows/agents/` (`rules.md`, `workflow.md`) and the prose style guide `../workflows/MdStyle.md`; all apply in full here.
If `../workflows` is absent (standalone checkout), use `~/workspaceconfig/deps/workflows`; if that is absent too, the injected plugin copies of `rules.md` and `workflow.md` apply.
This file holds only repo-specific guidance.
Keep it current per the shared rules.

## What this is

Personal scripts and utilities repo, consumed in two ways: as a `deps/scripts` submodule whose `git-hooks/` and `git-util/` provide the guard hooks and tooling for the public/private git-privacy workflow, and standalone via `~/workspaceconfig` for machine bootstrap (`setup/`) and desktop utilities (`shell/`, `shortcut-menus/`, `etc/`).
It carries no `deps/workflows` submodule of its own; it follows the shared workflow through the sibling checkout described above.

## Repo-specific rules

- Commit style: `[area] short lowercase summary` (see `git log`).
- `git-hooks/` and `git-util/` are shared API: every consumer repo that ran `setup-git-hooks.sh` executes these files, so interface changes propagate to all consumers on their next submodule bump.
- No `.gitprivate` split is in use here; everything committed goes to `origin` as-is.

## Reusable workflows

`../workflows/recipes/` documents reusable detailed workflows (same fallback chain as the preamble).
When a task falls under one, read and follow it.
Most relevant here: `git-privacy.md`, whose tooling this repo ships.

Project-local recipes: none yet.

## Layout

Everything is authored here; nothing is vendored.

- `git-hooks/`: pre-commit and pre-push guards for the git-privacy workflow; consumer repos point `core.hooksPath` at this directory.
- `git-util/`: `setup-git-hooks.sh` (sets `core.hooksPath`; owner runs it, it writes git config) and `publish.sh` (replays public commits `private` -> the public branch, resolved via `origin/HEAD` with `master` fallback).
- `setup/`: machine/workspace bootstrap (`fetch-repos.sh`, `fetch-tarballs.sh`, `lib.sh`); expects `$CONFIGROOT` exported by the parent's `sourceme`.
- `bin/`: standalone tools, incl. `gen_flist.py` (FuseSoC filelist generator).
- `util/`: standalone utilities, incl. `verify-format-diff.py` (checks a formatting-only diff is only rewraps and dash removals).
- `shell/`, `shortcut-menus/`, `etc/`: dwl session scripts, status helpers, dmenu-style shortcut menus, desktop file.

## Toolchain and build

Shell (POSIX sh and bash) plus Python 3 (`bin/gen_flist.py`, uses the `fusesoc` package).
No build or test suite; verify a change by exercising it in its real environment: a consumer repo for `git-hooks/`/`git-util/`, `~/workspaceconfig` for `setup/`.

## Current state and next steps

Git-privacy tooling is in daily use by consumer repos (`hw-commons` among them).
`setup/` backs the `~/workspaceconfig` bootstrap.
Direction emerges from consumer repos' needs; no roadmap file.

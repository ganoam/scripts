# AGENTS.md: notes for anyone working in this repo

Generic binding rules and operating workflow live in `~/workspaceconfig/deps/workflows/agents/` (`rules.md`, `workflow.md`) and the prose style guide `~/workspaceconfig/deps/workflows/MdStyle.md`; all apply in full here.
Resolve them through the checkout chain: `~/workspaceconfig/deps/workflows`, then `deps/workflows` in this repo, then `../workflows` for dependency checkouts; if none exists, warn the owner and prompt them to clone the workflows repo.
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

- `git-hooks/`: run-parts hook multiplexers (`pre-commit`, `pre-push`) that consumers point `core.hooksPath` at; shared guards live in `<hook>.d/` (currently `10-git-private`, the git-privacy file guards, and `20-no-public-commit`, which keeps the public branch publish-only) and run first, consumer repos add local gates in their own `git-hooks/<hook>.d/`; convention documented in `README.md`.
- `git-util/`: `setup-git-hooks.sh` (sets `core.hooksPath`; owner runs it, it writes git config), `publish.sh` (replays public commits `private` -> the public branch, resolved via `origin/HEAD` with `master` fallback), and `bump.sh` (dependency-pin tail: pushes the dep, then commits the gitlink + a one-line DEVLOG entry in the consumer; runs from the dep or by dep name from the consumer).
- `setup/`: machine/workspace bootstrap (`fetch-repos.sh`, `fetch-tarballs.sh`, `lib.sh`); expects `$CONFIGROOT` exported by the parent's `sourceme`.
- `bin/`: standalone tools, incl. `gen_flist.py` (FuseSoC filelist generator).
- `util/`: standalone utilities, incl. `verify-format-diff.py` (checks a formatting-only diff is only rewraps and dash removals).
- `tests/`: self-contained test harnesses (`test-git-privacy.sh` exercises the git-privacy hooks and publisher, `test-bump.sh` the dependency bump script; each builds its own scratch repo).
- `shell/`, `shortcut-menus/`, `etc/`: dwl session scripts, status helpers, dmenu-style shortcut menus, desktop file.

## Toolchain and build

Shell (POSIX sh and bash) plus Python 3 (`bin/gen_flist.py`, uses the `fusesoc` package).
No build; `tests/` holds self-contained bash harnesses (run `tests/test-git-privacy.sh`).
Otherwise verify a change by exercising it in its real environment: a consumer repo for `git-hooks/`/`git-util/`, `~/workspaceconfig` for `setup/`.

## Current state and next steps

Git-privacy tooling is in daily use by consumer repos (`hw-commons` among them).
`setup/` backs the `~/workspaceconfig` bootstrap.
Direction emerges from consumer repos' needs; no roadmap file.

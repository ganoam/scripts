# DEVLOG.md

## 2026-11-20: agent workflow onboarding

- Onboarded this repo onto the shared agent workflow as a dependency repo: no `deps/workflows` submodule of its own, `AGENTS.md` points at the sibling `../workflows` checkout with `~/workspaceconfig/deps/workflows` and the injected plugin copies as fallback chain.

## 2026-11-20: format-diff verifier

- owner: added `util/verify-format-diff.py`, a checker that proves a formatting-only diff contains only rewraps and dash removals and flags everything else as real content changes for review.
  Written to verify the workflows repo's MdStyle sweep; landed here as shared tooling.

## 2026-11-20: parameterize public branch

- `git-util/publish.sh` and `git-hooks/pre-commit` now resolve the public branch via `origin/HEAD` with `master` fallback instead of hardcoding it, so the git-privacy tooling applies on repos whose public branch is `main`.
  `publish.sh` also refuses to run when the resolved local branch is missing, closing a silent no-op that would have advanced `publish-base`.
  `pre-push` was already branch-agnostic (keys on the remote name); the `private` branch name stays fixed by convention.

## 2026-11-22: .gitprivate directory entries

- `.gitprivate` entries naming a directory now cover every path below it (gitignore-style), replacing exact-path-only matching in `git-hooks/pre-commit`, `git-hooks/pre-push`, and `git-util/publish.sh` via a shared `private_filter` helper.
- `publish.sh` fix: the `origin/HEAD` resolution died under `set -e` before the `master` fallback could apply on remotes without `origin/HEAD`; `|| true` restores the intended fallback.
- `pre-push` fix: a private file added and removed inside a single pushed range escaped detection (endpoint diff only); the range check now scans every pushed commit's touched paths (`git log --name-only -m`) and flags transient private content too.
- `tests/test-git-privacy.sh`: new self-contained harness that builds a scratch repo and exercises both hooks and the publisher end to end (15 checks).

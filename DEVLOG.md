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

## 2026-11-22: bump script

- `git-util/bump.sh` added: automates the tail of a dependency change: pushes the dep first (bare `push`, so a dep's configured upstream is honored rather than forcing `origin`), then commits the consumer's updated gitlink with a message listing the dep's new commits plus a one-line consumer DEVLOG entry.
  Both invocation modes: inside the dep checkout (no argument) or by dep name from the consumer repo; `-n`/`--dry-run` reports the push, commit message, and DEVLOG append without doing them.
  Pin safety: a dep sha not reachable from any `origin/*` ref is refused (an unpublished `private`-branch commit would leave the consumer's public side with a dangling gitlink and leak its subjects through the bump message; published copies carry new shas, so the private sha never lands publicly).
- `tests/test-bump.sh`: end-to-end harness (consumer + submodule + bare-remote fixture) covering both modes, the no-op case, the clean-index guard, the dirty-DEVLOG refusal, dry-run non-mutation, and the private-dep pin refusal (16 checks).

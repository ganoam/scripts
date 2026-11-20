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

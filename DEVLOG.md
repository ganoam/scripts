# DEVLOG.md

Agent-maintained.

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

- `git-util/bump.sh` added: automates the tail of a dependency change: commits the consumer's updated gitlink with a message listing the dep's new commits plus a one-line consumer DEVLOG entry.
  The script never pushes: an unpushed public dep branch is allowed and the owed push is named in the next-steps, which keeps pushes in the owner's hands and sidesteps upstream naming quirks (push.default=simple dies on name-mismatched upstreams, and an eager `git push` could send private-branch work to a mirror).
  Both invocation modes: inside the dep checkout (no argument) or by dep name from the consumer repo; `-n`/`--dry-run` reports the owed push, commit message, and DEVLOG append without doing them.
  Pin safety: only a dep sha that can never reach `origin/*` is refused (an unpublished `private`-branch commit would leave the consumer's public side with a dangling gitlink and leak its subjects through the bump message; published copies carry new shas, so the private sha never lands publicly).
- `tests/test-bump.sh`: end-to-end harness (consumer + submodule + bare-remote fixture) covering both modes, the no-op case, the clean-index guard, the dirty-DEVLOG refusal, the never-push contract, dry-run non-mutation, and the private-dep pin refusal (18 checks).
- snippet: `.gitprivate` added so the deferred-items file stays off `origin`.
- snippet: `AGENTS.md` preamble synced to the checkout-chain wording.

## 2026-11-23: hook multiplexers

- `git-hooks/pre-commit` and `git-hooks/pre-push` are now run-parts multiplexers: each saves stdin to a temp file once, then runs every executable in its own `<hook>.d/` (shared guards first, currently `10-git-private`) and then the calling repo's `git-hooks/<hook>.d/` gates; the first nonzero exit aborts the hook.
  The split lets consumer repos add local gates (e.g. workspaceconfig's `pre-push.d/readme-docs`) without forking the shared guards; numeric prefixes set `.d` order.
- `README.md` added: documents the dispatch convention and how consumers add local gates; only `git-hooks/` is covered so far.
- `tests/test-git-privacy.sh` gained repo-local `.d` dispatch checks: local gates run after the shared guards, get the replayed stdin, and can veto the hook.

## 2026-11-23: publish-only public branch

- `git-hooks/pre-commit.d/20-no-public-commit`: new shared guard refusing `git commit` on the resolved public branch (origin/HEAD, `master` fallback), so it can only advance through `git-util/publish.sh`.
  Inert where no `private` branch exists, so consumers without the split commit normally.
  The publisher is unaffected by construction: it advances the branch via `cherry-pick` in a temp worktree, which never runs `pre-commit`.
  Residual: merges and manual cherry-picks on a public-branch checkout bypass `pre-commit`; closing that would need a `commit-msg` gate plus a publisher bypass.
- `tests/test-git-privacy.sh`: the master-side allow-checks now invoke `10-git-private` directly (the new guard refuses every commit on master through the multiplexer); new checks cover the master block, the private pass, and inertness without `private`; the local-gate dispatch checks moved onto `private`.
- `README.md`, `AGENTS.md`: shared-guard inventory updated.

## 2026-11-23: dir restructure

- Renamed the non-contract dirs by domain: `shell/` -> `desktop/` (dwl session scripts and status helpers), `shortcut-menus/` -> `menus/`, `util/verify-format-diff.py` -> `bin/` (lands it on PATH via `sourceme`); `etc/` dropped (stale `dwl.desktop`, superseded by `deps/dwl/dwl.desktop`).
  `git-hooks/`, `git-util/`, `setup/`, `bin/`, `tests/` unchanged: those paths are consumer or PATH contracts.
- Reference updates outside this repo: `deps/dwl/config.h` and `deps/dwl/dwl.desktop` (`shell/` -> `desktop/`), `sourceme` PATH (`shortcut-menus` -> `menus`), workspaceconfig README, workflows docs (`util/` -> `bin/` path).
- `README.md` gained a `## Structure` table mapping each dir to how it is reached.

## 2026-11-23: verify-format-diff runs from any subdir

- `bin/verify-format-diff.py` resolves its location argument (default: cwd, i.e. the repo it is called from) to the enclosing repo's toplevel via `git rev-parse --show-toplevel`: porcelain paths are root-relative, so a call from a subdirectory previously joined them onto the subdir and died in `open()`.
- Same pass on adjacent crashes of the same wrong-basis class: changed submodule gitlinks and untracked directories are skipped with a `== path (skipped: not a regular file)` note (a gitlink's `HEAD:path` is a commit, not a blob; `git show` exited 128), and staged renames diff `HEAD:old` against worktree `new` instead of failing on `HEAD:new`.
- snippet: `README.md` structure table generalized to per-dir roles instead of file lists, so adding a tool needs no table edit.

## 2026-11-23: verify-format-diff checks only checked-in files

- The check now covers only files with a `HEAD` blob: untracked (`??`), newly-added (`A`), and copied (`C`) entries are skipped outright; an untracked file previously diffed against an empty stream and surfaced as a whole-file insertion, which could dump megabytes into the region context.
  Typechanged symlinks join gitlinks in the named non-file skip; deleted and renamed entries still compare against their `HEAD:` blob as before.

## 2026-11-23: mdstyle-scan

- `bin/mdstyle-scan.py` added (committed `b325483`, file marked `Agent-generated`): a read-only MdStyle scanner reporting candidate violations per line: `emdash` (em/en-dashes and `--` surrogates) and `multi` (multiple sentences on one source line); skips code fences, tables, headings, `<!-- name:key:begin -->` generated fences, front matter, and blockquotes.
  Companion to `verify-format-diff.py`: the scanner finds violations in place, the verifier proves a sweep diff changed nothing but format.

## 2026-11-23: provenance marks

- `Agent-maintained` on `DEVLOG.md` and `BACKLOG.md` (which gained its title line to carry the mark), `Agent-generated` on `git-util/setup-git-hooks.sh`.
  Left unmarked by convention: `AGENTS.md` (byte-identical preamble), `.gitprivate` (workflows precedent), and the owner-authored tools (`verify-format-diff.py`, `gen_flist.py`, `screenshot`, `setup/`, `desktop/`, `menus/`).

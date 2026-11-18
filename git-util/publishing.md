# Publishing from a private superset branch

Workflow for repos that are mostly public but carry private files
(docs, notes, tooling state) that must never reach the public remote.

## Model

- `origin` = public remote, `master` = public branch.
- A second remote (any name, e.g. `self`) = private mirror; local
  branch `private` tracks its `master`.
- Day-to-day work happens on `private`, which is a **superset** of
  `master`: every public commit plus commits that touch only private
  files.

## .gitprivate

`.gitprivate` (tracked on `private`, itself private) lists every
private path, one per line, repo-root relative. Exact paths only, no
globs. Comments and blank lines allowed.

- Entries guard **history**, not just the working tree. Deleting a
  private file does NOT remove its entry: keep dead paths as
  tombstones so past commits still classify as private.
- To add a new private file: list it in `.gitprivate` and commit
  `.gitprivate` first (hooks read the committed list), then commit the
  file. Or commit both with `--no-verify`.

## Commit discipline

A commit must never mix private and public files. The pre-commit hook
enforces this on both branches (on `master`: any `.gitprivate` file
staged; on `private`: a staged set containing both). Split violations
into two commits.

## publish.sh

`git-util/publish.sh` replays not-yet-published public commits from
`private` onto `master`:

- Boundary is the `publish-base` tag (default: `origin/master`).
  Everything at or before it is settled and never re-examined; the tag
  auto-advances to the scanned `private` tip after every run.
- Candidate commits: patches not yet on local `master`
  (`git cherry`), after the boundary, non-merge.
- Private-only commits are skipped. A commit mixing private and public
  files aborts the run -- split it and re-run.
- Picks are cherry-picked onto `master` in a temporary worktree, so
  the checkout never moves. On conflict it stops and prints how to
  resolve in the worktree.

After a run: `git push origin master`. The boundary tag is local;
`git push <private-remote> publish-base` keeps it backed up if wanted.

## Graduating a file to public

When a private file should become public from now on (its past stays
private):

1. Add it to `master` directly:
   `git show private:<path> > <path>` in a master worktree, commit,
   push.
2. Remove `<path>` from `.gitprivate`, commit on `private` (private
   commit).
3. Done. Commits before `publish-base` are never re-examined, so old
   commits touching the file stay private; new commits touching it are
   public and publish normally.

## Removing the boundary

`git tag -d publish-base` resets the scan to `origin/master` -- all
private-side commits get reclassified under the current `.gitprivate`
(useful for auditing, dangerous right after a graduation).

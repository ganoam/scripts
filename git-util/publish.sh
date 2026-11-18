#!/bin/bash
# Publish public commits from `private` to `master`.
#
# `private` is a superset branch: it carries all of master's content
# plus private-only commits (docs listed in .gitprivate). This script
# replays every not-yet-published public commit onto `master` via a
# temporary worktree, so the current checkout never moves.
#
# Rules relied upon (enforced by the pre-commit hook):
#   - no commit may mix .gitprivate files with public files
#   - private-only commits are simply skipped here
set -e
cd "$(git rev-parse --show-toplevel)"

private_set=$(git show private:.gitprivate 2>/dev/null \
  | sed 's/#.*//; s/^ *//; s/ *$//' | grep -v '^$' | LC_ALL=C sort)
[ -n "$private_set" ] || { echo "publish: no .gitprivate on 'private'"; exit 1; }

# Commits on private whose patch is not yet on master ('+' marks).
declare -A pending
while read mark sha; do
  [ "$mark" = "+" ] && pending[$sha]=1
done < <(git cherry master private 2>/dev/null || git cherry master private)

pick=()
for sha in $(git rev-list --reverse master..private); do
  [ "${pending[$sha]:-}" = "1" ] || continue   # already on master by patch-id
  # skip merge commits -- they can't be cherry-picked linearly
  [ "$(git rev-list --parents -n1 "$sha" | wc -w)" -gt 2 ] && continue
  touched=$(git diff-tree --no-commit-id --name-only -r "$sha" | LC_ALL=C sort)
  priv=$(comm -12 <(echo "$touched") <(echo "$private_set"))
  pub=$(comm -23 <(echo "$touched") <(echo "$private_set"))
  if [ -n "$priv" ] && [ -n "$pub" ]; then
    echo "publish: $sha mixes private and public files -- split it first:"
    git show --stat --oneline "$sha" | head -20
    exit 1
  fi
  if [ -z "$touched" ]; then
    echo "publish: skipping empty commit $(git log --oneline -1 "$sha")"
    continue
  fi
  [ -n "$pub" ] && pick+=("$sha")
done

if [ ${#pick[@]} -eq 0 ]; then
  echo "publish: nothing to publish (master already has all public patches)."
  exit 0
fi

echo "publishing ${#pick[@]} commit(s) to master:"
printf '  %s\n' "$(git log --oneline --no-walk "${pick[@]}" | tac)"

wt=$(mktemp -d /tmp/publish-master.XXXXXX)
git worktree add "$wt" master >/dev/null 2>&1
trap 'git worktree remove --force "$wt" 2>/dev/null' EXIT
for sha in "${pick[@]}"; do
  if ! git -C "$wt" cherry-pick -x "$sha"; then
    trap - EXIT
    echo "publish: conflict at $sha"
    echo "  resolve in: cd $wt && git cherry-pick --continue"
    echo "  then remove worktree: git worktree remove --force $wt"
    exit 1
  fi
done

echo
echo "published. master is now: $(git -C "$wt" log --oneline -1)"
echo "next: git push origin master"
echo "optional: merge master back into private to converge histories"

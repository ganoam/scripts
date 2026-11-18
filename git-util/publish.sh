#!/bin/bash
# Publish public commits from `private` to `master`.
#
# `private` is a superset branch: it carries all of master's content
# plus private-only commits (files listed in .gitprivate). This script
# replays every not-yet-published public commit onto `master` via a
# temporary worktree, so the current checkout never moves.
#
# Boundary: tag `publish-base` marks the last settled point on
# `private` and defaults to origin/master. Commits at or before it are
# never re-examined -- that is what lets a file graduate from private
# to public without its history leaking. The tag auto-advances to the
# scanned tip after every run.
#
# Rules relied upon (enforced by the pre-commit hook):
#   - no commit may mix .gitprivate files with public files
#   - private-only commits are simply skipped here
#
# Usage: publish.sh [--dry-run|-n]
set -e
cd "$(git rev-parse --show-toplevel)"

dry=0
case "${1:-}" in --dry-run|-n) dry=1 ;; esac

private_set=$(git show private:.gitprivate 2>/dev/null \
  | sed 's/#.*//; s/^ *//; s/ *$//' | grep -v '^$' | LC_ALL=C sort)
[ -n "$private_set" ] || { echo "publish: no .gitprivate on 'private'"; exit 1; }

if git rev-parse --verify --quiet publish-base >/dev/null; then
  base=publish-base
else
  base=origin/master
fi
scan_tip=$(git rev-parse private)

# Commits on private whose patch is not yet on local master ('+'
# marks). Local master is the pick target, so already-picked (even
# unpushed) patches are not re-examined.
declare -A pending
while read mark sha; do
  [ "$mark" = "+" ] && pending[$sha]=1
done < <(git cherry master private)

pick=(); lines=()
for sha in $(git rev-list --reverse "$base..private"); do
  line="$(git log --oneline -1 "$sha")"
  if [ "$(git rev-list --parents -n1 "$sha" | wc -w)" -gt 2 ]; then
    lines+=("skip (merge)   $line"); continue
  fi
  if [ "${pending[$sha]:-}" != "1" ]; then
    lines+=("skip (on master) $line"); continue
  fi
  touched=$(git diff-tree --no-commit-id --name-only -r "$sha" | LC_ALL=C sort)
  priv=$(comm -12 <(echo "$touched") <(echo "$private_set"))
  pub=$(comm -23 <(echo "$touched") <(echo "$private_set"))
  if [ -n "$priv" ] && [ -n "$pub" ]; then
    echo "publish: $sha mixes private and public files -- split it first:"
    git show --stat --oneline "$sha" | head -20
    exit 1
  fi
  if [ -z "$touched" ]; then
    lines+=("skip (empty)   $line"); continue
  fi
  if [ -z "$pub" ]; then
    lines+=("skip (private) $line"); continue
  fi
  pick+=("$sha"); lines+=("pick           $line")
done

printf '%s\n' "${lines[@]}"

if [ "$dry" = 1 ]; then
  echo "dry run: ${#pick[@]} commit(s) would publish; boundary $base;"
  echo "         would advance publish-base -> $(git log --oneline -1 "$scan_tip")"
  exit 0
fi

# Everything scanned is settled, picked or not -- retire it.
git tag -f publish-base "$scan_tip" >/dev/null

if [ ${#pick[@]} -eq 0 ]; then
  echo "publish: nothing to publish (publish-base -> $(git log --oneline -1 "$scan_tip"))."
  exit 0
fi

echo "publishing ${#pick[@]} commit(s) to master:"

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

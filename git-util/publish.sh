#!/bin/bash
# Agent-generated; human reviewed; output verified.
# Publish public commits from `private` to the public branch
# (resolved via origin/HEAD, default `master`).
#
# `private` is a superset branch: it carries all of the public
# branch's content plus private-only commits (files listed in
# .gitprivate). This script replays every not-yet-published public
# commit onto the public branch via a temporary worktree, so the
# current checkout never moves.
#
# Boundary: tag `publish-base` marks the last settled point on
# `private` and defaults to origin's public branch. Commits at or
# before it are never re-examined -- that is what lets a file graduate
# from private to public without its history leaking. The tag
# auto-advances to the scanned tip after every run.
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

# The public branch is origin/HEAD, falling back to master.
public=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)
public=${public#origin/}; public=${public:-master}
git rev-parse --verify --quiet "$public" >/dev/null \
  || { echo "publish: no local public branch '$public'"; exit 1; }

private_set=$(git show private:.gitprivate 2>/dev/null \
  | sed 's/#.*//; s/^ *//; s/ *$//' | grep -v '^$' | LC_ALL=C sort)
[ -n "$private_set" ] || { echo "publish: no .gitprivate on 'private'"; exit 1; }

# An entry matches a path equal to it, or every path below it when it
# names a directory (gitignore-style, repo-root relative).
private_filter() {
  local p e
  while IFS= read -r p; do          # each path on stdin
    while IFS= read -r e; do        # each .gitprivate entry
      case $p in "$e"|"$e"/*) echo "$p"; break ;; esac
    done <<< "$private_set"
  done
}

if git rev-parse --verify --quiet publish-base >/dev/null; then
  base=publish-base
else
  base="origin/$public"
fi
scan_tip=$(git rev-parse private)

# Commits on private whose patch is not yet on the local public
# branch ('+' marks). The local public branch is the pick target, so
# already-picked (even unpushed) patches are not re-examined.
declare -A pending
while read mark sha; do
  [ "$mark" = "+" ] && pending[$sha]=1
done < <(git cherry "$public" private)

pick=(); lines=()
for sha in $(git rev-list --reverse "$base..private"); do
  line="$(git log --oneline -1 "$sha")"
  if [ "$(git rev-list --parents -n1 "$sha" | wc -w)" -gt 2 ]; then
    lines+=("skip (merge)   $line"); continue
  fi
  if [ "${pending[$sha]:-}" != "1" ]; then
    lines+=("skip (on $public) $line"); continue
  fi
  touched=$(git diff-tree --no-commit-id --name-only -r "$sha" | LC_ALL=C sort)
  priv=$(echo "$touched" | private_filter)
  pub=$(comm -23 <(echo "$touched") <(echo "$priv"))
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

if [ ${#pick[@]} -eq 0 ]; then
  # Everything scanned is settled -- retire it.
  git tag -f publish-base "$scan_tip" >/dev/null
  echo "publish: nothing to publish (publish-base -> $(git log --oneline -1 "$scan_tip"))."
  exit 0
fi

echo "publishing ${#pick[@]} commit(s) to $public:"

wt=$(mktemp -d /tmp/publish.XXXXXX)
if ! git worktree add "$wt" "$public"; then
  echo "publish: could not create worktree for '$public' --"
  echo "  is another worktree already holding it? (git worktree list)"
  rm -rf "$wt"
  exit 1
fi
trap 'git worktree remove --force "$wt" 2>/dev/null' EXIT
for sha in "${pick[@]}"; do
  if ! out=$(git -C "$wt" cherry-pick -x "$sha" 2>&1); then
    if echo "$out" | grep -q "now empty"; then
      echo "  skip (already applied) ${sha:0:8}  $(git log --format=%s -1 "$sha")"
      continue
    fi
    trap - EXIT
    echo "publish: cherry-pick failed at $sha:"
    echo "$out" | sed 's/^/  /'
    echo "  resolve in: cd $wt && git cherry-pick --continue"
    echo "  then remove worktree: git worktree remove --force $wt"
    exit 1
  fi
  echo "  $(git -C "$wt" rev-parse --short HEAD) <- ${sha:0:8}  $(git log --format=%s -1 "$sha")"
done

# All picks applied -- the scanned range is settled.
git tag -f publish-base "$scan_tip" >/dev/null
echo
echo "published. $public is now: $(git -C "$wt" log --oneline -1)"
echo "next: git push origin $public"
echo "optional: git merge $public   # pull published commits back into private"

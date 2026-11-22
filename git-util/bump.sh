#!/bin/bash
# Agent-generated; human reviewed; output verified.
# Tail of a dependency change: push the dep, update the consumer
# repo's gitlink, and commit the bump there. The bump commit lists
# the dep's commits since the previous pin; a one-line DEVLOG entry
# summarizing them rides in the same commit.
#
# Usage:
#   bump.sh [-n]       inside a dependency checkout: bumps this dep
#   bump.sh [-n] <dep> in the consumer repo: <dep> is a submodule path
#                      or its basename (scripts -> deps/scripts)
#   -n, --dry-run      report the bump without doing it
set -e

dry=0
case "${1:-}" in -n|--dry-run) dry=1; shift ;; esac

die() { echo "bump: $*" >&2; exit 1; }

if [ $# -ge 1 ]; then
  consumer=$(git rev-parse --show-toplevel) || die "not inside a repo"
  dep_path=$(
    # run in the consumer; .gitmodules is INI: *.path = submodule paths
    git -C "$consumer" config -f .gitmodules --get-regexp '\.path$' |
    # d = dep arg; $2 = path value; keep exact or basename match
    awk -v d="$1" '$2 == d || $2 ~ "/" d "$" {print $2; exit}'
  )
  [ -n "$dep_path" ] || die "'$1' is not a submodule of $consumer"
  dep=$consumer/$dep_path
else
  dep=$(git rev-parse --show-toplevel) || die "not inside a repo"
  consumer=$(git -C "$dep" rev-parse --show-superproject-working-tree 2>/dev/null || true)
  [ -n "$consumer" ] || die "$dep is not a submodule checkout"
  dep_path=$(realpath --relative-to="$consumer" "$dep")
fi
name=$(basename "$dep_path")

# Pin bookkeeping: what the consumer records vs the dep's HEAD.
new=$(git -C "$dep" rev-parse HEAD)
old=$(git -C "$consumer" ls-tree HEAD -- "$dep_path" | awk '{print $3}')
[ -n "$old" ] || die "$dep_path is not pinned in the consumer HEAD"
[ "$old" != "$new" ] || { echo "bump: $dep_path already at $new"; exit 0; }
git -C "$dep" merge-base --is-ancestor "$old" "$new" \
  || die "$dep_path history moved ($old not an ancestor); bump manually"

# Keep the bump commit clean: only the gitlink and DEVLOG may land in it.
[ -z "$(git -C "$consumer" diff --cached --name-only)" ] \
  || die "consumer index not clean; commit or unstage first"
# Unstaged DEVLOG.md edits would ride into the bump commit via
# `git add DEVLOG.md`; refuse unless the file is clean or brand-new.
dirty=$(git -C "$consumer" status --porcelain -- DEVLOG.md | grep -v '^??' || true)
[ -z "$dirty" ] || die "consumer DEVLOG.md has uncommitted changes; commit them first"
[ -z "$(git -C "$dep" status --porcelain)" ] \
  || echo "bump: warning: $dep_path checkout is dirty; pin covers HEAD only"

log=$(git -C "$dep" log --format='  %h %s' "$old..$new")
n=$(echo "$log" | wc -l); c=commits; [ "$n" = 1 ] && c=commit

msg="[deps] bump $name

$dep_path <- ${old:0:8}..${new:0:8}:
$log"

# DEVLOG: a bare heading, date + name + count. No bullet, no commit
# list: the bump commit message itself carries it (house rule: hashes
# and transcripts belong to git log, not to DEVLOG).
entry=$(printf '\n## %s: bump %s %s...%s (%s %s)\n' \
  "$(date +%F)" "$name" "${old:0:8}" "${new:0:8}" "$n" "$c")

if [ "$dry" = 1 ]; then
  echo "dry run: would bump $dep_path (${old:0:8} -> ${new:0:8}, $n $c)"
  if git -C "$dep" rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
    up=$(git -C "$dep" rev-list --count '@{u}..HEAD')
    echo "  push: $up unpushed commit(s) -> $(git -C "$dep" rev-parse --abbrev-ref '@{u}')"
  else
    echo "  push: would FAIL, no upstream configured for this checkout"
  fi
  echo "  commit message:"
  echo "$msg" | sed 's/^/    /'
  echo "  DEVLOG append:"
  echo "$entry" | sed 's/^/    /'
  if git -C "$dep" branch -r --contains "$new" | grep -q 'origin/'; then
    echo "  pin: reachable on an origin/* ref"
  else
    echo "  pin: not on any origin/* ref (needs the push above)"
  fi
  exit 0
fi

# The dep push must land before the consumer commits the pin, or the
# consumer could record a sha the dep remote never got. Bare `push`
# honors the dep's upstream: not every dep pushes to origin (a
# git-privacy dep pushes its private branch to a mirror).
git -C "$dep" push

# The pin must resolve on the dep's public remote: a sha living only
# on a private branch or mirror leaves the consumer's public side
# with a dangling gitlink and leaks private subjects via the bump
# message. publish.sh replays private-branch patches under new shas,
# so a private-branch sha is never reachable from the public branch.
git -C "$dep" branch -r --contains "$new" | grep -q 'origin/' \
  || die "$dep_path: $new not on any origin/* ref (dep on a private branch? publish it first)"

{
  [ -f "$consumer/DEVLOG.md" ] || printf '# DEVLOG.md\n'
  printf '%s' "$entry"
} >> "$consumer/DEVLOG.md"

git -C "$consumer" add "$dep_path" DEVLOG.md
git -C "$consumer" commit -m "$msg"
echo "bump: $dep_path -> $new"
echo "next: git -C $consumer push"

#!/bin/bash
# Agent-generated; human reviewed; output validated.
# Integration test for git-util/bump.sh: fixture is a consumer repo
# with a dependency submodule plus a bare remote for the dep. Runs the
# real script in both invocation modes and checks gitlink, bump commit,
# DEVLOG line, and that the dep was pushed first.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d /tmp/bump-test.XXXXXX)
trap 'rm -rf "$T"' EXIT
C=$T/consumer; D=$T/dep-seed; S=$C/deps/dep-work
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

pass=0; fail=0
ok()  { pass=$((pass+1)); echo "ok   $1"; }
bad() { fail=$((fail+1)); echo "FAIL $1"; }

# expect <desc> <want-exit> <cmd...>
expect() {
  local desc=$1 want=$2; shift 2
  "$@" >"$T/out" 2>&1; local got=$?
  if [ "$got" = "$want" ]; then ok "$desc"; return; fi
  bad "$desc: exit $got, want $want"; sed 's/^/    /' "$T/out"
}

# expect_grep <desc> <pattern> <want-exit> <cmd...>
# outcome plus a check that the reason matches the pattern.
expect_grep() {
  local desc=$1 pat=$2 want=$3; shift 3
  "$@" >"$T/out" 2>&1; local got=$?
  if [ "$got" = "$want" ] && grep -q -- "$pat" "$T/out"; then ok "$desc"; return; fi
  bad "$desc: exit $got, want $want, pattern '$pat'"; sed 's/^/    /' "$T/out"
}

# check <desc> <cmd...>: pass iff cmd exits 0.
check() { local desc=$1; shift; if "$@" >/dev/null 2>&1; then ok "$desc"; else bad "$desc"; fi; }

bump()    { bash "$ROOT/git-util/bump.sh" "$@"; }
gitlink() { git -C "$C" ls-tree HEAD -- deps/dep-work | awk '{print $3}'; }

# --- fixture ------------------------------------------------------
# Seed dep in $D, push to a bare remote, then add the remote (not the
# seed dir) as submodule so the submodule's pushes land on the bare
# remote, like a real dependency setup.
git init -q --bare "$T/dep-origin.git" && git init -q "$D" || exit 1
cd "$D" && git symbolic-ref HEAD refs/heads/master
echo v1 > f.txt; git add f.txt; git commit -qm 'dep init'
git remote add origin "$T/dep-origin.git"; git push -qu origin master

git init -q "$C" && cd "$C" && git symbolic-ref HEAD refs/heads/master
echo r > README.md; git add README.md; git commit -qm 'consumer init'
git -c protocol.file.allow=always submodule add "$T/dep-origin.git" \
  deps/dep-work >/dev/null 2>&1
git commit -qm 'add dep submodule'
printf '# DEVLOG.md\n' > DEVLOG.md; git add DEVLOG.md; git commit -qm devlog

# --- no-arg mode: run inside the dep checkout ---------------------
cd "$S"
echo v2 > f.txt; git add f.txt; git commit -qm 'dep change'
echo v3 > g.txt; git add g.txt; git commit -qm 'dep change 2'
expect 'bump inside dep: exits 0' 0 bump
check 'gitlink pins new dep HEAD' \
  test "$(gitlink)" = "$(git -C "$S" rev-parse HEAD)"
expect_grep 'bump commit lists dep commits' 'dep change 2' 0 \
  git -C "$C" log -1 --format=%B
expect_grep 'consumer DEVLOG gained bump heading' 'bump dep-work [0-9a-f]*\.\.\.[0-9a-f]* (2 commits)' 0 \
  cat "$C/DEVLOG.md"
check 'dep commits pushed to its remote' \
  test "$(git --git-dir="$T/dep-origin.git" rev-parse refs/heads/master)" \
       = "$(git -C "$S" rev-parse HEAD)"

# --- arg mode: dep name from the consumer repo ---------------------
cd "$S" && echo v4 > f.txt && git add f.txt && git commit -qm 'dep change 3'
cd "$C"
expect 'bump by dep name from consumer' 0 bump dep-work
check 'gitlink at v4' test "$(gitlink)" = "$(git -C "$S" rev-parse HEAD)"

# --- guards ---------------------------------------------------------
expect 'second bump is a no-op' 0 bump dep-work
cd "$S" && echo v5 > f.txt && git add f.txt && git commit -qm 'dep change 4'
cd "$C"
echo x > README.md; git add README.md
expect 'staged change in consumer: refuses' 1 bump dep-work
git reset -q
expect 'unknown dep name: refuses' 1 bump nope
echo draft >> "$C/DEVLOG.md"
expect 'unstaged DEVLOG edit in consumer: refuses' 1 bump dep-work
git -C "$C" checkout -q DEVLOG.md

# --- dry run ---------------------------------------------------------
cd "$S" && echo v6 > f.txt && git add f.txt && git commit -qm 'dep change 5'
PRELINK=$(gitlink)
expect_grep 'dry run reports the bump' 'dep change 5' 0 bump -n
check 'dry run left gitlink unchanged' test "$(gitlink)" = "$PRELINK"
check 'dry run pushed nothing' \
  test "$(git --git-dir="$T/dep-origin.git" rev-parse refs/heads/master)" \
       != "$(git -C "$S" rev-parse HEAD)"
check 'dry run left DEVLOG untouched' \
  test "$(grep -c 'dep change 5' "$C/DEVLOG.md")" = 0

# --- dep on a private branch ----------------------------------------
# A sha living only on a private branch (pushed to a mirror, never to
# origin) must be refused: the gitlink would dangle publicly.
git init -q --bare "$T/dep-mirror.git"
cd "$S" && git checkout -qb private
echo s > secret.txt; git add secret.txt; git commit -qm 'private dep change'
git remote add mirror "$T/dep-mirror.git"; git push -qu mirror private
expect_grep 'pin to a private-only dep sha: refuses' 'not on any origin' 1 bump

echo
echo "$pass passed, $fail failed"
[ "$fail" = 0 ]

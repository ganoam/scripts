#!/bin/bash
# Agent-generated; human reviewed.
# Integration tests for the git-privacy guards (git-hooks/) and the
# publisher (git-util/publish.sh): builds a throwaway repo under /tmp
# and runs the shipped scripts against it. Run directly; no fixtures.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d /tmp/gitprivate-test.XXXXXX)
trap 'rm -rf "$T"' EXIT
R=$T/repo
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t \
       GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

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
# expect an outcome and check the reason matches the pattern
expect_grep() {
  local desc=$1 pat=$2 want=$3; shift 3
  "$@" >"$T/out" 2>&1; local got=$?
  if [ "$got" = "$want" ] && grep -q -- "$pat" "$T/out"; then ok "$desc"; return; fi
  bad "$desc: exit $got, want $want, pattern '$pat'"; sed 's/^/    /' "$T/out"
}

# check <desc> <cmd...>: pass iff cmd exits 0 (for count assertions).
check() { local desc=$1; shift; if "$@" >/dev/null 2>&1; then ok "$desc"; else bad "$desc"; fi; }

pre_commit() { bash "$ROOT/git-hooks/pre-commit"; }
pre_push()   { printf 'refs/heads/b %s refs/heads/b %s\n' "$2" "$3" \
               | bash "$ROOT/git-hooks/pre-push" "$1" url; }
publish()    { bash "$ROOT/git-util/publish.sh" "$@"; }
ZERO=0000000000000000000000000000000000000000

# --- fixture repo ------------------------------------------------
# $R = repo under test; $T/origin.git = bare repo playing the public
# remote (pre-push keys on 'origin', publish.sh needs origin/master).
git init -q "$R" && git init -q --bare "$T/origin.git" || exit 1
cd "$R" || exit 1
git symbolic-ref HEAD refs/heads/master   # 'master' regardless of init.defaultBranch (nothing initialized yet)
echo readme > README.md; git add README.md; git commit -qm init # -q: quiet
git remote add origin "$T/origin.git"; git push -qu origin master
# creates origin/master (publish-base default); origin/HEAD stays
# unset, so the 'master' fallback is the path exercised.

# private: .gitprivate (file entry, dir entry, tombstone), a private
# commit, and a public commit on top.
git checkout -qb private
printf '.gitprivate\nnotes\nsecret.md\ntomb\n' > .gitprivate
git add .gitprivate; git commit -qm gitprivate
mkdir notes; echo s > notes/s.md; echo s > secret.md
git add notes/s.md secret.md; git commit -qm 'private files'
echo p > pub.md; git add pub.md; git commit -qm 'public file'

# --- publish.sh ---------------------------------------------------
check 'publish picks the public commit only' \
  test "$(publish -n | grep -c 'pick ')" = 1
check 'publish skips both private commits' \
  test "$(publish -n | grep -c 'skip (private)')" = 2

echo m > pubmix.md; echo m > notes/mix.md
git add -A; git commit -qm 'mixed'
expect 'publish aborts on a mixed commit' 1 publish --dry-run
git reset -q --hard HEAD~1

# --- pre-commit on master ------------------------------------------
git checkout -q master
mkdir -p notes tomb
echo l > notes/leak.md; git add notes/leak.md
expect_grep 'master: blocks file under private dir' 'notes/leak.md' 1 pre_commit
git reset -q
echo x > notesx.md; git add notesx.md
expect 'master: path boundary, notesx.md is not notes/' 0 pre_commit
git reset -q
echo s > secret.md; git add secret.md
expect_grep 'master: blocks exact private file' 'secret.md' 1 pre_commit
git reset -q
echo t > tomb/t.md; git add tomb/t.md
expect_grep 'master: tombstone entry covers new dir' 'tomb/t.md' 1 pre_commit
git reset -q
echo c > clean.md; git add clean.md
expect 'master: allows public file' 0 pre_commit
git reset -q; git clean -fdq

# --- pre-commit on private ------------------------------------------
git checkout -q private
echo n > notes/new.md; git add notes/new.md
expect 'private: allows private-only commit' 0 pre_commit
echo p2 > pub2.md; git add pub2.md
expect 'private: blocks mixed commit' 1 pre_commit
git reset -q; git clean -fdq

# --- pre-push ---------------------------------------------------------
expect 'pre-push: ignores non-origin remote' 0 \
  pre_push self "$(git rev-parse HEAD)" "$ZERO"
git checkout -q master
mkdir -p notes tomb
echo l > notes/leak.md; echo t > tomb/t.md
git add -A; git commit -qm leak
TIP=$(git rev-parse HEAD); PREV=$(git rev-parse HEAD~1)
expect_grep 'pre-push: blocks private dir files in pushed tree' 'notes/leak.md' 1 \
  pre_push origin "$TIP" "$ZERO"
git rm -q notes/leak.md; git commit -qm unleak
TIP2=$(git rev-parse HEAD)
expect_grep 'pre-push: blocks private file deleted in range' 'notes/leak.md' 1 \
  pre_push origin "$TIP2" "$TIP"
expect_grep 'pre-push: blocks private file added and removed inside range' 'notes/leak.md' 1 \
  pre_push origin "$TIP2" "$PREV"
expect 'pre-push: allows clean tree and range' 0 \
  pre_push origin "$PREV" "$ZERO"

# --- repo-local .d hook dispatch --------------------------------------
# Consumers add gates under <repo>/git-hooks/<hook>.d/; they run after
# the shared guards and each gets a replayed copy of stdin.
git checkout -q master
mkdir -p git-hooks/pre-commit.d git-hooks/pre-push.d
printf '#!/bin/bash\ntouch %s/local-pc\n' "$T" \
  > git-hooks/pre-commit.d/marker
printf '#!/bin/bash\ncat > %s/local-stdin\n' "$T" \
  > git-hooks/pre-push.d/see-stdin
chmod +x git-hooks/pre-commit.d/marker git-hooks/pre-push.d/see-stdin
echo d > d.md; git add d.md
expect 'local pre-commit.d gate runs' 0 pre_commit
check 'local gate was executed' test -f "$T/local-pc"
expect 'local pre-push.d gate runs on non-origin remote' 0 \
  pre_push self "$ZERO" "$ZERO"
check 'local gate received the pushed ref list' test -s "$T/local-stdin"
printf '#!/bin/bash\nexit 1\n' > git-hooks/pre-commit.d/marker
expect 'failing local gate aborts the hook' 1 pre_commit
git reset -q; git clean -fdq

echo
echo "$pass passed, $fail failed"
[ "$fail" = 0 ]

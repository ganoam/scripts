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
# 10-git-private invoked directly: unit-checks the file-boundary guard
# without 20-no-public-commit, which refuses every commit on master.
git_private() { bash "$ROOT/git-hooks/pre-commit.d/10-git-private"; }
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

# private: two commits from before .gitprivate exists (one ordinary
# file, one under the later-listed notes/ dir), then .gitprivate
# (file entry, dir entry, tombstone), a private commit, and a public
# commit on top. The pre-list commits exercise era classification
# against the union of later versions.
git checkout -qb private
echo x > early.md; git add early.md; git commit -qm 'pre-list public'
mkdir -p notes; echo n > notes/early.md
git add notes/early.md; git commit -qm 'pre-list notes'
printf '.gitprivate\nnotes\nsecret.md\ntomb\n' > .gitprivate
git add .gitprivate; git commit -qm gitprivate
echo s > notes/s.md; echo s > secret.md
git add notes/s.md secret.md; git commit -qm 'private files'
echo p > pub.md; git add pub.md; git commit -qm 'public file'

# --- publish.sh ---------------------------------------------------
check 'publish picks both public commits' \
  test "$(publish -n | grep -c 'pick ')" = 2
check 'publish skips all three private commits' \
  test "$(publish -n | grep -c 'skip (private)')" = 3

echo m > pubmix.md; echo m > notes/mix.md
git add -A; git commit -qm 'mixed'
expect 'publish aborts on a mixed commit' 1 publish --dry-run
git reset -q --hard HEAD~1

# --- publish.sh: applied detection across merge-back ----------------
# Once published commits are merged back into private, patch-ids over the whole
# public branch must still retire the originals. The merged-in copy
# is itself a scan candidate and gets the same marking.
expect 'publish lands the public commit' 0 publish
git merge -qm 'merge public back' master
echo p2 > pub5.md; git add pub5.md; git commit -qm 'public two'
git tag -d publish-base >/dev/null
check 'merged-back original is not re-picked' \
  test "$(publish -n | grep -c 'pick .*public file')" = 0
check 'merged-back commits show skip (on master)' \
  test "$(publish -n | grep -c 'skip (on master).*public file')" -ge 1
check 'new public commit still picked' \
  test "$(publish -n | grep -c 'pick .*public two')" = 1

# --- publish.sh: era classification ---------------------------------
# A commit is judged by its era's .gitprivate unioned with every later
# version: a path private then (unlisted since) stays skipped, and a
# path listed only later is protected for its earlier commits.
echo grad.md >> .gitprivate; git add .gitprivate
git commit -qm 'list grad.md'
echo g > grad.md; git add grad.md; git commit -qm 'private-at-era file'
sed -i '/^grad.md$/d' .gitprivate; git add .gitprivate
git commit -qm 'unlist grad.md'
echo e > era.md; git add era.md; git commit -qm 'public-at-era file'
echo era.md >> .gitprivate; git add .gitprivate
git commit -qm 'list era.md later'
echo p4 > pub4.md; git add pub4.md; git commit -qm 'public tail'
check 'era-private commit skipped though unlisted now' \
  test "$(publish -n | grep -c 'skip (private).*private-at-era')" = 1
check 'later-listed path skipped for earlier commits' \
  test "$(publish -n | grep -c 'skip (private).*public-at-era')" = 1
check 'public tail still picked' \
  test "$(publish -n | grep -c 'pick .*public tail')" = 1

# --- pre-commit on master ------------------------------------------
git checkout -q master
mkdir -p notes tomb
echo l > notes/leak.md; git add notes/leak.md
expect_grep 'master: blocks file under private dir' 'notes/leak.md' 1 pre_commit
git reset -q
echo x > notesx.md; git add notesx.md
expect 'master: path boundary, notesx.md is not notes/' 0 git_private
git reset -q
echo s > secret.md; git add secret.md
expect_grep 'master: blocks exact private file' 'secret.md' 1 pre_commit
git reset -q
echo t > tomb/t.md; git add tomb/t.md
expect_grep 'master: tombstone entry covers new dir' 'tomb/t.md' 1 pre_commit
git reset -q
echo c > clean.md; git add clean.md
expect 'master: allows public file' 0 git_private
git reset -q; git clean -fdq

# --- pre-commit on private ------------------------------------------
git checkout -q private
echo n > notes/new.md; git add notes/new.md
expect 'private: allows private-only commit' 0 pre_commit
echo p2 > pub2.md; git add pub2.md
expect 'private: blocks mixed commit' 1 pre_commit
git reset -q; git clean -fdq

# --- pre-commit: public branch is publish-only ----------------------
git checkout -q master
echo np > nopub.md; git add nopub.md
expect_grep 'master: blocks direct commit' 'publish.sh' 1 pre_commit
git reset -q; git clean -fdq
git checkout -q private
echo np2 > pub3.md; git add pub3.md
expect 'private: commit still allowed' 0 pre_commit
git reset -q; git clean -fdq
# Without the private/public split the guard is inert:
git checkout -q master
git branch -m private notprivate
echo z > z.md; git add z.md
expect 'no private branch: master commit passes' 0 pre_commit
git reset -q; git clean -fdq
git branch -m notprivate private

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
# Runs on private: master refuses every commit (20-no-public-commit).
git checkout -q private
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

# --- pre-commit.d/15-gitlink-public: staged gitlinks ------------------
# A dep pinned at a private/side-line sha must be refused: bump.sh
# checks its own pins, this covers hand commits sweeping up whatever
# the dep checkout holds. Gitlinks are staged via --cacheinfo; the
# dep clone needs its public line on origin/HEAD (checkout master
# last so the clone's default lands there).
gitlink_public() { bash "$ROOT/git-hooks/pre-commit.d/15-gitlink-public"; }
D2=$T/dep2
git init -q "$D2" && git -C "$D2" symbolic-ref HEAD refs/heads/master
git -C "$D2" commit -qm 'dep init' --allow-empty
pub_sha=$(git -C "$D2" rev-parse HEAD)
git -C "$D2" checkout -qb private && git -C "$D2" commit -qm 'dep private' --allow-empty
priv_sha=$(git -C "$D2" rev-parse HEAD)
git -C "$D2" checkout -q master && git -C "$D2" commit -qm 'dep pub2' --allow-empty
git -C "$D2" checkout -q private && git -C "$D2" merge -qm 'merge' master
merge_sha=$(git -C "$D2" rev-parse HEAD)
git -C "$D2" checkout -q master
git -c protocol.file.allow=always clone -q "$D2" deps/dep

git update-index --add --cacheinfo 160000,"$pub_sha",deps/dep
expect 'gitlink: public-branch pin passes' 0 gitlink_public
git update-index --add --cacheinfo 160000,"$priv_sha",deps/dep
expect_grep 'gitlink: private-side sha refused' 'public branch' 1 gitlink_public
git update-index --add --cacheinfo 160000,"$merge_sha",deps/dep
expect_grep 'gitlink: private-side merge refused' 'public branch' 1 gitlink_public
git update-index --add --cacheinfo 160000,"$pub_sha",deps/ghost
expect_grep 'gitlink: pin without checkout refused' 'cannot verify' 1 gitlink_public
git reset -q
echo g > g.md; git add g.md
expect 'gitlink: no gitlink change is inert' 0 gitlink_public
git reset -q; git clean -fdq

echo
echo "$pass passed, $fail failed"
[ "$fail" = 0 ]

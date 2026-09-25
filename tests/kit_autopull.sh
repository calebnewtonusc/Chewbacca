#!/bin/bash
# kit-autopull must fast-forward a clean checkout and must refuse, without
# touching anything, in every case where a pull could cost work.
#
# The dirty-tree case is the one this file exists for. An automatic pull is
# only acceptable if it cannot eat uncommitted work, and "it looks careful" is
# not evidence. Each case below is run against a real origin.
set -uo pipefail
ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
HOOK="$ROOT/.claude/hooks/kit-autopull.sh"
[ -x "$HOOK" ] || { echo "FAIL: kit-autopull.sh missing or not executable"; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export CHEWBACCA_LOG_DIR="$TMP/logs"
export CHEWBACCA_PULL_INTERVAL=0
FAILED=0
fail() { echo "FAIL: $*"; FAILED=1; }

git init -q --bare "$TMP/origin.git"
# The bare repo's HEAD names git's default branch, which is master on CI's
# git and main on this Mac. Cloned with HEAD on a branch that does not exist,
# the clone has no checkout and every step below fails (CI, 2026-09-21 on).
git -C "$TMP/origin.git" symbolic-ref HEAD refs/heads/main
git clone -q "$TMP/origin.git" "$TMP/work" 2>/dev/null
git -C "$TMP/work" config user.email t@t; git -C "$TMP/work" config user.name t
echo one > "$TMP/work/a.txt"
git -C "$TMP/work" add a.txt; git -C "$TMP/work" commit -qm one
git -C "$TMP/work" branch -M main; git -C "$TMP/work" push -q origin main
git clone -q "$TMP/origin.git" "$TMP/clone"
git -C "$TMP/clone" config user.email t@t; git -C "$TMP/clone" config user.name t
export CHEWBACCA_REPO_DIR="$TMP/clone"

ahead() {  # push one new commit to origin
  echo "$1" > "$TMP/work/$1.txt"
  git -C "$TMP/work" add "$1.txt"
  git -C "$TMP/work" commit -qm "$1"
  git -C "$TMP/work" push -q origin main
}

# 1. clean and behind: fast-forwards
ahead two
bash "$HOOK" </dev/null >/dev/null 2>&1
[ -f "$TMP/clone/two.txt" ] || fail "clean checkout did not fast-forward"

# 2. dirty and behind: refuses, and the dirty file is untouched
ahead three
echo PRECIOUS > "$TMP/clone/a.txt"
bash "$HOOK" </dev/null >/dev/null 2>&1
[ "$(cat "$TMP/clone/a.txt")" = "PRECIOUS" ] || fail "a dirty file was overwritten"
[ -f "$TMP/clone/three.txt" ] && fail "pulled into a dirty tree"

# 3. not on main: refuses
git -C "$TMP/clone" checkout -q -- a.txt
git -C "$TMP/clone" checkout -q -b feat/x
bash "$HOOK" </dev/null >/dev/null 2>&1
[ -f "$TMP/clone/three.txt" ] && fail "pulled while on a feature branch"

# 4. diverged: refuses rather than creating a merge commit
git -C "$TMP/clone" checkout -q main
echo local > "$TMP/clone/d.txt"
git -C "$TMP/clone" add d.txt; git -C "$TMP/clone" commit -qm "local only"
bash "$HOOK" </dev/null >/dev/null 2>&1
[ "$(git -C "$TMP/clone" log --oneline --merges | wc -l | tr -d ' ')" = "0" ] ||
  fail "created a merge commit instead of refusing"

[ "$FAILED" -eq 0 ] && echo "ok    kit-autopull fast-forwards clean and refuses dirty, branched and diverged"
exit "$FAILED"

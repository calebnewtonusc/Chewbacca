#!/bin/bash
# The pre-commit guard must refuse an index holding two sessions' work, and must
# stay silent when it cannot tell. On 2026-09-20 the guard existed since 18:49
# and commit 4a0b1df still absorbed another session's files at 21:44, because
# the only signal was mtime and a live session's files are fresh.
set -uo pipefail
SRC="$(cd "$(dirname "$0")/.." && pwd)/.githooks/pre-commit"
T=$(mktemp -d); WLDIR=$(mktemp -d); trap 'rm -rf "$T" "$WLDIR"' EXIT
pass=0; fail=0
ok(){ printf '  \033[0;32mpass\033[0m  %s\n' "$1"; pass=$((pass+1)); }
no(){ printf '  \033[0;31mfail\033[0m  %s\n' "$1"; fail=$((fail+1)); }

cd "$T" && git init -q . && git config user.email t@t.t && git config user.name t
mkdir .githooks && cp "$SRC" .githooks/ && git config core.hooksPath .githooks
export CHEWBACCA_WRITE_LOG="$WLDIR/wl.tsv" CHEWBACCA_PATHSPEC_COMMIT=1
stage(){ echo "$RANDOM" > a.txt; echo "$RANDOM" > b.txt; git add -A; }
now(){ date +%s; }

stage; rm -f "$CHEWBACCA_WRITE_LOG"
git commit -q -m x >/dev/null 2>&1 && ok "no write log: stays silent" || no "blocked with no log"

stage; printf '%s\tS1\t%s/a.txt\n%s\tS1\t%s/b.txt\n' "$(now)" "$T" "$(now)" "$T" > "$CHEWBACCA_WRITE_LOG"
git commit -q -m x >/dev/null 2>&1 && ok "one session: allowed" || no "blocked a single author"

stage; printf '%s\tS1\t%s/a.txt\n%s\tS2\t%s/b.txt\n' "$(now)" "$T" "$(now)" "$T" > "$CHEWBACCA_WRITE_LOG"
git commit -q -m x >/dev/null 2>&1 && no "absorbed a second session's file" || ok "two sessions: refused"

stage; echo z > c.txt; git add -A
printf '%s\tS1\t%s/a.txt\n' "$(now)" "$T" > "$CHEWBACCA_WRITE_LOG"
git commit -q -m x >/dev/null 2>&1 && ok "unlogged paths: stays silent" || no "blocked on unlogged paths"

stage; printf '%s\tS1\t%s/a.txt\n%s\tS2\t%s/b.txt\n' "$(now)" "$T" "$(now)" "$T" > "$CHEWBACCA_WRITE_LOG"
ALLOW_STALE_STAGED=1 git commit -q -m x >/dev/null 2>&1 && ok "override still works" || no "override broken"

# The session gate: two live sessions, bare multi-file commit is refused,
# a pathspec commit is allowed, and a MERGE is allowed because git forbids a
# pathspec during one (2026-09-22, it blocked every upstream merge until then).
unset CHEWBACCA_PATHSPEC_COMMIT
rm -f "$CHEWBACCA_WRITE_LOG"
export CHEWBACCA_FAKE_SESSIONS=2

stage
git commit -q -m x >/dev/null 2>&1 && no "two sessions: absorbed a bare commit" || ok "two sessions: bare commit refused"

stage
git commit -q -m x -- a.txt b.txt >/dev/null 2>&1 && ok "two sessions: pathspec commit allowed" || no "two sessions: refused a pathspec commit"

# A real, conflict-free merge, concluded with a bare commit.
git checkout -q -b base 2>/dev/null || git checkout -q base
echo base > m.txt; git add m.txt; git commit -q -m base -- m.txt
git checkout -q -b feature
echo feat > f.txt; git add f.txt; git commit -q -m feat -- f.txt
git checkout -q base
echo other > o.txt; git add o.txt; git commit -q -m other -- o.txt
git merge -q --no-commit --no-ff feature >/dev/null 2>&1
git commit -q -m "merge feature" >/dev/null 2>&1 && ok "two sessions: merge commit allowed" || no "two sessions: refused a merge commit"

unset CHEWBACCA_FAKE_SESSIONS
export CHEWBACCA_PATHSPEC_COMMIT=1

echo "  ${pass} passed, ${fail} failed"
[ "$fail" -eq 0 ]

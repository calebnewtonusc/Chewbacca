#!/bin/bash
# The pre-commit guard must refuse an index holding two sessions' work, and must
# stay silent when it cannot tell. On 2026-09-20 the guard existed since 18:49
# and commit 4a0b1df still absorbed another session's files at 21:44, because
# the only signal was mtime and a live session's files are fresh.
set -uo pipefail
SRC="$(cd "$(dirname "$0")/.." && pwd)/.githooks/pre-commit"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok(){ printf '  \033[0;32mpass\033[0m  %s\n' "$1"; pass=$((pass+1)); }
no(){ printf '  \033[0;31mfail\033[0m  %s\n' "$1"; fail=$((fail+1)); }

cd "$T" && git init -q . && git config user.email t@t.t && git config user.name t
mkdir .githooks && cp "$SRC" .githooks/ && git config core.hooksPath .githooks
export CHEWBACCA_WRITE_LOG="$T/wl.tsv" CHEWBACCA_PATHSPEC_COMMIT=1
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

echo "  ${pass} passed, ${fail} failed"
[ "$fail" -eq 0 ]

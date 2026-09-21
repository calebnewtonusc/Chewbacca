#!/bin/bash
# The Stop reminder must not push somebody toward committing another session's
# work. On 2026-09-21 it reported "4 uncommitted changes" for files a second
# live session had written seconds earlier and said "commit and push it". The
# volume noise in this hook had been fixed twice; the authorship noise never.
#
# It must also degrade to the old wording whenever it cannot tell, because a
# reminder suppressed on a bad day is worse than one that repeats itself.
set -uo pipefail
HOOK="$(cd "$(dirname "$0")/.." && pwd)/.claude/hooks/stop-check.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok(){ printf '  \033[0;32mpass\033[0m  %s\n' "$1"; pass=$((pass+1)); }
no(){ printf '  \033[0;31mfail\033[0m  %s\n' "$1"; fail=$((fail+1)); }

mkdir -p "$T/repo" "$T/home"
cd "$T/repo" && git init -q . && git config user.email t@t.t && git config user.name t
echo one > a.txt && git add a.txt && git commit -qm init
R="$(pwd -P)"; LOG="$T/wl.tsv"

# Each run gets a fresh HOME so the hook's own repeat-suppression fingerprint
# never decides one of these cases for us.
run(){ rm -rf "$T/home/.chewbacca"
  printf '{"session_id":"%s"}' "$1" | HOME="$T/home" CHEWBACCA_WRITE_LOG="$LOG" bash "$HOOK" 2>/dev/null; }
says(){ printf '%s' "$1" | grep -qF "$2"; }

echo changed > a.txt

rm -f "$LOG"
out="$(run me)"
says "$out" "commit and push it" && ok "no write log: the old wording, unchanged" || no "changed behaviour with no log"

printf '%s\tgavin-tab\t%s/a.txt\n' "$(date +%s)" "$R" > "$LOG"
out="$(run me)"
says "$out" "DIFFERENT session" && ok "another session's file: says do not commit it" || no "told the reader to commit another session's work"

printf '%s\tme\t%s/a.txt\n' "$(date +%s)" "$R" > "$LOG"
out="$(run me)"
says "$out" "commit and push it" && ok "own file: the old wording" || no "warned about the reader's own work"

echo two > b.txt && git add b.txt
printf '%s\tme\t%s/a.txt\n%s\tgavin-tab\t%s/b.txt\n' "$(date +%s)" "$R" "$(date +%s)" "$R" > "$LOG"
out="$(run me)"
says "$out" "never -A" && ok "mixed: says stage your own paths by name" || no "no warning on a mixed tree"

git checkout -q -- a.txt && git reset -q && rm -f b.txt
out="$(run me)"
[ -z "$out" ] && ok "clean tree: stays silent" || no "spoke about a clean tree"

echo "  ${pass} passed, ${fail} failed"
[ "$fail" -eq 0 ]

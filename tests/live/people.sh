#!/usr/bin/env bash
# Live: the `people` CLI on PATH is the real one, and it drives real SQLite.
#
# On 2026-09-07 the installed `people` was a stale COPY of the repo's, three days
# behind it. `events` and `merge` existed in the repo and not on PATH, the nightly
# scan had been silently dead the whole time, and nothing noticed, because
# doctor.sh asks "is `people` on PATH" and the answer was yes.
#
# The first check below is that bug, turned into a check. The rest drive the real
# binary against a scratch store, never the user's own.
source "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
need people "— run: chewbacca setup"

# Scoped before ANY invocation. `people add --help` is still an add, and a
# probe that writes to the real store is a check that damages what it measures.
export PEOPLE_DIR="$LIVE_SCRATCH/people"

BIN="$(command -v people)"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 1. Installed is a SYMLINK into a checkout, not a copy. A copy is how the store
#    goes three days stale while every surface reports healthy.
ok     "the installed people is a symlink, not a copy" test -L "$BIN"
mutant "a regular file would pass a bare -e check" test -L "$REPO/bin/people.NOPE"

# 2. Everything the skills promise is actually reachable on THIS binary. A stale
#    copy passes --help and fails the subcommand the skill told Claude to call.
# Two different failures, so two different checks. A subcommand can exist and
# be undocumented (Claude never calls it), or be documented and gone (Claude
# calls it and it dies). Only the second is fatal; the first is still a bug.
# Probed by what the CLI says, not by exit code. A known subcommand called with
# no arguments and an unknown one BOTH exit 1 — correctly, they are both errors.
# The only thing that separates "this verb is gone" from "you called it wrong"
# is the `unknown command` message, so that is what this reads. Invoking the
# verb for real is not an option: `add` would write.
for sub in add note log show list merge dedupe events tasks rank; do
  ok "subcommand '$sub' is reachable" \
    bash -c "! lt 20 '$BIN' $sub 2>&1 | grep -qF 'unknown command'"
done
for sub in add note log show list tasks rank merge dedupe events; do
  if ! lt 20 "$BIN" --help 2>&1 | grep -qF -- "$sub"; then
    unproven "'$sub' works but is missing from --help, so nothing tells Claude it exists"
  fi
done
mutant "a subcommand that was never written is refused" \
  bash -c "lt 20 '$BIN' teleport >/dev/null 2>&1"

# 3. Round trip through real SQLite, in scratch. Proves the binary WRITES, not
#    just that it prints help.
ok     "add writes to a real store"        lt 20 "$BIN" add "Live Check" --company Acme
says   "show reads back what add wrote" "Acme" lt 20 "$BIN" show "live check"
ok     "the db file exists"                test -f "$PEOPLE_DIR/people.db"
ok     "sqlite considers it intact"        bash -c "sqlite3 '$PEOPLE_DIR/people.db' 'pragma integrity_check' | grep -qx ok"
mutant "a person never added is not found" lt 20 "$BIN" show "nobody at all ever"

# 4. The user's REAL store, read only. Unproven rather than failed when absent:
#    a fresh machine has no store yet and that is not a broken install.
REAL="${HOME}/.chewbacca/people/people.db"
if [ -f "$REAL" ]; then
  ok "the real store passes integrity check" \
    bash -c "sqlite3 'file:$REAL?mode=ro' 'pragma integrity_check' | grep -qx ok"
  N="$(sqlite3 "file:$REAL?mode=ro" 'select count(*) from people' 2>/dev/null || echo 0)"
  ok "the real store has people in it ($N)" test "$N" -gt 0
else
  unproven "no real store at $REAL yet"
fi

finish

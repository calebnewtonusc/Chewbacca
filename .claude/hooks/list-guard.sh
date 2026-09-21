#!/bin/bash
# Stop: refuse to end a turn that produced an outbound list nobody checked.
#
# WHY THIS EXISTS. On 2026-09-20 this kit built five investor lists and reported
# them finished four times running. Every time, Caleb said "I have a feeling you
# still are stupid", and every time reading the OUTPUT found defects the code
# review had missed: 2,121 people on more than one list, eleven partners at one
# fund, info@ mailboxes, analysts who cannot write a cheque, and 843 rows whose
# company name was the literal string "Company".
#
# All of it was then written up as guidance in a skill, which is the same mistake
# craft-gate exists to fix: this repo is full of good judgment in markdown and
# almost none of it fires. So the guidance is a program now, and this runs it
# without being asked.
#
# Advisory in the same way prose-guard is advisory. It puts the failures into
# context so they get fixed before the lists are handed over, rather than after
# somebody sends 2,121 duplicate emails.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" 2>/dev/null || true
type hook_init >/dev/null 2>&1 && hook_init list-guard.sh 20

command -v jq >/dev/null 2>&1 || exit 0
GATE=$(command -v list-gate || echo "$HOME/.local/bin/list-gate")
[ -x "$GATE" ] || exit 0

# Only look at CSVs this turn actually touched, in the working directory.
CANDIDATES=$(find . -maxdepth 3 -name '*.csv' -newermt '-20 minutes' \
             -not -path './.git/*' -not -path './node_modules/*' 2>/dev/null | head -40)
[ -n "$CANDIDATES" ] || exit 0

# A contact list, not any CSV. Needs an email-ish and a name-ish column.
LISTS=""
while IFS= read -r f; do
  head -1 "$f" 2>/dev/null | grep -qiE '(^|,)"?(email|email_address|work_email)"?(,|$)' || continue
  head -1 "$f" 2>/dev/null | grep -qiE '(full_name|fullname|name|organization|company)' || continue
  LISTS="$LISTS $f"
done <<< "$CANDIDATES"
[ -n "${LISTS// /}" ] || exit 0

# shellcheck disable=SC2086
REPORT=$("$GATE" $LISTS 2>/dev/null) && exit 0
DETAIL=$(printf '%s' "$REPORT" | grep -E '^\s+(FAIL|warn)' | head -25)
[ -n "$DETAIL" ] || exit 0

jq -n --arg d "$DETAIL" '{
  hookSpecificOutput: {
    hookEventName: "Stop",
    additionalContext: ("list-gate refused the outbound lists in this directory:\n" + $d +
      "\n\nThese are defects that shipped four times on 2026-09-20 before anyone read the " +
      "output files. Fix the generator and regenerate, then rerun `list-gate <files>`. " +
      "Do not describe these lists as finished until it exits 0.")
  }
}' 2>/dev/null || true
exit 0

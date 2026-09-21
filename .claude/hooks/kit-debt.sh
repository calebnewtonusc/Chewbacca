#!/bin/bash
# Stop: say so when a session shipped work everywhere except the kit.
#
# WHY. On 2026-09-20 Caleb asked four times whether Chewbacca had been updated
# with what the session learned, and finally said "I shouldn't hv to keep asking
# this bruv". The standing rule went into memory as prose, which is the same
# failure craft-gate and list-gate exist to name. So the rule runs now.
#
# Advisory, like prose-guard. It puts the debt into context so it gets paid
# before anyone says the session is finished.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" 2>/dev/null || true
type hook_init >/dev/null 2>&1 && hook_init kit-debt.sh 15

command -v jq >/dev/null 2>&1 || exit 0
TOOL=$(command -v kit-debt || echo "$HOME/.local/bin/kit-debt")
[ -x "$TOOL" ] || exit 0

REPORT=$("$TOOL" --terse 2>/dev/null) && exit 0
[ -n "$REPORT" ] || exit 0

jq -n --arg d "$REPORT" '{
  hookSpecificOutput: {
    hookEventName: "Stop",
    additionalContext: ($d + "\n\nDo this before telling Caleb the session is done.")
  }
}' 2>/dev/null || true
exit 0

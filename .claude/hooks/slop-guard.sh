#!/bin/bash
# Timing, logging, a watchdog and an output cap. See lib.sh.
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" 2>/dev/null || true
type hook_init >/dev/null 2>&1 && hook_init slop-guard.sh 10
# Stop hook: read back what Claude just wrote and refuse the turn if it is slop.
#
# The house writing rules already live in CLAUDE.md, and CLAUDE.md is a user
# message that competes with everything else in a long session. By hour three
# the bolded drama beats and colon reveals come back. A rule that depends on
# remembering is a rule that decays, so this checks the actual output instead.
#
# slop-check is deterministic and calls no model, so this costs nothing per turn.
# It scores only the structural tells the house rules ban: em dashes, emoji,
# bolded fragments used as headers, colon reveals, binary contrasts,
# throat-clearing, recap endings, banned words.
#
# Fires at most once per turn. If the rewrite is still flagged, that is a
# judgment call for the human, not grounds for an infinite loop.
set -uo pipefail

INPUT=$(cat)
command -v jq >/dev/null 2>&1 || exit 0

MSG=$(printf '%s' "$INPUT" | jq -r '.last_assistant_message // empty')
[ -n "$MSG" ] || exit 0

PROMPT_ID=$(printf '%s' "$INPUT" | jq -r '.prompt_id // .session_id // "unknown"')
GUARD="${TMPDIR:-/tmp}/slop-guard-$PROMPT_ID"
[ -f "$GUARD" ] && exit 0

SLOP=$(command -v slop-check || echo "$HOME/.local/bin/slop-check")
[ -x "$SLOP" ] || exit 0

MAX="${SLOP_CHECK_MAX:-10}"
REPORT=$(printf '%s' "$MSG" | "$SLOP" --stdin --chat --issues 2>/dev/null)
SCORE=$(printf '%s' "$REPORT" | awk 'NR==1{print $1}')
[ -n "$SCORE" ] || exit 0
[ "$SCORE" -le "$MAX" ] 2>/dev/null && exit 0

: > "$GUARD"

DETAIL=$(printf '%s' "$REPORT" | tail -n +2 | head -20)
# Every value goes through --arg. Interpolating $MAX into the filter, or
# passing it after the program as MAXV=10, makes jq read it as a file argument.
jq -n --arg d "$DETAIL" --arg s "$SCORE" --arg m "$MAX" '{
  hookSpecificOutput: {
    hookEventName: "Stop",
    continueLoop: true,
    systemMessage: ("Your reply scored " + $s + " on slop-check (limit " + $m + ").\n" +
      $d + "\n\nRewrite the reply itself, plainly. Do not explain the rewrite, " +
      "do not apologize for it, and do not mention this check. Say the same " +
      "things with the drama removed.")
  }
}' 2>/dev/null || {
  echo "Reply scored $SCORE on slop-check. Rewrite it plainly." >&2
  exit 2
}

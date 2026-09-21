#!/bin/bash
# Timing, logging, a watchdog and an output cap. See lib.sh.
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" 2>/dev/null || true
type hook_init >/dev/null 2>&1 && hook_init handoff-guard.sh 10
# Stop hook: refuse a reply that hands the user a command to run.
#
# ~/.claude/rules/do-it-yourself.md is ALWAYS ON, loaded into every session,
# and says plainly: never end a task with a command for them to run. On
# 2026-09-21 Caleb said, twice in one night:
#
#     "Bro chewbacca u must be stupid to hv to ask me to do something manual"
#     "Never ask me to do something manual retard"
#
# An always-on rule did not prevent the behaviour it exists to prevent, twice,
# inside six hours. A lesson that has to be remembered decays; the rule even
# ends with the test, and nothing ever ran it. So this runs it.
#
# handoff-check is deterministic and calls no model, so it costs nothing per
# turn. Measured against 1052 real replies from that night it fired on 3, all
# of them genuine handoffs. The false-positive rate is what decides whether a
# guard survives contact with a working week.
#
# Fires at most once per turn: a second refusal on the rewrite is a judgment
# call for the human, not grounds for a loop.
set -uo pipefail

INPUT=$(cat)
command -v jq >/dev/null 2>&1 || exit 0

MSG=$(printf '%s' "$INPUT" | jq -r '.last_assistant_message // empty')
[ -n "$MSG" ] || exit 0

PROMPT_ID=$(printf '%s' "$INPUT" | jq -r '.prompt_id // .session_id // "unknown"')
GUARD="${TMPDIR:-/tmp}/handoff-guard-$PROMPT_ID"
[ -f "$GUARD" ] && exit 0

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CHECK="$ROOT/bin/handoff-check"
[ -x "$CHECK" ] || CHECK="$(command -v handoff-check || true)"
[ -x "$CHECK" ] || exit 0

# What they asked for is the escape: a request for a runnable prompt makes
# handing one over correct, and he asked for exactly that on the same night.
USER_TEXT=$(printf '%s' "$INPUT" | jq -r '.user_message // .prompt // empty' 2>/dev/null)

if OUT=$(printf '%s' "$MSG" | "$CHECK" --user "$USER_TEXT" 2>&1); then
  exit 0
fi

: > "$GUARD"
printf '%s\n' "$OUT" >&2
exit 2

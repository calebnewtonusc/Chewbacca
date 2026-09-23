#!/bin/bash
# Timing, logging, a watchdog and an output cap. See lib.sh.
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" 2>/dev/null || true
type hook_init >/dev/null 2>&1 && hook_init agent-claim-guard.sh 10
# Stop hook: refuse a reply that says background work is running when nothing
# in this turn proves it was launched.
#
# 2026-09-23. A subagent from a previous session was resumed with SendMessage,
# which returned {"success":true,"resumedAgentId":"a94eaff..."}. Nothing
# started. The reply went out saying "I've resumed that agent and it hasn't
# reported yet", and Caleb was the one who noticed: "Not seeing that agent
# running?" A later ListAgents showed four peer sessions and zero subagents.
#
# SendMessage reporting success means the message was accepted, NOT that an
# agent is alive and working. That is the same class as
# feedback_built_but_never_fires: the thing reporting success was not doing
# the work. So the only evidence this accepts is a real launch in this turn,
# or a live listing.
#
# Fires at most once per turn.
set -uo pipefail

INPUT=$(cat)
command -v jq >/dev/null 2>&1 || exit 0

MSG=$(printf '%s' "$INPUT" | jq -r '.last_assistant_message // empty')
[ -n "$MSG" ] || exit 0

TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty')
[ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] || exit 0

PROMPT_ID=$(printf '%s' "$INPUT" | jq -r '.prompt_id // .session_id // "unknown"')
GUARD="${TMPDIR:-/tmp}/agent-claim-guard-$PROMPT_ID"
[ -f "$GUARD" ] && exit 0

# Claims that background work is in flight. Deliberately narrow: "the build is
# running" and "the dev server is running" are not agent claims and must not
# trip this.
CLAIM_RE='(spawn(ed|ing)?|launch(ed|ing)?|resum(ed|ing)|kick(ed)? off|fann?(ed|ing) out|dispatch(ed)?)[^.]{0,60}(agent|research|subagent|in the background)'
CLAIM_RE2='(agent|research|subagent)[^.]{0,60}(is |are |still )?(running|in flight|in the background|working on)'
CLAIM_RE3="(hasn't|has not|have not|haven't) (reported|come back|returned|landed)"

echo "$MSG" | grep -qiE "$CLAIM_RE|$CLAIM_RE2|$CLAIM_RE3" || exit 0

# Evidence. Only two things count.
#
#   1. The Agent tool actually launched something this turn. Its result string
#      is fixed, so this is an exact match rather than a guess.
#   2. A ListAgents result in this turn showed at least one live subagent.
#
# Both are scoped to AFTER the last user message, because an agent launched an
# hour ago and long since reported is not evidence that one is running now.
LAST_USER_LINE=$(grep -n '"type":"user"' "$TRANSCRIPT" 2>/dev/null | tail -1 | cut -d: -f1)
[ -n "$LAST_USER_LINE" ] || LAST_USER_LINE=1
TAIL=$(tail -n "+$LAST_USER_LINE" "$TRANSCRIPT" 2>/dev/null)

LAUNCHED=0
printf '%s' "$TAIL" | grep -q "Async agent launched successfully" && LAUNCHED=1
# A ListAgents run that printed subagent rows, as opposed to only peer sessions.
printf '%s' "$TAIL" | grep -qE 'subagent|Agents \(([1-9])' && LAUNCHED=1

[ "$LAUNCHED" -eq 1 ] && exit 0

: > "$GUARD"

{
  echo "Your reply says background work is running, and nothing in this turn"
  echo "shows anything was launched."
  echo
  echo "A SendMessage that returns success only means the message was accepted."
  echo "It does not mean an agent is alive. On 2026-09-23 a resume returned"
  echo "{\"success\":true} for a dead agent, the reply claimed it was running,"
  echo "and ListAgents showed zero subagents."
  echo
  echo "Do one of these before saying it again:"
  echo "  - launch it with the Agent tool and check the result says launched"
  echo "  - run ListAgents and confirm the agent is actually listed"
  echo "  - or drop the claim and say plainly that it is not running"
  echo
  echo "Do not explain this check or apologise for it."
} >&2
exit 2

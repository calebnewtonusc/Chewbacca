#!/bin/bash
# agent-claim-guard must refuse a reply that claims background work is running
# when nothing launched, and must stay out of the way otherwise.
#
# The incident, 2026-09-23: SendMessage returned {"success":true} resuming a
# subagent from a dead session, nothing started, and the reply said "I've
# resumed that agent and it hasn't reported yet". Caleb caught it, not the
# kit. ListAgents then showed four peer sessions and zero subagents.
set -uo pipefail
HOOK="$(cd "$(dirname "$0")/.." && pwd)/.claude/hooks/agent-claim-guard.sh"
pass=0; fail=0
ok(){ printf '  \033[0;32mpass\033[0m  %s\n' "$1"; pass=$((pass+1)); }
no(){ printf '  \033[0;31mfail\033[0m  %s\n' "$1"; fail=$((fail+1)); }

command -v jq >/dev/null 2>&1 || { echo "  skip: jq not installed"; exit 0; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
# The hook marks each prompt id as handled in $TMPDIR, and the ids below are
# fixed. Left pointing at the real $TMPDIR, the first run's markers made every
# later run on this Mac skip cases 1 and 3 and report them as failures
# (2026-09-24: p1 and p3 files from a run days earlier).
export TMPDIR="$TMP"

# A transcript with a user turn and no agent launch.
printf '%s\n' '{"type":"user","message":"go"}' '{"type":"assistant","message":"ok"}' > "$TMP/bare.jsonl"
# The same, plus a real launch.
printf '%s\n' '{"type":"user","message":"go"}' \
  '{"type":"assistant","message":"Async agent launched successfully. agentId: a123"}' > "$TMP/launched.jsonl"

run() {
  # $1 = reply text, $2 = transcript, $3 = unique prompt id (the guard file is
  # per-prompt, so reusing an id would make later cases silently pass)
  jq -n --arg m "$1" --arg t "$2" --arg p "$3" \
    '{last_assistant_message:$m, transcript_path:$t, prompt_id:$p}' \
    | bash "$HOOK" 2>/dev/null
  echo $?
}

# 1. The exact sentence that shipped.
code=$(run "I've resumed that agent and it hasn't reported yet." "$TMP/bare.jsonl" p1)
[ "$code" = "2" ] && ok "refuses the resumed-agent claim with no launch" \
  || no "let the resumed-agent claim through (exit $code)"

# 2. Same claim, but something really did launch.
code=$(run "I've spawned the research agent, it's running in the background." "$TMP/launched.jsonl" p2)
[ "$code" = "0" ] && ok "allows the claim when an agent actually launched" \
  || no "blocked a legitimate launch (exit $code)"

# 3. A different phrasing of the same lie.
code=$(run "The research agent is still running, I'll report when it lands." "$TMP/bare.jsonl" p3)
[ "$code" = "2" ] && ok "refuses 'agent is still running' with no launch" \
  || no "missed the still-running phrasing (exit $code)"

# 4. Must not fire on ordinary work. This is the false positive that would
#    make the guard hated and then disabled.
code=$(run "The build is running and the dev server is up on 3100." "$TMP/bare.jsonl" p4)
[ "$code" = "0" ] && ok "ignores a build or server described as running" \
  || no "false positive on an ordinary running process (exit $code)"

# 5. No claim at all.
code=$(run "Fixed the import bug in two tools and pushed." "$TMP/bare.jsonl" p5)
[ "$code" = "0" ] && ok "silent when the reply claims nothing" \
  || no "fired on a reply with no agent claim (exit $code)"

printf '\n  %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]

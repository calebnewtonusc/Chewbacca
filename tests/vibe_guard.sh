#!/usr/bin/env bash
# The vibe guard must REFUSE a claim with no evidence, and must stay silent
# on an ordinary reply. A guard that has never refused anything is decoration:
# two authorship guards in this kit had never fired once.
set -uo pipefail
HOOK="$HOME/.claude/hooks/vibe-guard.sh"
[ -x "$HOOK" ] || { echo "vibe-guard not installed"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq absent, skipping"; exit 0; }

fail=0
probe() {                     # name, message, expected exit
  local out code
  out=$(printf '{"last_assistant_message":%s,"prompt_id":"t-%s"}' \
        "$(jq -Rn --arg m "$2" '$m')" "$RANDOM" | "$HOOK" 2>&1)
  code=$?
  if [ "$code" = "$3" ]; then
    printf '  ok    %s (exit %s)\n' "$1" "$code"
  else
    printf '  FAIL  %s: wanted exit %s got %s\n' "$1" "$3" "$code"
    printf '%s\n' "$out" | head -3 | sed 's/^/        /'
    fail=$((fail + 1))
  fi
}

echo "refuses an unevidenced claim:"
probe "safe to close"        "We're good to close this tab." 2
probe "claims a fix"         "That's fixed now."             2
probe "claims tests pass"    "All tests pass."               2

echo "stays out of the way otherwise:"
probe "reports a change"     "I changed the exponent from 2.5 to 1.35." 0
probe "reports a failure"    "Still a wedge, so my fix was partial."    0
probe "asks a question"      "Which of these two should it be?"         0

echo
[ "$fail" = 0 ] && echo "the guard fires when it should and not otherwise   ok" || echo "$fail failed"
exit "$fail"

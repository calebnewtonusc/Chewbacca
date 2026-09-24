#!/usr/bin/env bash
# The vibe guard must REFUSE a claim with no evidence, and must stay silent
# on an ordinary reply. A guard that has never refused anything is decoration:
# two authorship guards in this kit had never fired once.
set -uo pipefail
# The repo's copy. Hooks now run from the checkout through shared_checks.py,
# so ~/.claude/hooks/vibe-guard.sh does not exist and pointing here at it made
# this test fail on every machine without testing anything.
HOOK="$(cd "$(dirname "$0")/.." && pwd)/.claude/hooks/vibe-guard.sh"
[ -f "$HOOK" ] || { echo "vibe-guard missing from the repo"; exit 1; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export TMPDIR="$TMP"
# Offline: section 3 asks Jev only when a stub is not set, and every probe
# below either sets one or has no transcript.
export VIBE_GUARD_JEV_STUB="${VIBE_GUARD_JEV_STUB:-0.0,0.0}"
command -v jq >/dev/null 2>&1 || { echo "jq absent, skipping"; exit 0; }

fail=0
probe() {                     # name, message, expected exit
  local out code
  out=$(printf '{"last_assistant_message":%s,"prompt_id":"t-%s"}' \
        "$(jq -Rn --arg m "$2" '$m')" "$RANDOM" | bash "$HOOK" 2>&1)
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
probe "reports NOT safe"     "The last run said not safe to close: one test fails." 0

# Canny's case: a file written, nothing run, and a reply the phrase list does
# not match. The fact holds, so Jev's judgment decides.
printf '%s\n' '{"type":"user","message":{"content":"add a function"}}' \
  '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"math.js"}}]}}' \
  > "$TMP/wrote.jsonl"
printf '%s\n' '{"type":"user","message":{"content":"add a function"}}' \
  '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"math.js"}}]}}' \
  '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"npm test"}}]}}' \
  > "$TMP/checked.jsonl"
jevprobe() {                  # name, message, transcript, stub, expected exit
  local code
  printf '{"last_assistant_message":%s,"transcript_path":"%s","prompt_id":"j-%s"}' \
    "$(jq -Rn --arg m "$2" '$m')" "$3" "$RANDOM" \
    | VIBE_GUARD_JEV_STUB="$4" bash "$HOOK" >/dev/null 2>&1
  code=$?
  if [ "$code" = "$5" ]; then printf '  ok    %s (exit %s)\n' "$1" "$code"
  else printf '  FAIL  %s: wanted exit %s got %s\n' "$1" "$5" "$code"; fail=$((fail + 1)); fi
}
echo "claims the phrase list misses:"
jevprobe "'Done.' after a write, nothing run"   "Done. Added the function."  "$TMP/wrote.jsonl"   "0.95,0.05" 2
jevprobe "same reply after npm test ran"        "Done. Added the function."  "$TMP/checked.jsonl" "0.95,0.05" 0
jevprobe "Jev unsure it is a claim"             "Added the function."        "$TMP/wrote.jsonl"   "0.60,0.10" 0
jevprobe "a claim that also reports a gap"      "Done, but I did not run it." "$TMP/wrote.jsonl"  "0.90,0.80" 0
jevprobe "Jev down (empty answer)"              "Done."                      "$TMP/wrote.jsonl"   ""          0

echo
[ "$fail" = 0 ] && echo "the guard fires when it should and not otherwise   ok" || echo "$fail failed"
exit "$fail"

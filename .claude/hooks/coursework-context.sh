#!/bin/bash
# Timing, logging, a watchdog and an output cap. See lib.sh.
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" 2>/dev/null || true
type hook_init >/dev/null 2>&1 && hook_init coursework-context.sh 5
# SessionStart: put the next coursework deadlines into context before the first
# question. Silent when there is no CLI, no ledger, or nothing due, because an
# empty line every session is pure token cost.
#
# Kept as its own hook rather than folded into the Todoist one-liner in
# settings.json: that command is already a single string with several levels of
# escaping, and adding to it is how it becomes unreadable.

set -uo pipefail

command -v coursework >/dev/null 2>&1 || exit 0

# Cached, with one writer, for the same reason session-context.sh is: this hook
# had no cache at all, so every session start paid for the ledger read, and five
# starting at once contended until the 5s watchdog killed them. Five tabs opened
# in one second on 2026-09-15 and five of these died. See hook_cache_ready in
# lib.sh. The ledger invalidates the cache itself, so editing a syllabus shows up
# in the next session rather than whenever the TTL happens to run out.
CACHE="$HOME/.chewbacca/cache/coursework-context.json"
TTL="${CHEWBACCA_CONTEXT_TTL:-900}"

hook_cache_ready "$CACHE" "$TTL" "$HOME/coursework/courses"
case $? in
  0) type hook_emit >/dev/null 2>&1 && hook_emit < "$CACHE" || cat "$CACHE"; exit 0 ;;
  2) exit 0 ;;
esac

COURSEWORK_JSON="$(coursework due --days 10 --json 2>/dev/null || true)"
[ -n "$COURSEWORK_JSON" ] || exit 0
export COURSEWORK_JSON

python3 <<'PY' > "$CACHE.tmp"
import json, os

raw = os.environ.get("COURSEWORK_JSON", "")
try:
    data = json.loads(raw)
except Exception:
    raise SystemExit(0)

bits = []
for d in data.get("overdue", [])[:3]:
    bits.append(f"OVERDUE: {d['course']} {d['name']} (was due {d.get('date')})")
for d in data.get("upcoming", [])[:5]:
    bits.append(f"{d['course']} {d['name']} due {d.get('date')}")

if not bits:
    raise SystemExit(0)

print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": (
            "Coursework deadlines: " + "; ".join(bits) + ". "
            "Source: the ledger at ~/coursework. Run `coursework due`, "
            "`coursework attendance`, or `coursework policy <course> ai` "
            "rather than guessing, and never state a date you did not read."
        ),
    }
}))
PY

# An empty result is a valid answer worth caching: it means nothing was due, and
# recomputing that costs the same ledger read.
mv "$CACHE.tmp" "$CACHE" 2>/dev/null || rm -f "$CACHE.tmp"
[ -s "$CACHE" ] && { type hook_emit >/dev/null 2>&1 && hook_emit < "$CACHE" || cat "$CACHE"; }

exit 0

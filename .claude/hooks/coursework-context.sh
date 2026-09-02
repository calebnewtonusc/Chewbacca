#!/bin/bash
# SessionStart: put the next coursework deadlines into context before the first
# question. Silent when there is no CLI, no ledger, or nothing due, because an
# empty line every session is pure token cost.
#
# Kept as its own hook rather than folded into the Todoist one-liner in
# settings.json: that command is already a single string with several levels of
# escaping, and adding to it is how it becomes unreadable.

set -uo pipefail

command -v coursework >/dev/null 2>&1 || exit 0
COURSEWORK_JSON="$(coursework due --days 10 --json 2>/dev/null || true)"
[ -n "$COURSEWORK_JSON" ] || exit 0
export COURSEWORK_JSON

python3 <<'PY'
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

exit 0

#!/bin/bash
# Stop: remind about unpushed work, but only when there actually is any.
#
# The previous version fired the same "push to GitHub now" reminder at the end
# of every turn, including turns where nothing changed. An unconditional
# reminder is noise, and noise gets ignored, so the one time it matters it does
# not land. This exits silently unless the repo has uncommitted changes or
# commits ahead of its upstream.

set -uo pipefail

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

DIRTY_COUNT="$(git status --porcelain 2>/dev/null | grep -c . || true)"
AHEAD_COUNT=0
NO_UPSTREAM=0

if git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
  AHEAD_COUNT="$(git rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)"
elif git remote | grep -q .; then
  # A remote exists but this branch does not track anything, so nothing here
  # has ever been pushed.
  NO_UPSTREAM=1
fi

[ "$DIRTY_COUNT" -eq 0 ] && [ "$AHEAD_COUNT" -eq 0 ] && [ "$NO_UPSTREAM" -eq 0 ] && exit 0

export DIRTY_COUNT AHEAD_COUNT NO_UPSTREAM
export BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"

python3 <<'PY'
import json, os

dirty = int(os.environ.get("DIRTY_COUNT", "0"))
ahead = int(os.environ.get("AHEAD_COUNT", "0"))
no_upstream = os.environ.get("NO_UPSTREAM", "0") == "1"
branch = os.environ.get("BRANCH", "?")

bits = []
if dirty:
    bits.append(f"{dirty} uncommitted change{'s' if dirty != 1 else ''}")
if ahead:
    bits.append(f"{ahead} commit{'s' if ahead != 1 else ''} not pushed")
if no_upstream:
    bits.append(f"branch '{branch}' has no upstream, so nothing here is pushed")

print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "Stop",
        "additionalContext": (
            f"Uncommitted or unpushed work in this repo: {'; '.join(bits)}. "
            "If the work is finished, commit and push it. If it is mid-flight, ignore this."
        ),
    }
}))
PY

exit 0

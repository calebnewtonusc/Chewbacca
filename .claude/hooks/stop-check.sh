#!/bin/bash
# Timing, logging, a watchdog and an output cap. See lib.sh.
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" 2>/dev/null || true
type hook_init >/dev/null 2>&1 && hook_init stop-check.sh 10
# Stop: remind about unpushed work, but only when there actually is any.
#
# The previous version fired the same "push to GitHub now" reminder at the end
# of every turn, including turns where nothing changed. An unconditional
# reminder is noise, and noise gets ignored, so the one time it matters it does
# not land. This exits silently unless the repo has uncommitted changes or
# commits ahead of its upstream.

set -uo pipefail

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# A home directory under git is somebody's dotfiles repo, and `git status`
# there reports Library, Downloads, .ssh and every cache on the machine as
# untracked work. That fired "183 uncommitted changes" at the end of every
# turn in a session whose actual repos were clean and pushed, three times in a
# row, which is exactly the unconditional-noise failure this hook was rewritten
# to stop doing. Acting on it would stage the user's credentials.
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo)"
[ "$REPO_ROOT" = "$HOME" ] && exit 0

# Count what was actually touched, not what happens to be lying around.
#
# A workspace directory that holds many project repos is itself often under
# git, and `git status` there reports every sibling project, cache and scratch
# folder as untracked. That reported "110 uncommitted changes" at the end of a
# session whose real repos were clean and pushed, and buried the one tracked
# file that had genuinely changed. A number that large is a description of the
# environment, not of the turn, and acting on it means `git add -A` in a folder
# full of somebody else's work.
#
# So untracked entries stop counting once there are more of them than anyone
# could have created in one session. Tracked changes always count, however many
# there are, because those are files that were edited on purpose.
TRACKED_COUNT="$(git status --porcelain 2>/dev/null | grep -vc '^??' || true)"
UNTRACKED_COUNT="$(git status --porcelain 2>/dev/null | grep -c '^??' || true)"
UNTRACKED_NOISE_FLOOR=25

if [ "$UNTRACKED_COUNT" -gt "$UNTRACKED_NOISE_FLOOR" ]; then
  DIRTY_COUNT="$TRACKED_COUNT"
else
  DIRTY_COUNT="$((TRACKED_COUNT + UNTRACKED_COUNT))"
fi
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

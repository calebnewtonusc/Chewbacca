#!/bin/bash
# Timing, logging, a watchdog and an output cap. See lib.sh.
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" 2>/dev/null || true
type hook_init >/dev/null 2>&1 && hook_init kit-autopull.sh 20
# SessionStart: fast-forward the kit repo, so a session never starts on a stale
# copy of it.
#
# THE OTHER HALF OF kit-autopush. That hook's own comment names the problem it
# was fixing: "Explicitly means a person remembering." `chewbacca update` has
# always been able to pull, and it has always needed somebody to run it. So the
# kit pushed itself and never pulled itself, and two machines drifted in the one
# direction nobody was watching. A contributor put 159 commits into a fork in
# four days; anybody in that position starts every session behind.
#
# WHAT THIS WILL NOT DO, because an automatic pull is only acceptable if it
# cannot lose work:
#
#   - It never touches a dirty working tree. Uncommitted work is the thing
#     most expensive to lose and the thing a merge is most likely to eat.
#   - It is --ff-only. No merge commit, no rebase, no conflict to resolve at
#     session start. If it cannot fast-forward it says so and stops.
#   - It never stashes, resets, checks out or cleans. Nothing here rewrites
#     anything the user has not already committed.
#   - main only, origin only. Same reasoning as the push half: a feature branch
#     is somebody mid-thought.
#
# So the worst case is that it declines and prints why.

set -uo pipefail

LOG_DIR="${CHEWBACCA_LOG_DIR:-$HOME/.chewbacca/logs}"
LOG="$LOG_DIR/autopull.log"
mkdir -p "$LOG_DIR" 2>/dev/null || true
note() { echo "$(date -u +%FT%TZ) $*" >> "$LOG" 2>/dev/null || true; }

say() {
  MSG="$1" python3 <<'PY'
import json, os
print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart",
      "additionalContext": os.environ.get("MSG", "")}}))
PY
}

# ── Which repo ────────────────────────────────────────────────────────────────
# Resolved exactly as kit-autopush resolves it, and for the same reason: an
# explicit env value wins so a test harness never points this at a real
# checkout.
REPO="${CHEWBACCA_REPO_DIR:-}"
if [ -z "$REPO" ]; then
  CONFIG="$HOME/.claude/d1-config.sh"
  # shellcheck source=/dev/null
  [ -f "$CONFIG" ] && . "$CONFIG"
  REPO="${CHEWBACCA_REPO_DIR:-}"
fi
if [ -z "$REPO" ] && [ -f "$HOME/.chewbacca/install-manifest.json" ]; then
  REPO="$(python3 -c '
import json, sys
try:
    print(json.load(open(sys.argv[1])).get("repo", ""))
except Exception:
    print("")
' "$HOME/.chewbacca/install-manifest.json" 2>/dev/null)"
fi
[ -n "$REPO" ] || exit 0
[ -d "$REPO/.git" ] || exit 0
cd "$REPO" || exit 0

# ── Throttle ──────────────────────────────────────────────────────────────────
# A fetch is a network round trip and SessionStart runs on every new session.
# Once an hour keeps a long day current without paying for it on every window.
STAMP="$LOG_DIR/.autopull-stamp"
NOW="$(date +%s)"
INTERVAL="${CHEWBACCA_PULL_INTERVAL:-3600}"
if [ -f "$STAMP" ]; then
  LAST="$(cat "$STAMP" 2>/dev/null || echo 0)"
  case "$LAST" in (*[!0-9]*|"") LAST=0 ;; esac
  [ $((NOW - LAST)) -lt "$INTERVAL" ] && exit 0
fi

# ── Refuse on anything that could cost work ───────────────────────────────────
BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '')"
if [ "$BRANCH" != "main" ]; then
  note "skipped: on branch '$BRANCH'"
  exit 0
fi

git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1 || exit 0
TRACKED_REMOTE="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null | cut -d/ -f1)"
if [ -n "$TRACKED_REMOTE" ] && [ "$TRACKED_REMOTE" != "origin" ]; then
  note "refused: branch tracks '$TRACKED_REMOTE', not origin"
  exit 0
fi

# THE ONE THAT MATTERS. A dirty tree is never fast-forwarded into.
if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
  note "refused: working tree is dirty"
  exit 0
fi

echo "$NOW" > "$STAMP" 2>/dev/null || true

# ── Fetch and fast-forward ────────────────────────────────────────────────────
git fetch origin --quiet 2>/dev/null || { note "fetch failed"; exit 0; }

BEHIND="$(git rev-list --count 'HEAD..@{u}' 2>/dev/null || echo 0)"
case "$BEHIND" in (*[!0-9]*|"") BEHIND=0 ;; esac
[ "$BEHIND" -gt 0 ] || exit 0

BEFORE="$(git rev-parse HEAD 2>/dev/null)"
if ! git merge --ff-only '@{u}' --quiet 2>/dev/null; then
  note "could not fast-forward, $BEHIND commit(s) behind"
  say "Kit repo is $BEHIND commit(s) behind origin/main and could not fast-forward, so nothing was changed. The local branch has diverged. Resolve it before relying on anything in the kit being current."
  exit 0
fi
AFTER="$(git rev-parse HEAD 2>/dev/null)"

CHANGED="$(git diff --name-only "$BEFORE..$AFTER" 2>/dev/null)"
SUBJECTS="$(git log --oneline --no-decorate "$BEFORE..$AFTER" 2>/dev/null | head -10)"
note "pulled $BEHIND commit(s)"

# Pulling code is not installing it. setup.sh is what puts hooks, skills and
# tools where the agent reads them, so a pull that touched any of those left
# the machine running the old copy. Say so, and say it as a fact rather than
# as a chore for the user: the agent reads this and can run it.
NEEDS_SETUP=""
case "$CHANGED" in
  *setup.sh*|*.claude/hooks/*|*skills/*|*bin/*|*commands/*) NEEDS_SETUP=1 ;;
esac

MSG="Kit repo fast-forwarded $BEHIND commit(s) from origin/main:
$SUBJECTS"
if [ -n "$NEEDS_SETUP" ]; then
  MSG="$MSG

This pull touched setup.sh, hooks, skills, bin or commands, so what is installed
under ~/.claude and ~/.local/bin is now older than the repo. Run 'chewbacca setup'
to install what was just pulled."
fi
say "$MSG"
exit 0

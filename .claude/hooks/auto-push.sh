#!/bin/bash
# Timing, logging, a watchdog and an output cap. See lib.sh.
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" 2>/dev/null || true
type hook_init >/dev/null 2>&1 && hook_init auto-push.sh 20
# Stop: push finished work to the user's own remote without being asked.
#
# The friction this removes: a session ends with a real commit sitting on the
# machine, stop-check.sh prints "1 commit not pushed", and the next turn is
# spent asking a human whether to push their own work to their own fork. That
# happened three times in one session before this existed.
#
# What it deliberately does NOT do:
#
#   1. It never commits. format-and-sync.sh auto-commits prose in the context
#      repos, where "chore: update NOW.md" is an honest message. Code is not
#      prose: an auto-commit here would invent a message for a change it did
#      not understand and would ship whatever half-written state the tree was
#      in when the turn happened to end. Committing stays a decision.
#   2. It only ever pushes to `origin`. This repo also has an `upstream`
#      pointing at somebody else's public main, and a hook that pushed there
#      would put unreviewed work on another person's project. Forks are the
#      whole reason origin and upstream are different words.
#   3. It only runs inside directories on an explicit allowlist. A hook that
#      pushed from whatever repo happened to be the working directory would
#      eventually push a client's private repo somewhere.
#
# Allowlist lives in ~/.claude/d1-config.sh as AUTOPUSH_DIRS, colon separated.

set -uo pipefail

CONFIG="$HOME/.claude/d1-config.sh"
# shellcheck source=/dev/null
[ -f "$CONFIG" ] && . "$CONFIG"

AUTOPUSH_DIRS="${AUTOPUSH_DIRS:-}"
[ -n "$AUTOPUSH_DIRS" ] || exit 0

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo)"
[ -n "$REPO_ROOT" ] || exit 0
[ "$REPO_ROOT" = "$HOME" ] && exit 0

on_allowlist() {
  local want="$1" entry
  local IFS=:
  for entry in $AUTOPUSH_DIRS; do
    [ -n "$entry" ] || continue
    entry="${entry%/}"
    [ "$want" = "$entry" ] && return 0
  done
  return 1
}
on_allowlist "$REPO_ROOT" || exit 0

git -C "$REPO_ROOT" remote | grep -qx origin || exit 0

BRANCH="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo)"
[ -n "$BRANCH" ] && [ "$BRANCH" != "HEAD" ] || exit 0

# Nothing to send. Uncommitted work is not this hook's business, so a dirty
# tree with no commits ahead exits quietly and stop-check.sh still nags.
# Count against origin/BRANCH, which is where this hook actually pushes, not
# against @{u}. On a fork those are routinely different: a branch tracking
# upstream/main reads as "ahead" whenever local is ahead of the other
# project, so the old check passed on every turn, pushed a no-op to origin,
# got exit 0 from "Everything up-to-date", and announced a push that never
# happened. It fired seven times in one session before anyone read the hook.
if git -C "$REPO_ROOT" rev-parse --verify --quiet "origin/$BRANCH" >/dev/null 2>&1; then
  AHEAD="$(git -C "$REPO_ROOT" rev-list --count "origin/$BRANCH..HEAD" 2>/dev/null || echo 0)"
  [ "$AHEAD" -gt 0 ] || exit 0
  SET_UPSTREAM=0
else
  SET_UPSTREAM=1
fi

# A credential pushed to a public fork is public the moment it lands, and
# deleting the commit afterward does not un-publish it. The repo ships a
# scanner that matches on credential context rather than vendor prefix, so it
# is cheap enough to run on every push. If it finds something, say so and push
# nothing: a blocked push costs a turn, a leaked key costs a rotation.
SCAN="$REPO_ROOT/bin/secret-scan"
SCAN_NOTE=""
if [ -x "$SCAN" ]; then
  if ! SCAN_OUT="$("$SCAN" "$REPO_ROOT" 2>&1)"; then
    export SCAN_OUT REPO_ROOT
    python3 <<'PY'
import json, os
out = os.environ.get("SCAN_OUT", "").strip()[:800]
print(json.dumps({"hookSpecificOutput": {"hookEventName": "Stop", "additionalContext":
  "Auto-push refused: secret-scan flagged something in "
  f"{os.environ.get('REPO_ROOT','the repo')}. Nothing was pushed. Fix or confirm, "
  f"then push by hand.\n{out}"}}))
PY
    exit 0
  fi
fi

if [ "$SET_UPSTREAM" = "1" ]; then
  PUSH_OUT="$(git -C "$REPO_ROOT" push -u origin "$BRANCH" 2>&1)"; RC=$?
else
  PUSH_OUT="$(git -C "$REPO_ROOT" push origin "$BRANCH" 2>&1)"; RC=$?
fi

REMOTE_URL="$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || echo origin)"
export PUSH_OUT RC BRANCH REMOTE_URL SCAN_NOTE

python3 <<'PY'
import json, os
rc = os.environ.get("RC", "1")
branch = os.environ.get("BRANCH", "?")
url = os.environ.get("REMOTE_URL", "origin")
out = os.environ.get("PUSH_OUT", "").strip()[:600]
if rc == "0":
    msg = f"Auto-pushed {branch} to {url}. Tell the user it went up, with the URL."
else:
    msg = (f"Auto-push of {branch} to {url} FAILED. Nothing is on the remote. "
           f"Tell the user and say why.\n{out}")
print(json.dumps({"hookSpecificOutput": {"hookEventName": "Stop", "additionalContext": msg}}))
PY

exit 0

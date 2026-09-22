#!/bin/bash
# Timing, logging, a watchdog and an output cap. See lib.sh.
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" 2>/dev/null || true
type hook_init >/dev/null 2>&1 && hook_init kit-autopush.sh 30
# Stop: push the kit repo's committed work, so a fix never stays on one laptop.
#
# THE FAILURE THIS EXISTS FOR. format-and-sync.sh auto-commits and auto-pushes
# the context store, and d1-config.sh said of the kit itself: "Chewbacca is its
# own repo and is pushed explicitly." Explicitly means a person remembering,
# and the same assumption in sync-chewbacca.sh is why commit cfb8001 sat on
# this machine unpushed until a SessionStart check happened to look. A fix that
# exists only here is a fix nobody else got, and every install pulls from the
# remote.
#
# So the remote is now the default rather than the reward for remembering.
#
# WHAT THIS DOES NOT DO. It never commits. A context store is notes and a
# half-written note is still a note; a code repo mid-session holds a function
# with no caller and a test that does not run yet, and "chore: update file.sh"
# across forty of those is an unreadable history and a broken main. Committing
# stays a deliberate act. stop-check.sh still reports uncommitted work.
#
# WHY IT IS GATED. A push to main runs CI, and an auto-push is exactly the
# push nobody is watching. Shipping a stale SHA256SUMS.txt means the checksums
# published for `curl | bash` are lying, which is worse than not publishing.
# So the cheap half of CI runs here first, locally, in about two seconds. A
# gate that fails blocks the push and says which one and why, and that message
# reaches the session rather than a log nobody opens.

set -uo pipefail

# CHEWBACCA_LOG_DIR is what tests/run.sh redirects to keep a run hermetic.
# Writing straight to $HOME meant the suite appended twenty rows to the real
# log, which is somebody else's history on somebody else's machine.
LOG_DIR="${CHEWBACCA_LOG_DIR:-$HOME/.chewbacca/logs}"
LOG="$LOG_DIR/autopush.log"
mkdir -p "$LOG_DIR" 2>/dev/null || true
note() { echo "$(date -u +%FT%TZ) $*" >> "$LOG" 2>/dev/null || true; }

# ── Which repo ────────────────────────────────────────────────────────────────
#
# The install manifest records where the kit was installed from, so this works
# on a machine that keeps it somewhere other than the author's path. An env
# override wins, for a second checkout or a test.
# An explicit environment value wins over the config file. d1-config.sh uses
# plain assignment, so sourcing it unconditionally would clobber an override
# and point this at the author's real checkout. That is how a test harness
# ends up pushing the actual repo.
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

# ── Is there anything to push ─────────────────────────────────────────────────
git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1 || exit 0
AHEAD="$(git rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)"
[ "$AHEAD" -gt 0 ] 2>/dev/null || exit 0

# THE UPSTREAM MUST BE ORIGIN. A contributor's guard, from his fork's
# .claude/hooks/auto-push.sh. A fork has both origin and upstream, the
# ahead-count above is computed against whatever the branch tracks, and the
# push below goes to origin. When those are different remotes the count does
# not describe the push, and the push can publish commits nobody measured.
# His framing: forks are the whole reason origin and upstream are different
# words.
TRACKED_REMOTE="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null | cut -d/ -f1)"
if [ -n "$TRACKED_REMOTE" ] && [ "$TRACKED_REMOTE" != "origin" ]; then
  note "refused: branch tracks '$TRACKED_REMOTE', not origin"
  exit 0
fi

# Only main is pushed without being asked. A feature branch is somebody
# mid-thought, and force-publishing it is a surprise, not a service.
BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '')"
if [ "$BRANCH" != "main" ]; then
  note "skipped: on branch '$BRANCH', $AHEAD commit(s) ahead"
  exit 0
fi

# ── The gates ─────────────────────────────────────────────────────────────────
#
# Each one is a step CI already runs, chosen for being fast and for failing on
# something an auto-push would otherwise publish. Timings on this machine:
# checksums 0.09s, counts 0.15s, frontmatter 0.05s, evals 0.07s, secret-scan
# 1.65s. The whole set is under two seconds and only runs when there is
# actually something to push.
FAILED=""
gate() {
  local name="$1"; shift
  "$@" >/dev/null 2>&1 || FAILED="$FAILED $name"
}

gate checksums   python3 tools/checksums.py --check
# The one above compares disk to disk, so it passes while the commit is
# already lying. This compares what git would hand a stranger to what the
# manifest claims, which is the comparison an installer actually makes.
gate committed   python3 tools/committed_checksums.py
gate counts      python3 tools/counts.py --check
gate frontmatter python3 tools/frontmatter.py
gate evals       python3 tools/evals.py
gate secrets     python3 bin/secret-scan .

# Shell syntax, but only on the files this push would actually ship. Running
# bash -n over the whole tree on every turn is the kind of cost that gets a
# hook disabled.
while IFS= read -r f; do
  case "$f" in
    *.sh|bin/chewbacca|bin/peekaboo|bin/chrome-js|bin/mac-use)
      [ -f "$f" ] || continue
      bash -n "$f" >/dev/null 2>&1 || FAILED="$FAILED syntax:$f"
      ;;
  esac
done < <(git diff --name-only '@{u}..HEAD' 2>/dev/null)

if [ -n "$FAILED" ]; then
  note "BLOCKED $AHEAD commit(s), failed:$FAILED"
  REASONS="$FAILED" AHEAD="$AHEAD" python3 <<'PY'
import json, os
reasons = os.environ.get("REASONS", "").split()
ahead = os.environ.get("AHEAD", "?")
hint = {
    "checksums": "run: python3 tools/checksums.py",
    "committed": "the committed SHA256SUMS.txt does not describe the committed tree, so an install would refuse. Commit everything, then: python3 tools/checksums.py and amend",
    "counts": "run: python3 tools/counts.py",
    "frontmatter": "a SKILL.md yaml block does not parse, so that skill is silently unregistered",
    "evals": "a skill has malformed or missing evals",
    "secrets": "run: python3 bin/secret-scan . and remove the literal",
}
lines = [f"- {r}: {hint.get(r.split(':')[0], 'see the check output')}" for r in reasons]
print(json.dumps({"hookSpecificOutput": {"hookEventName": "Stop", "additionalContext": (
    f"Auto-push of the kit repo was BLOCKED. {ahead} commit(s) are still local "
    f"because a pre-push gate failed:\n" + "\n".join(lines) +
    "\nFix it and the next turn pushes on its own. Do not push past this by hand: "
    "the same checks run in CI on main."
)}}))
PY
  exit 0
fi

# ── Push ──────────────────────────────────────────────────────────────────────
#
# Serialized against format-and-sync's lock convention so two hooks a second
# apart do not race the remote. A push that cannot take the lock is dropped
# rather than queued: `git push origin HEAD` sends every local commit, so the
# next run carries whatever a dropped one would have.
LOCK="$REPO/.git/chewbacca-push.lock"
if [ -d "$LOCK" ]; then
  holder="$(cat "$LOCK/pid" 2>/dev/null)"
  if [ -n "$holder" ] && kill -0 "$holder" 2>/dev/null; then
    note "skipped: push already in flight (pid $holder)"
    exit 0
  fi
  rm -rf "$LOCK" 2>/dev/null   # its holder died mid-push
fi
mkdir "$LOCK" 2>/dev/null || exit 0
echo $$ > "$LOCK/pid" 2>/dev/null

PUSH_ERR="$(git push origin HEAD 2>&1)"
PUSH_RC=$?
rm -rf "$LOCK" 2>/dev/null

if [ "$PUSH_RC" -eq 0 ]; then
  note "pushed $AHEAD commit(s) from $BRANCH"
  AHEAD="$AHEAD" python3 <<'PY'
import json, os
n = os.environ.get("AHEAD", "?")
s = "" if n == "1" else "s"
print(json.dumps({"hookSpecificOutput": {"hookEventName": "Stop", "additionalContext":
    f"Kit repo: {n} commit{s} pushed to origin/main automatically. CI is running on them."
}}))
PY
  exit 0
fi

# A failed push is the whole reason this hook exists, so it is never silent.
note "PUSH FAILED, $AHEAD commit(s) still local: $(printf '%s' "$PUSH_ERR" | tr '\n' ' ' | cut -c1-300)"

# EXCEPT WHEN THE ANSWER IS "YOU DO NOT OWN THIS REPO", which is the normal
# state for anybody who cloned this kit rather than forking it. That is not a
# fault to report once a turn for the rest of their life; it is a fact about
# their remote that will not change until they do something about it. Say it
# once, clearly, then stay quiet.
case "$PUSH_ERR" in
  *"Permission"*|*"permission denied"*|*"403"*|*"Authentication failed"*|*"not have access"*|*"does not appear to be a git repo"*)
    DENIED_STAMP="$LOG_DIR/.autopush-denied"
    if [ -f "$DENIED_STAMP" ]; then
      exit 0
    fi
    : > "$DENIED_STAMP" 2>/dev/null || true
    python3 <<'PY2'
import json
print(json.dumps({"hookSpecificOutput": {"hookEventName": "Stop", "additionalContext": (
    "Kit auto-push is on by default, and this checkout has no push access to its "
    "origin, which is what happens when the kit is cloned rather than forked. "
    "Local commits will stay local. To turn auto-push into something useful here, "
    "fork the repo and point origin at the fork:\n"
    "  gh repo fork --remote=false && git remote set-url origin <your fork>\n"
    "Auto-pull is unaffected and keeps working. This message is shown once."
)}}))
PY2
    exit 0
    ;;
esac
PUSH_ERR="$PUSH_ERR" AHEAD="$AHEAD" python3 <<'PY'
import json, os
err = " ".join(os.environ.get("PUSH_ERR", "").split())[:300]
print(json.dumps({"hookSpecificOutput": {"hookEventName": "Stop", "additionalContext": (
    f"Kit repo PUSH FAILED. {os.environ.get('AHEAD','?')} commit(s) are still only on this "
    f"machine. git said: {err}"
)}}))
PY
exit 0

#!/bin/bash
# Timing, logging, a watchdog and an output cap. See lib.sh.
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" 2>/dev/null || true
type hook_init >/dev/null 2>&1 && hook_init submit-guard.sh 10
# PreToolUse: HARD BLOCK on submitting coursework to an LMS.
#
# Written 2026-09-20. Twice in one night this kit moved to submit WP1 to
# Brightspace without Caleb saying to. Once it opened the file picker on the
# final draft; once it clicked "Add a File" on the self-assessment. Both times
# he had to stop it. Nothing was actually submitted, which was luck.
#
# The rule already existed in prose ("never ask permission" has an explicit
# carve-out for decisions only he can make). Prose did not stop it. This does.
#
# Turning in graded work is irreversible, it is his name on it, and no reading
# of "act, then report" covers it. The gate opens only when he has typed the
# authorization within the last 10 minutes:
#
#   touch ~/.chewbacca/submit-authorized
#
# and the agent may only run that after he says submit in this turn.

set -uo pipefail

payload="$(cat)"
tool="$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null)"
blob="$(printf '%s' "$payload" | jq -r '.tool_input // {} | tostring' 2>/dev/null)"

[ -n "$blob" ] || exit 0

# Only care about browser drive + shell that could hit an LMS.
case "$tool" in
  mcp__chrome-devtools__*|Bash|mcp__peekaboo__*) ;;
  *) exit 0 ;;
esac

lower="$(printf '%s' "$blob" | tr '[:upper:]' '[:lower:]')"

# Bash is only a submission path if it actually makes an HTTP request. Without
# this, writing a note ABOUT this rule trips the rule, which happened the first
# time the gate ran. Prose mentioning Brightspace is not a submission.
if [ "$tool" = "Bash" ]; then
  case "$lower" in
    *curl\ *|*wget\ *|*httpie*|*"requests.post"*|*"urllib"*) ;;
    *) exit 0 ;;
  esac
fi

# Is this an LMS at all?
case "$lower" in
  *brightspace*|*d2l*|*instructure*|*canvas.usc*|*gradescope*|*blackboard*) ;;
  *) exit 0 ;;
esac

# Is it a submitting action, as opposed to reading status?
submitting=0
case "$lower" in
  *folder_submit_files*|*"add a file"*|*upload*|*'"submit"'*|*submitassignment*|*dropbox_submit*)
    submitting=1 ;;
esac
[ "$tool" = "mcp__chrome-devtools__upload_file" ] && submitting=1

# A shell HTTP call that carries a body is a submission by definition.
if [ "$tool" = "Bash" ]; then
  case "$lower" in
    *-x\ post*|*--request\ post*|*\ -f\ *|*--form*|*--data*|*-d\ @*) submitting=1 ;;
  esac
fi

[ "$submitting" = "1" ] || exit 0

# Authorized within the last 10 minutes?
token="$HOME/.chewbacca/submit-authorized"
if [ -f "$token" ]; then
  now=$(date +%s)
  then=$(stat -f %m "$token" 2>/dev/null || echo 0)
  if [ $((now - then)) -lt 600 ]; then
    exit 0
  fi
fi

cat >&2 <<'MSG'
BLOCKED: this is a coursework submission and Caleb has not authorized it.

Submitting graded work is irreversible and it is his name on the assignment.
It is a decision only he can make, not a permission gate you may skip. On
2026-09-20 this was attempted twice in one night without his word and he had
to stop it both times.

Do not retry, do not route around this, and do not read his answer to some
other question as a yes. He has to say submit about THIS assignment.

When he does, run:  touch ~/.chewbacca/submit-authorized
That opens the gate for ten minutes.

Reading submission status is fine and is not blocked. Only submitting is.
MSG
exit 2

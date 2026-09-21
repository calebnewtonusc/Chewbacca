#!/bin/bash
# PostToolUse: attribute changed files to the session that changed them.
#
# WHY NOT tool_input.file_path. The first version of this matched Write|Edit and
# read the path out of the tool input. It never fired once, because this kit
# tells agents to make file changes through Bash with sed and heredocs, so the
# dominant write path carries no file_path at all. A guard reading an empty log
# fails open forever, which is decoration.
#
# So this watches the REPOSITORY instead of the tool. After any tool call it
# diffs `git status --porcelain` against this session's last snapshot and files
# whatever newly changed under this session id. That works for a heredoc, a sed
# in place, a build step, a formatter, or the Write tool, because it never asks
# how the change was made.
#
# .githooks/pre-commit reads the result and refuses an index holding two authors.
set -uo pipefail
command -v jq >/dev/null 2>&1 || exit 0
INPUT=$(cat)
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty')
[ -n "$SID" ] || exit 0

command -v git >/dev/null 2>&1 || exit 0
REPO=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -n "$REPO" ] || exit 0

LOG="${CHEWBACCA_WRITE_LOG:-$HOME/.chewbacca/write-log.tsv}"
STATE_DIR="${CHEWBACCA_SESSION_STATE:-$HOME/.chewbacca/session-state}"
mkdir -p "$(dirname "$LOG")" "$STATE_DIR" 2>/dev/null || exit 0

KEY=$(printf '%s%s' "$SID" "$REPO" | shasum -a 256 2>/dev/null | cut -c1-16)
[ -n "$KEY" ] || exit 0
SNAP="$STATE_DIR/$KEY"

CUR=$(cd "$REPO" && git status --porcelain 2>/dev/null | sed 's/^...//' | sed 's/.* -> //' | sort -u)
[ -n "$CUR" ] || { printf '%s' "$CUR" > "$SNAP" 2>/dev/null; exit 0; }

if [ -f "$SNAP" ]; then
  NEW=$(comm -13 "$SNAP" <(printf '%s\n' "$CUR") 2>/dev/null)
else
  # First sight of this session in this repo: record the baseline and claim
  # NOTHING. Claiming everything currently dirty attributed one session's work
  # to whichever session happened to look second, which is worse than silence.
  # The next tool call diffs correctly.
  NEW=""
fi
printf '%s\n' "$CUR" > "$SNAP" 2>/dev/null || true

[ -n "${NEW//[[:space:]]/}" ] || exit 0
TS=$(date +%s)
printf '%s\n' "$NEW" | while IFS= read -r f; do
  [ -n "$f" ] || continue
  # Never log the bookkeeping itself.
  case "$f" in
    *write-log.tsv*|*session-state*|*.chewbacca/*) continue ;;
  esac
  # First claimer wins. Each session diffs against its OWN snapshot, so a file
  # another session changed looks new to everyone who looks afterwards. The
  # session that made the change sees it first, because its own tool call fires
  # this hook immediately. If somebody already claimed this path recently, leave
  # it alone rather than adding a second author and tripping the guard falsely.
  PRIOR=$(grep -F "	$REPO/$f" "$LOG" 2>/dev/null | tail -1)
  if [ -n "$PRIOR" ]; then
    PTS=$(printf '%s' "$PRIOR" | cut -f1); PSID=$(printf '%s' "$PRIOR" | cut -f2)
    if [ "$PSID" != "$SID" ] && [ $(( TS - PTS )) -lt 1800 ]; then continue; fi
  fi
  printf '%s\t%s\t%s/%s\n' "$TS" "$SID" "$REPO" "$f" >> "$LOG" 2>/dev/null || true
done

if [ "$(wc -l < "$LOG" 2>/dev/null || echo 0)" -gt 4000 ]; then
  tail -2000 "$LOG" > "$LOG.tmp" 2>/dev/null && mv "$LOG.tmp" "$LOG" 2>/dev/null || true
fi
exit 0

#!/bin/bash
# PostToolUse on Write|Edit: record WHICH SESSION wrote each file.
#
# WHY. .githooks/pre-commit refuses staged files whose mtime is far OLDER than
# the newest staged file, which catches a tab that closed hours ago. It does not
# catch a session running RIGHT NOW, because that session's files are fresh. On
# 2026-09-20 commit 4a0b1df absorbed Gavin's bin/evolve and tests/evolve.sh,
# written minutes earlier, and the hook printed them and let them through.
#
# Time cannot tell two live sessions apart. Authorship can. This writes the
# session id beside every path a tool touches, so pre-commit can refuse an index
# that mixes two authors instead of guessing from timestamps.
set -uo pipefail
command -v jq >/dev/null 2>&1 || exit 0
INPUT=$(cat)
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty')
FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')
[ -n "$SID" ] && [ -n "$FILE" ] || exit 0

LOG="${CHEWBACCA_WRITE_LOG:-$HOME/.chewbacca/write-log.tsv}"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || exit 0
printf '%s\t%s\t%s\n' "$(date +%s)" "$SID" "$FILE" >> "$LOG" 2>/dev/null || true

# Keep it small; only recent history can possibly matter to a pre-commit check.
if [ "$(wc -l < "$LOG" 2>/dev/null || echo 0)" -gt 4000 ]; then
  tail -2000 "$LOG" > "$LOG.tmp" 2>/dev/null && mv "$LOG.tmp" "$LOG" 2>/dev/null || true
fi
exit 0

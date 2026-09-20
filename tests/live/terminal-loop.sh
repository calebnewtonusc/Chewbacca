#!/usr/bin/env bash
# Live: the hook sees a permission prompt in a tab this check opened, holds
# it, and an answer file grants it. Opens a Terminal window with --fresh and
# takes focus for about thirty seconds, so this is never run by
# tests/run.sh. Run it when the person says go. Needs the hook registered
# (setup.sh). Works in the real memory dir on purpose: the hook Claude Code
# runs reads ~/.bob/memory/project.json, not a temp copy.
source "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
need claude "npm i -g @anthropic-ai/claude-code"
need peekaboo "run install.sh"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CH="$REPO/mac/bin/chewie"
MEM="${BOB_MEMORY_DIR:-$HOME/.bob/memory}"
DIR="$(mktemp -d)"
TTY="$(bash "$CH" terminal ensure --cwd "$DIR" --fresh --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["tty"])')"
ok "ensure opened a claude tab and remembered it" test -n "$TTY"
rm -f "$MEM"/asks/*.json "$MEM"/asks/*.answer 2>/dev/null
sleep 2
ok "draft a prompt that needs a permission" bash "$CH" terminal draft "run this shell command: touch loop-proof.txt" --tty "$TTY"
sleep 1
ok "submit it" env CHEWIE_TERMINAL_SUBMIT=1 bash "$CH" terminal submit --tty "$TTY"
# The hook holds only when Terminal is not in front; put the Finder there.
osascript -e 'tell application "Finder" to activate' >/dev/null 2>&1 || true
echo "  LOOK: within ~20 s the pill should say the terminal is waiting. 20 s."
ASK=""
for _ in $(seq 1 40); do
  ASK="$(ls "$MEM"/asks/*.json 2>/dev/null | head -1)"
  [ -n "$ASK" ] && break
  sleep 0.5
done
ok "the hook wrote an ask for this tab" test -n "$ASK"
[ -n "$ASK" ] && echo allow > "${ASK%.json}.answer"
sleep 3
ok "the answer was consumed" test ! -e "${ASK:-/nonexistent}"
ok "the event log records the allow" grep -q ask_answered "$MEM/terminal-events.jsonl"
echo "  LOOK: claude should have created loop-proof.txt in $DIR. Close that window when done."
mutant "an unknown terminal verb is rejected" bash "$CH" terminal nonsense
finish

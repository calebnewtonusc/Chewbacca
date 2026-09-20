#!/usr/bin/env bash
# Live: a draft lands in Claude Code's input and does not submit; Return
# submits it; Control-U clears it. Opens a Terminal window and takes focus for
# about twenty seconds, so this is never run by tests/run.sh. Run it when the
# person says go, never on a live claude session: it opens its own in a temp
# folder.
source "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
need claude "npm i -g @anthropic-ai/claude-code"
need peekaboo "run install.sh"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CH="$REPO/mac/bin/chewie"
export BOB_MEMORY_DIR="$(mktemp -d)"
DIR="$(mktemp -d)"

TTY="$(bash "$CH" terminal ensure --cwd "$DIR" --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["tty"])')"
ok "ensure opened a claude tab" test -n "$TTY"
sleep 2
ok "draft pastes without submitting" bash "$CH" terminal draft "reply with exactly one word: chewbacca" --tty "$TTY"
echo "  LOOK: the text should sit in the input, unsent. 5 s."
sleep 5
ok "clear empties the input" bash "$CH" terminal clear --tty "$TTY"
sleep 1
ok "draft again" bash "$CH" terminal draft "reply with exactly one word: chewbacca" --tty "$TTY"
sleep 1
ok "submit presses Return" bash "$CH" terminal submit --tty "$TTY"
echo "  LOOK: claude should now answer 'chewbacca'. Close that window when done."

# The mutant: an unknown verb must be rejected, or the dispatch is not
# actually checking anything. Deliberately touches no real tab.
mutant "an unknown terminal verb is rejected" bash "$CH" terminal nonsense

finish

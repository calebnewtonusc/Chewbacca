#!/bin/bash
# UserPromptSubmit: name the process and the falsifier BEFORE the work starts.
#
# THE FAILURE THIS EXISTS FOR. Caleb, 2026-09-20: "Make chewbacca always ask
# creative high leverage outside of the box questions to itself before it
# builds anything... I should never have to prompt engineer ever again."
#
# The obvious build is a skill file full of good questions. That fails, and
# this repo has proven it repeatedly: voice.md loaded into every session and
# was obeyed by nothing until a hook started refusing replies;
# research-the-craft was a rule that did nothing until craft-gate could exit 1.
# Text that is retrieved does not fire. Text that is INJECTED does.
#
# WHY IT ASKS FOR ONE THING. A checklist makes the performance of thinking
# cheaper, not rarer. So this demands the single answer that cannot be faked
# by answering in a friendly tone: what result would show this was wrong.
# A falsifier is a prediction, so it is either stated and tested or it is not.
#
# WHAT IT CANNOT DO, stated because the limit is real: a hook can verify a
# falsifier was WRITTEN, never that it was believed or that the work tested
# it. This raises the cost of skipping the step. It does not do the thinking.
#
# Deliberately silent on short prompts and on anything with no build intent,
# because an injection that fires every turn is an injection that gets skipped.
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" 2>/dev/null || true
type hook_init >/dev/null 2>&1 && hook_init method-guard.sh 5
set -uo pipefail

INPUT=$(cat)
command -v jq >/dev/null 2>&1 || exit 0
PROMPT=$(printf '%s' "$INPUT" | jq -r '.prompt // empty')
[ -n "$PROMPT" ] || exit 0

# Under ~6 words is a reply, an ack or a redirect, not a brief.
WORDS=$(printf '%s' "$PROMPT" | wc -w | tr -d ' ')
[ "$WORDS" -ge 6 ] || exit 0

METHOD=$(command -v method || echo "$HOME/.local/bin/method")
[ -x "$METHOD" ] || exit 0

TERSE=$("$METHOD" pick "$PROMPT" --terse 2>/dev/null) || exit 0
[ -n "$TERSE" ] || exit 0

# Once per process per session. The same six lines on every turn is noise,
# and noise is how an injection gets tuned out.
SESSION=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"')
KIND=$(printf '%s' "$TERSE" | head -1 | cut -d' ' -f2)
SEEN="${TMPDIR:-/tmp}/method-guard-$SESSION-$KIND"
[ -f "$SEEN" ] && exit 0
: > "$SEEN"

# The sharpest question bank this kit has is its own history. 53 commits
# describe a failure somebody actually made here, and nothing ever read them.
# The silent-except bug that ate every focus state tonight was already
# written down months ago: "Every bug this kit shipped failed silently."
SCARS_BIN=$(command -v scars || echo "$HOME/.local/bin/scars")
SCARS=""
if [ -x "$SCARS_BIN" ]; then
  SCARS=$("$SCARS_BIN" find "$PROMPT" --terse -n 2 2>/dev/null) || SCARS=""
fi
[ -n "$SCARS" ] && TERSE="$TERSE"$'\n\n'"$SCARS"

jq -n --arg t "$TERSE" '{
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: ("Before building, answer these to yourself and put the "
      + "FALSIFIER in your reply as one plain sentence. If nothing could show "
      + "this is wrong, say so: that is the finding.\n\n" + $t
      + "\n\nFull set: `method " + (($t | split("\n") | .[0] | split(" ") | .[1])) + "`")
  }
}' 2>/dev/null
exit 0

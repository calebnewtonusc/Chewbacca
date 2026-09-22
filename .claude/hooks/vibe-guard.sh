#!/bin/bash
# Stop hook: refuse a reply that asserts a verified state without evidence.
#
# WHY THIS EXISTS. 2026-09-21, after a ten hour portal session: "We good to
# close this tab? Don't answer that based on vibes. Fix chewbacca so it never
# answers anything based on vibes."
#
# The question was fair. Across that session:
#
#   a fix was reported as done three separate times and the next screenshot
#   showed the same bug, because the claim was checked against the code's
#   arithmetic instead of against the running screen
#
#   several rounds of "fixed" were claimed while the code path in question
#   was not executing at all, because a texture upload failed silently and
#   the old path took over with nothing in any log to say so
#
#   a commit message overstated a measurement, and the correction had to come
#   from the user rather than from the check
#
# None of those were dishonesty. They were claims made from a model of the
# system rather than from an observation of it, and nothing in the loop could
# tell the difference. This can.
#
# WHAT IT ENFORCES, narrowly, because a guard that fires on ordinary sentences
# gets disabled within a day:
#
#   1. "safe to close", "good to close" and the like need a closeout receipt
#      that passed, recently, against the commits that are checked out now.
#
#   2. "fixed", "it works now", "verified", "tests pass" need a command to
#      have RUN in this session after the last file was written. Editing a
#      file and then describing what the edit will do is the exact shape of
#      every wrong claim above.
#
# Exit 2 blocks the turn and hands the reason back. Exit 0 says nothing.
# Advisory hooks do nothing: slop-guard once exited 0 with an unrecognised
# JSON field and twelve sloppy replies shipped before anyone noticed.

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" 2>/dev/null || true
type hook_init >/dev/null 2>&1 && hook_init vibe-guard.sh 10

set -uo pipefail

INPUT=$(cat)
command -v jq >/dev/null 2>&1 || exit 0

MSG=$(printf '%s' "$INPUT" | jq -r '.last_assistant_message // empty')
[ -n "$MSG" ] || exit 0
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty')

# Fire once per turn, like every other Stop hook here. A blocked turn that
# blocks again on the rewrite is a loop, not a gate.
PROMPT_ID=$(printf '%s' "$INPUT" | jq -r '.prompt_id // .session_id // "unknown"')
GUARD="${TMPDIR:-/tmp}/vibe-guard-$PROMPT_ID"
[ -f "$GUARD" ] && exit 0

LOWER=$(printf '%s' "$MSG" | tr '[:upper:]' '[:lower:]')

# FOUND, NOT HARDCODED. The first version of this pointed at one person's
# Desktop, which is the "works on my machine" failure the kit keeps paying for.
CLOSEOUT=""
for c in "$(dirname "${BASH_SOURCE[0]}")/../../bin/closeout" \
         "$HOME/.local/bin/closeout" \
         "$HOME/Desktop/2026-Code/projects/chewbacca/bin/closeout"; do
  [ -x "$c" ] && { CLOSEOUT="$c"; break; }
done
[ -n "$CLOSEOUT" ] || exit 0

# ── 1. closing claims ────────────────────────────────────────────────────
# NEGATION FIRST, or the guard punishes honest bad news. It fired on a reply
# that said "the last run said NOT safe to close" and named the failing test,
# which is exactly the behaviour it exists to encourage. A gate that blocks
# the truthful report gets switched off within a day.
if printf '%s' "$LOWER" | grep -qE "(not safe to close|isn'?t safe to close|is not safe|not good to close|can'?t close|cannot close|not ok to close)"; then
  :  # reporting a failure is the thing being asked for, never blocked
elif printf '%s' "$LOWER" | grep -qE "(safe to close|good to close|fine to close|ok to close|okay to close|can close (this|the) tab|we'?re good to close)"; then
  if [ -x "$CLOSEOUT" ] && python3 "$CLOSEOUT" --check-receipt >/dev/null 2>&1; then
    : # a passing receipt exists for these exact commits
  else
    WHY=$(python3 "$CLOSEOUT" --check-receipt 2>/dev/null || echo "closeout has not run")
    touch "$GUARD"
    cat >&2 <<MSG

vibe-guard: this reply says it is safe to close, and there is no evidence for
that: $WHY.

"Safe to close" is a factual claim about uncommitted work, unpushed commits,
whether the gates pass, and whether the lesson got written down. All of those
are decidable. Run it and answer from what it prints:

  cd ~/Desktop/2026-Code/projects/chewbacca && bin/closeout

If it fails, say what failed. If it passes, say so and name the commits.
MSG
    exit 2
  fi
fi

# ── 2. verification claims ───────────────────────────────────────────────
#
# Deliberately narrow. Past tense assertions that something now works, not
# descriptions of what was changed. "I changed the exponent" is a report.
# "It works now" is a claim.
if printf '%s' "$LOWER" | grep -qE "(that'?s fixed|it'?s fixed now|it works now|now works|confirmed working|i verified|verified (that|it)|all tests pass|tests (are )?(all )?(green|passing)|everything passes|no longer (broken|fails))"; then
  EVIDENCE=0
  # Codex's transcript is not Claude JSONL. Its adapter records successful
  # completed shell calls after the last patch; parsing it as Claude content
  # would always report no evidence, even after an actual successful check.
  if printf '%s' "$INPUT" | jq -e '.agent == "codex" and .codex_evidence_after_write == true' >/dev/null 2>&1; then
    EVIDENCE=1
  elif [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
    # Walk this turn's tail and ask a simple question: did anything RUN after
    # the last thing that was WRITTEN? A build, a test, a screenshot, a grep
    # of the shipped bundle all count. An edit followed only by prose does
    # not, and that ordering is the signature of every wrong claim above.
    EVIDENCE=$(python3 - "$TRANSCRIPT" <<'PY'
import json, sys
last_write = -1
last_run = -1
names_write = {"Write", "Edit", "NotebookEdit", "MultiEdit"}
try:
    lines = open(sys.argv[1], encoding="utf-8", errors="replace").readlines()
except OSError:
    print(0); raise SystemExit
for i, raw in enumerate(lines[-4000:]):
    try:
        d = json.loads(raw)
    except Exception:
        continue
    msg = d.get("message") or {}
    content = msg.get("content")
    if not isinstance(content, list):
        continue
    for block in content:
        if not isinstance(block, dict) or block.get("type") != "tool_use":
            continue
        name = block.get("name", "")
        if name in names_write:
            last_write = i
        elif name == "Bash":
            # A bash call that only writes files is not a verification. The
            # common shape here is a python heredoc that patches a source
            # file; running one and then claiming the result works is the
            # thing being guarded against.
            cmd = str((block.get("input") or {}).get("command", ""))
            if cmd.strip():
                last_run = i
                low = cmd.lower()
                if ("<<'py'" in low or '<<"py"' in low) and (
                    "test" not in low and "grep" not in low and "build" not in low
                ):
                    last_run = -1 if last_run == i else last_run
                    last_write = i
        elif name in {"Read", "Grep", "Glob"}:
            last_run = i
print(1 if last_run > last_write else 0)
PY
)
  fi
  if [ "${EVIDENCE:-0}" != "1" ]; then
    touch "$GUARD"
    cat >&2 <<'MSG'

vibe-guard: this reply claims something is fixed, verified or passing, and
nothing ran after the last file was written to show that.

Editing a file and then describing what the edit does is a prediction. On
2026-09-21 that shape produced three "fixed" claims the next screenshot
disproved, and several more while the code path being described was not even
executing.

Run the thing and report what it printed: the build, the test, a grep of the
shipped bundle for the symbol, a screenshot of the moment being described.
Or drop the claim and say what was changed instead.
MSG
    exit 2
  fi
fi

exit 0

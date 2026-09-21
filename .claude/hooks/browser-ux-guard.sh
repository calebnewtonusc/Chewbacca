#!/bin/bash
# PreToolUse on Bash and the peekaboo MCP tools: refuse to read or drive a
# BROWSER through pixels before the DOM route has been tried in this session.
#
# 2026-09-21. Asked to fill a form the user had open in Chrome, this kit
# screenshotted the window, read the PNG, and clicked at pixel coordinates, one
# field per round trip. `chewie web` already existed and drives the same form
# through CDP in a single call. The user, twice: "Bro can't you navigate ux? Why
# are you having to visually do it... Be smarter and fix chewbacca" and "You were
# able to fill out a google form in 1s before be smarter".
#
# The routing table in skills/mac-control listed layer 6 as "Playwright over
# CDP", which names no runnable command, so the agent fell back to the layer it
# did have a command for. That was fixed in prose the same day. This exists
# because prose already failed once: see feedback_enforce_dont_document, and
# feedback_advisory_hooks_do_nothing, where a guard exited 0 with an
# unrecognized JSON field and twelve bad replies shipped anyway.
#
# So: exit 2, which PreToolUse honors and which blocks the call before it runs.
#
# This is NOT a ban on ever screenshotting a browser. A canvas app (FigJam,
# Figma, a WebGL scene) and a genuinely visual question ("does this look right")
# are real layer-5 work. Both are one word away: put `visual:` in the command.
# An escape hatch that costs one retry is what keeps a gate switched on, per the
# suppression evidence cited in ux-guard.sh.
set -uo pipefail

INPUT="$(cat 2>/dev/null || true)"
[ -n "$INPUT" ] || exit 0

STATE_DIR="${CHEWIE_STATE_DIR:-$HOME/.chewbacca}"

# tool_name, session id, and the strings worth inspecting, in one parse.
# A hook that dies on an unexpected field is a hook that silently allows
# everything, which is the exact failure feedback_advisory_hooks_do_nothing
# records. Every read below is defensive and the fallback is "no opinion".
PARSED="$(printf '%s' "$INPUT" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    raise SystemExit
ti = d.get("tool_input") or {}
if not isinstance(ti, dict):
    ti = {}
name = str(d.get("tool_name") or "")
sid  = str(d.get("session_id") or "nosession")
# Bash carries the whole command. The peekaboo MCP tools carry app/coords as
# their own fields, so flatten both into one haystack.
parts = [str(ti.get("command") or "")]
for k in ("app", "app_target", "window_title", "path", "mode", "coords", "x", "y"):
    v = ti.get(k)
    if v not in (None, ""):
        parts.append("%s=%s" % (k, v))
print(sid)
print(name)
print(" ".join(parts).replace("\n", " "))
' 2>/dev/null)"

SESSION="$(printf '%s' "$PARSED" | sed -n 1p)"
TOOL="$(printf '%s' "$PARSED" | sed -n 2p)"
HAY="$(printf '%s' "$PARSED" | sed -n 3p)"
[ -n "${SESSION:-}" ] || exit 0
[ -n "${HAY:-}" ] || exit 0

LOWER="$(printf '%s' "$HAY" | tr '[:upper:]' '[:lower:]')"
MARKER="$STATE_DIR/web-bridge-used.$SESSION"

# Job one: remember that the DOM route was taken. Any real use of the bridge
# clears the gate for the rest of the session, because after that a screenshot
# is a deliberate second step rather than a substitute for the first.
case "$LOWER" in
  *"chewie web "*|*"bridge/web.js"*)
    mkdir -p "$STATE_DIR" 2>/dev/null
    : > "$MARKER" 2>/dev/null
    exit 0
    ;;
esac

# Already cleared in this session.
[ -f "$MARKER" ] && exit 0

# The declared override.
case "$LOWER" in
  *visual:*) exit 0 ;;
esac

# Job two: is this a pixel action?
IS_PIXEL=0
case "$LOWER" in
  *"peekaboo image"*|*"chewie shot"*|*"screencapture"*) IS_PIXEL=1 ;;
  *"--coords"*)                                        IS_PIXEL=1 ;;
esac
case "$TOOL" in
  mcp__peekaboo__image|mcp__peekaboo__see) IS_PIXEL=1 ;;
  mcp__peekaboo__click)
    case "$LOWER" in *x=*|*y=*|*coords*) IS_PIXEL=1 ;; esac
    ;;
esac
[ "$IS_PIXEL" -eq 1 ] || exit 0

# ...aimed at a browser? An unnamed target is left alone: a whole-screen grab
# is usually not browser work, and guessing would put this over the false
# positive line where people switch gates off.
case "$LOWER" in
  *"google chrome"*|*chromium*|*safari*|*firefox*|*"microsoft edge"*|*brave*|*comet*|*arc*|*opera*|*vivaldi*) ;;
  *) exit 0 ;;
esac

{
  echo "browser-ux-guard: refusing to drive a browser through pixels."
  echo
  echo "A browser hands you an addressable model of its own contents. Reading it"
  echo "as an image throws that away: a form that takes one call took thirty on"
  echo "2026-09-21, and the user watched it happen."
  echo
  echo "Use layer 6 instead:"
  echo
  echo "  chewie web profiles                       # which account each Chrome profile holds"
  echo "  CHEWIE_CHROME_PROFILE=<email> chewie web goto \"<url>\""
  echo "  CHEWIE_CHROME_PROFILE=<email> chewie web eval \"<js>\""
  echo "  chewie web frames                         # every page AND iframe target"
  echo
  echo "Fill a whole multi-step form in ONE eval, with an async IIFE that clicks,"
  echo "waits, and returns the final field values. One call per field spawns a"
  echo "node process and a CDP connection each time."
  echo
  echo "Three traps, each of which has already cost a session:"
  echo "  - the profile: the bridge defaults to Default, often the wrong account."
  echo "  - the iframe: a cross-origin frame is its own CDP target and its text is"
  echo "    absent from the parent's innerText, so a step in one looks blank."
  echo "  - React inputs: el.value = x does not register. Use the native value"
  echo "    setter plus an input event, and dispatch the full pointer sequence."
  echo
  echo "If this genuinely is visual work, a canvas app or a 'does this look right'"
  echo "question, say so in the command and it goes through:"
  echo
  echo "  # visual: checking the FigJam canvas renders"
  echo
  echo "Any use of chewie web in this session clears this gate."
} >&2
exit 2

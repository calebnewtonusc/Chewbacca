#!/usr/bin/env bash
# The browser pixel gate, on every case it has to get right.
#
# feedback_a_silent_guard_proves_nothing: two authorship guards shipped having
# never refused anything, because their tests asserted the exit code of a path
# that returned early. So the first assertion here is that the gate REFUSES a
# real command, and the allow cases each state why they are allowed.
set -uo pipefail
ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
GUARD="$ROOT/.claude/hooks/browser-ux-guard.sh"
FAILED=0
note() { echo "    $1"; }
fail() { echo "    FAIL: $1"; FAILED=1; }

STATE="$(mktemp -d)"
trap 'rm -rf "$STATE"' EXIT

# Runs the guard with an isolated state dir. $1 session, $2 tool, $3 json for
# tool_input. Prints the exit code.
run() {
  local sid="$1" tool="$2" ti="$3"
  printf '{"session_id":"%s","tool_name":"%s","tool_input":%s}' "$sid" "$tool" "$ti" \
    | CHEWIE_STATE_DIR="$STATE" bash "$GUARD" >/dev/null 2>&1
  echo $?
}
bash_in() { printf '{"command":%s}' "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$1")"; }

blocks() {
  local want=2 got; got="$(run "$2" "${4:-Bash}" "$3")"
  if [ "$got" = "2" ]; then note "blocks: $1"; else fail "$1 exited $got, expected 2"; fi
}
allows() {
  local got; got="$(run "$2" "${4:-Bash}" "$3")"
  if [ "$got" = "0" ]; then note "allows: $1"; else fail "$1 exited $got, expected 0"; fi
}

[ -x "$GUARD" ] || { echo "    FAIL: $GUARD is not executable"; exit 1; }

# The exact command that started this. If this ever stops blocking, the gate is
# decorative again.
blocks "the screenshot that caused this, peekaboo image on Chrome" s1 \
  "$(bash_in 'peekaboo image --app "Google Chrome" --path ./tab.png')"

blocks "coordinate click at a browser" s1 \
  "$(bash_in 'peekaboo click --coords 519,394 --app "Google Chrome"')"

blocks "chewie shot at Safari" s1 "$(bash_in 'chewie shot --app Safari')"
blocks "screencapture aimed at Arc" s1 "$(bash_in 'screencapture -l 12 arc.png')"
blocks "the peekaboo MCP image tool on Chrome" s1 '{"app":"Google Chrome"}' mcp__peekaboo__image

# Allowed, each for a stated reason.
allows "a non-browser app, the gate has no opinion" s1 \
  "$(bash_in 'peekaboo image --app Xcode --path x.png')"
allows "a whole-screen grab with no named target" s1 \
  "$(bash_in 'peekaboo image --mode screen --path s.png')"
allows "an ordinary command that is not a pixel action" s1 \
  "$(bash_in 'grep -rn foo ~/Desktop')"
allows "the declared visual override" s1 \
  "$(bash_in '# visual: checking the FigJam canvas renders
peekaboo image --app "Google Chrome" --path c.png')"

# The session latch: using the bridge clears the gate, because a screenshot
# after the DOM route is a second step rather than a substitute for the first.
blocks "before the bridge is used in this session" s2 \
  "$(bash_in 'peekaboo image --app "Google Chrome" --path a.png')"
allows "the bridge call itself" s2 "$(bash_in 'chewie web tabs')"
allows "the same screenshot once the bridge has been used" s2 \
  "$(bash_in 'peekaboo image --app "Google Chrome" --path a.png')"
blocks "a DIFFERENT session is still gated" s3 \
  "$(bash_in 'peekaboo image --app "Google Chrome" --path a.png')"

# Malformed input must not silently allow everything, which is the failure
# feedback_advisory_hooks_do_nothing records.
got="$(printf 'not json at all' | CHEWIE_STATE_DIR="$STATE" bash "$GUARD" >/dev/null 2>&1; echo $?)"
[ "$got" = "0" ] && note "survives malformed input without erroring" || fail "malformed input exited $got"
got="$(printf '{"session_id":"s9","tool_name":"Bash","tool_input":{"unexpected":1}}' \
  | CHEWIE_STATE_DIR="$STATE" bash "$GUARD" >/dev/null 2>&1; echo $?)"
[ "$got" = "0" ] && note "an unrecognized field does not crash the gate" || fail "unknown field exited $got"

# The refusal has to name the command that replaces it, or it is a wall.
#
# Build this with the same helper as every other case. Putting the JSON in a
# printf FORMAT string instead of an argument let printf eat the \" escapes,
# which fed the guard invalid JSON, which made it exit 0 and print nothing, and
# the three assertions below then failed for a reason that had nothing to do
# with the guard.
OUT="$(printf '{"session_id":"s4","tool_name":"Bash","tool_input":%s}' \
  "$(bash_in 'peekaboo image --app "Google Chrome" --path a.png')" \
  | CHEWIE_STATE_DIR="$STATE" bash "$GUARD" 2>&1 >/dev/null)"
printf '%s' "$OUT" | grep -q 'chewie web goto'   && note "refusal names the replacement command" || fail "refusal does not name chewie web goto"
printf '%s' "$OUT" | grep -q 'chewie web frames' && note "refusal names the iframe trap"         || fail "refusal does not mention frames"
printf '%s' "$OUT" | grep -q 'visual:'           && note "refusal names the override"            || fail "refusal does not name the override"

exit $FAILED

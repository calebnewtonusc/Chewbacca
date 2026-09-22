#!/usr/bin/env bash
# The fusion guard must refuse a first-name collision and stay silent otherwise.
# Stage 8 of graph-engineering, enforced. It exists because "Jonah Black" was
# written into second-brain as a client's name on a first-name match, and the
# right person was Jonah Graham.
set -uo pipefail
HOOK="$HOME/.claude/hooks/fusion-guard.sh"
[ -x "$HOOK" ] || { echo "fusion-guard not installed"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq absent, skipping"; exit 0; }

BRAIN="$HOME/second-brain"
fail=0
probe() {                       # name, file, content, expected exit
  local code
  printf '{"tool_name":"Write","tool_input":{"file_path":%s,"content":%s}}' \
    "$(jq -Rn --arg v "$2" '$v')" "$(jq -Rn --arg v "$3" '$v')" \
    | "$HOOK" >/dev/null 2>&1
  code=$?
  if [ "$code" = "$4" ]; then printf '  ok    %s (exit %s)\n' "$1" "$code"
  else printf '  FAIL  %s: wanted %s got %s\n' "$1" "$4" "$code"; fail=$((fail+1)); fi
}

echo "refuses a first-name collision in the notes:"
# Joel Newton is on the roster; Joel Bannister is not.
probe "new surname, known first name" \
  "$BRAIN/memory/probe_fusion.md" "Met with Joel Bannister about the deal." 2

echo "stays out of the way:"
probe "a person already on the roster" \
  "$BRAIN/memory/probe_fusion.md" "Met with Joel Newton about the deal." 0
probe "a first name nobody shares" \
  "$BRAIN/memory/probe_fusion.md" "Met with Quentin Farraday about the deal." 0
probe "outside the notes store" \
  "/tmp/probe_fusion.md" "Met with Joel Bannister about the deal." 0
probe "no names at all" \
  "$BRAIN/memory/probe_fusion.md" "The build passes and the gates are green." 0

echo
[ "$fail" = 0 ] && echo "stage 8 is enforced, and only where it should be   ok" || echo "$fail failed"
exit "$fail"

#!/bin/bash
# design-context must fire on work that renders something and stay silent on
# work that does not. A shell-script session must not carry the animation rules.
set -uo pipefail
HOOK="$(cd "$(dirname "$0")/.." && pwd)/.claude/hooks/design-context.sh"
pass=0; fail=0
ok(){ printf '  \033[0;32mpass\033[0m  %s\n' "$1"; pass=$((pass+1)); }
no(){ printf '  \033[0;31mfail\033[0m  %s\n' "$1"; fail=$((fail+1)); }
command -v jq >/dev/null 2>&1 || { echo "  skip: jq not installed"; exit 0; }

run(){ printf '{"prompt":"%s"}' "$1" | bash "$HOOK" 2>/dev/null; }

out=$(run "make the hero scroll animation smoother")
printf '%s' "$out" | grep -q "400ms TOTAL" \
  && ok "fires on design work and carries the stagger ceiling" \
  || no "did not fire on obvious design work"

printf '%s' "$out" | grep -q "Removal is free" \
  && ok "carries the subtraction cue, which moved 41% to 61% on eight words" \
  || no "missing the subtraction cue"

out=$(run "fix the failing test in the argument parser")
[ -z "$out" ] && ok "silent on non-design work" \
  || no "fired on a parser bug"

out=$(run "why is the deploy failing on railway")
[ -z "$out" ] && ok "silent on a deploy question" \
  || no "fired on a deploy question"

printf '\n  %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]

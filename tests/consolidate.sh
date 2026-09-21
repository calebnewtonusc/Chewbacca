#!/bin/bash
# consolidate must promote only what recurred, refuse what methods/ already
# says, and hold back a coincidence. A loop that promotes everything is worse
# than none: a rule nobody believes teaches people to skip rules.
set -uo pipefail
ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
C="$ROOT/bin/consolidate"
fail() { echo "  FAIL $1"; exit 1; }

OUT="$("$C" 2>/dev/null)" || fail "consolidate exited non-zero"

# A mechanism already covered by methods/ must be named as covered, not
# proposed again. silent-failure is in debug.md.
printf '%s' "$OUT" | grep -q "ALREADY IN" || fail "never detects existing coverage"

# The bar must actually hold something back, or it is not a bar.
printf '%s' "$OUT" | grep -q "below the bar" || fail "nothing held below the bar"

# Promotion must name its episodes. A rule with no commits behind it cannot
# be checked and should not be believed.
"$C" --promote >/dev/null 2>&1 || fail "--promote failed"
M="$ROOT/methods/consolidated.md"
[ -f "$M" ] || fail "--promote wrote nothing"
grep -q "Earned by" "$M" || fail "promoted a rule without citing episodes"
grep -qE '^- `[0-9a-f]{6,}`' "$M" || fail "episodes are not real commit shas"
grep -q "PROPOSALS" "$M" || fail "promoted rules do not say they are proposals"

# Decay must refuse to retire on age alone.
"$C" --decay --days 3650 2>/dev/null | grep -q "Nothing to retire" \
  || fail "decay retired something at a 10-year threshold"

echo "  ok   consolidate promotes what recurred and holds back what did not"

#!/bin/bash
# scars must retrieve on meaning and refuse on coincidence. A bank that
# always returns something trains people to skip it.
set -uo pipefail
ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
S="$ROOT/bin/scars"
fail() { echo "  FAIL $1"; exit 1; }

"$S" reindex >/dev/null 2>&1 || fail "reindex"

# A query that matches a real recorded failure must return one.
"$S" find "a tool that swallows errors silently" 2>/dev/null \
  | grep -qi "silent\|swallow" || fail "missed a real silent-failure scar"

# A query with nothing to do with this kit must return nothing.
if "$S" find "book a flight to tokyo" 2>/dev/null | grep -q "PAST FAILURE"; then
  fail "padded an irrelevant query"
fi

# Terse mode is what the hook injects; it must stay short.
LINES=$("$S" find "a tool that swallows errors silently" --terse -n 2 2>/dev/null | wc -l)
[ "$LINES" -le 4 ] || fail "terse output is $LINES lines, too long to inject"
echo "  ok   scars retrieves on meaning and refuses on coincidence"

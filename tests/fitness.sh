#!/bin/bash
# A fitness function that does not persist is not a fitness function. The kit
# ran 164 eval cases and printed the result to stdout, where it died, so no
# change could ever be shown to help.
set -uo pipefail
ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
F="$ROOT/bin/fitness"
LEDGER="$HOME/.chewbacca/fitness.jsonl"
fail() { echo "  FAIL $1"; exit 1; }

BEFORE=$(wc -l < "$LEDGER" 2>/dev/null || echo 0)
"$F" --no-tests >/dev/null 2>&1 || fail "fitness exited non-zero"
AFTER=$(wc -l < "$LEDGER" 2>/dev/null || echo 0)
[ "$AFTER" -gt "$BEFORE" ] || fail "score was not appended to the ledger"

# Every entry must be stamped with a commit, or it cannot be compared.
tail -1 "$LEDGER" | python3 -c "
import json,sys
e=json.load(sys.stdin)
assert e.get('sha'), 'no sha on the entry'
assert 'structural_score' in e, 'no score on the entry'
assert 'dirty' in e, 'does not record whether the tree was dirty'
" || fail "ledger entry is missing sha, score or dirty flag"

# A sampled score must never be compared against a full one.
grep -q "sampled" "$F" || fail "no sampling honesty in the code"
grep -q "e.get(\"sampled\") == entry.get(\"sampled\")" "$F" \
  || fail "compare does not segregate sampled from full runs"

# It must not overclaim.
"$F" --no-tests 2>&1 | grep -q "not quality" \
  || fail "does not state that the score is coverage, not quality"

echo "  ok   fitness persists a comparable score stamped with its commit"

#!/bin/bash
# evolve must measure in isolation, keep failures, and never merge.
set -uo pipefail
ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
E="$ROOT/bin/evolve"
fail() { echo "  FAIL $1"; exit 1; }

# The archive has to survive a failed attempt. after=None and delta=None
# crashed --archive the first time a patch did not apply, and a failure is
# exactly the row the archive exists to hold.
"$E" --archive >/dev/null 2>&1 || fail "--archive crashed"

# It must never merge. If these strings go, so does the safety property.
grep -q "NOT MERGED" "$E" || fail "no longer states that it does not merge"
grep -q "not quality" "$E" || fail "no longer warns the score is a proxy"

# Isolation must be a worktree removed by exact path, per the repo's own rule
# about shared .worktrees/.
grep -q "worktree.*add.*--detach" "$E" || fail "does not isolate in a worktree"
grep -q 'worktree",\s*"remove"' "$E" || grep -q '"worktree", "remove"' "$E" \
  || fail "does not remove its worktree"

# No stray worktrees from earlier runs.
if git -C "$ROOT" worktree list | grep -q "evolve-"; then
  fail "left an evolve worktree behind"
fi

# It must refuse to run with nothing to try.
"$E" >/dev/null 2>&1 && fail "ran with no --patch and no --cmd"

echo "  ok   evolve measures in isolation, keeps failures, merges nothing"

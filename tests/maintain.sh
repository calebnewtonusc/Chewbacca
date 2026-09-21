#!/bin/bash
# maintain runs unattended, so the two things that matter are that it cannot
# change history and that its digest stays readable.
set -uo pipefail
ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
M="$ROOT/bin/maintain"
fail() { echo "  FAIL $1"; exit 1; }

# It must never commit, push, promote or merge. An unattended committer in a
# repo with concurrent sessions is a data-loss machine, and three commits
# swallowed another session's files on 2026-09-20.
grep -qE '"(commit|push)"' "$M" && fail "maintain references git commit/push"
grep -q -- "--promote" "$M" && fail "maintain can auto-promote a rule"
grep -q "Nothing was committed, pushed, promoted or merged" "$M" \
  || fail "no longer states its own limits"

# The digest must filter. Pasting raw check output trains people to stop
# reading it, which is how the real finding goes invisible.
grep -q "def distil" "$M" || fail "digest no longer filters output"
grep -q "NOISE" "$M" || fail "digest no longer drops passing lines"

# --quiet must be silent when nothing needs a human, or the nightly run
# becomes noise.
grep -q "if a.quiet and not human" "$M" || fail "--quiet always prints"

# Scheduling must be offline, not on load.
grep -q '"RunAtLoad": False' "$M" || fail "would run at load instead of offline"
grep -q "StartCalendarInterval" "$M" || fail "no schedule"

python3 -c "import ast;ast.parse(open('$M').read())" || fail "does not parse"
echo "  ok   maintain repairs and reports, and cannot commit or merge"

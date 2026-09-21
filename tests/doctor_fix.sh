#!/bin/bash
# doctor --fix must actually repair, not just report. Verified by BREAKING
# things and confirming they come back: a repair path that never fires in a
# test is untested, which is the mistake that shipped three times on
# 2026-09-20.
set -uo pipefail
ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
fail() { echo "  FAIL $1"; exit 1; }

SK="$HOME/.claude/skills"
HK="$HOME/.claude/hooks"
[ -d "$SK" ] && [ -d "$HK" ] || { echo "  skip doctor --fix (kit not installed)"; exit 0; }

BEFORE=$(ls "$SK" | wc -l | tr -d ' ')

# 1. a dangling link
ln -sfn /nonexistent/gone "$SK/.doctor-fix-test" 2>/dev/null
# 2. a hook that lost its bit
VIC_HOOK="$HK/env-guard.sh"
[ -f "$VIC_HOOK" ] && chmod -x "$VIC_HOOK"

"$ROOT/doctor.sh" --fix >/dev/null 2>&1 || true

D=$(find "$SK" -maxdepth 1 -type l ! -exec test -e {} \; -print 2>/dev/null | wc -l | tr -d ' ')
[ "$D" -eq 0 ] || fail "--fix left $D dangling skill link(s)"
[ ! -f "$VIC_HOOK" ] || [ -x "$VIC_HOOK" ] || fail "--fix did not restore the executable bit"

AFTER=$(ls "$SK" | wc -l | tr -d ' ')
[ "$AFTER" -ge "$BEFORE" ] || fail "--fix DELETED skills: $BEFORE -> $AFTER"

rm -f "$SK/.doctor-fix-test" 2>/dev/null
echo "  ok   doctor --fix repairs dangling links and lost executable bits"

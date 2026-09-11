#!/usr/bin/env bash
# Live: the `claude` CLI answers, so `chewbacca evals --run` means something.
#
# tools/evals.py has two modes. The no-model pass runs in CI and checks that
# eval files parse and name real skills. The behavioral pass shells out to
# `claude -p` and is the only one that measures whether a skill TRIGGERS. If the
# CLI is missing or the login is expired, that pass reports nothing and the kit
# looks evaluated when the only thing that ran was a JSON parser.
source "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
need claude "— npm i -g @anthropic-ai/claude-code, then: claude auth login"

ok "claude reports a version" lt 25 claude --version

# An expired login looks exactly like a working CLI until you ask it something.
# This is the check: one real round trip, with a deterministic answer.
ANS="$(lt 90 claude -p 'Reply with exactly one word: chewbacca' 2>&1)"
if printf '%s' "$ANS" | grep -qiE 'chewbacca'; then
  _pass=$((_pass+1)); printf "  \033[0;32mPASS\033[0m  claude -p completes a real round trip\n"
elif printf '%s' "$ANS" | grep -qiE 'auth|login|credential|expired|401|unauthor'; then
  unproven "claude is installed but NOT logged in — run: claude auth login"
  unproven "evals --run will report nothing until that is fixed"
else
  _fail=$((_fail+1))
  printf "  \033[0;31mFAIL\033[0m  claude -p did not answer\n"
  printf '%s' "$ANS" | sed 's/^/          /' | head -3
fi

# The eval harness itself, against the real skill tree.
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ok     "the no-model eval pass runs clean" python3 "$REPO/tools/evals.py"
mutant "evals reject a skill that does not exist" \
  python3 "$REPO/tools/evals.py" --run no-such-skill-anywhere

finish

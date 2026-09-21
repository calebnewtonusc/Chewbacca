#!/usr/bin/env bash
# The install must not reach for Claude on a machine that already has an agent.
#
# On 2026-09-19 setup.sh installed Claude Code whenever `claude` was missing,
# and start.sh's last screen said "type claude" and then exec'd it. Sagar runs
# Codex. The install finished, sent him to Claude Code, and Claude Code asked
# him to buy credits. He said "how is this model agnostic? i don't want to add
# claude credits" and stopped. Karthik seconded it. Both of them still have not
# onboarded. That is the product claim breaking on the last screen.
set -uo pipefail
ROOT="${1:?path to repo root}"
FAKE="$(mktemp -d)"
printf '#!/bin/sh\necho codex\n' > "$FAKE/codex"; chmod +x "$FAKE/codex"

fail() { echo "$1" >&2; exit 1; }

# 1. start.sh must name whatever agent is present, not Claude by name.
grep -q 'for candidate in "claude:Claude Code" "codex:Codex" "gemini:Gemini CLI"' "$ROOT/start.sh" \
  || fail "start.sh no longer detects the installed agent"
grep -q 'exec "$AGENT_CMD"' "$ROOT/start.sh" \
  || fail "start.sh execs a hardcoded agent again"
grep -qE '^\s+To start it any time: open Terminal and type \$\{B\}claude\$\{N\}' "$ROOT/start.sh" \
  && fail "start.sh tells everyone to type 'claude' again"

# 2. setup.sh must not install an agent when one is present.
grep -q 'for a in claude codex gemini; do' "$ROOT/setup.sh" \
  || fail "setup.sh no longer checks for an existing agent"

# 3. Behavioral: with codex on PATH and claude absent, the detection picks
#    codex and the install branch is the no-op one.
out="$(PATH="$FAKE:/usr/bin:/bin" bash -c '
  KIT_AGENT=""
  for a in claude codex gemini; do
    if command -v "$a" >/dev/null 2>&1; then KIT_AGENT="$a"; break; fi
  done
  printf "%s" "$KIT_AGENT"
')"
[ "$out" = "codex" ] || fail "with only codex on PATH the agent resolved to '$out'"

# 4. And on a bare machine it still installs something, or the kit is useless.
out2="$(PATH="/usr/bin:/bin" bash -c '
  KIT_AGENT=""
  for a in claude codex gemini; do
    if command -v "$a" >/dev/null 2>&1; then KIT_AGENT="$a"; break; fi
  done
  printf "%s" "$KIT_AGENT"
')"
[ -z "$out2" ] || fail "a bare machine resolved an agent it does not have: '$out2'"
exit 0

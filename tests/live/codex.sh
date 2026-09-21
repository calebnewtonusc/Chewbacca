#!/usr/bin/env bash
# Live: Codex installation and login; opt in to one read-only discovery round trip.
source "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
need codex "optional secondary agent"
ok "codex reports a version" lt 20 codex --version
if ! lt 20 codex login status >"$LIVE_SCRATCH/login" 2>&1; then
  unproven "Codex is installed but login is unavailable"
  exit 77
fi
ok "codex authentication is available without a model call" test -s "$LIVE_SCRATCH/login"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ok "agent instructions are current" python3 "$REPO/tools/agents_md.py" --check
mutant "missing instructions fail freshness check" python3 "$REPO/tools/agents_md.py" "$LIVE_SCRATCH" --check
if [ "${CHEWBACCA_CODEX_LIVE:-0}" = 1 ]; then
  ok "fresh Codex session discovers the agent roles" lt 120 codex exec --ephemeral --sandbox read-only -C "$REPO" \
    -o "$LIVE_SCRATCH/answer" 'Without tools or changing files, use the project instructions already loaded: name the primary agent and the separate browser model backend. Reply in one sentence.'
  ok "loaded instructions identify Claude Code" grep -qi 'Claude' "$LIVE_SCRATCH/answer"
  ok "loaded instructions identify ChatGPT Web" grep -qi 'ChatGPT' "$LIVE_SCRATCH/answer"
else
  unproven "model invocation omitted; CHEWBACCA_CODEX_LIVE=1 enables one read-only discovery call"
fi
finish

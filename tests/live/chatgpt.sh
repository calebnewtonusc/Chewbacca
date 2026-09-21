#!/usr/bin/env bash
# Live: one harmless browser model round trip. Never extracts credentials.
source "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
need chatgpt-tab "run Chewbacca tools setup"
if ! chatgpt-tab status --json --timeout 5 >"$LIVE_SCRATCH/status" 2>"$LIVE_SCRATCH/status.err"; then
  unproven "no idle signed-in ChatGPT browser session; check Chrome and Allow JavaScript from Apple Events"
  exit 77
fi
nonce="CHEWBACCA_LIVE_$(date +%s)_$$"
if chatgpt-tab ask "Bridge test only. Reply exactly $nonce with no other text. Do not use tools." --timeout 90 >"$LIVE_SCRATCH/answer" 2>"$LIVE_SCRATCH/turn.err"; then
  ok "new completed ChatGPT response matches the nonce" grep -qx "$nonce" "$LIVE_SCRATCH/answer"
else
  _fail=$((_fail+1))
  printf '  FAIL  ChatGPT round trip\n'
  cat "$LIVE_SCRATCH/turn.err"
fi
mutant "old or invented text cannot satisfy the round trip" grep -qx 'CHEWBACCA_NOT_THE_NONCE' "$LIVE_SCRATCH/answer"
finish

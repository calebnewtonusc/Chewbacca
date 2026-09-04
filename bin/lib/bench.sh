#!/usr/bin/env bash
# chewbacca bench: time the things that run before you can type.
#
# Nothing in this kit had ever been measured. Eight hooks run at session
# start and the only evidence about their cost was that sessions felt fine.
set -uo pipefail
CLAUDE_DIR="$HOME/.claude"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BLD='\033[1m'; DIM='\033[2m'; YLW='\033[1;33m'; RED='\033[0;31m'; GRN='\033[0;32m'; NC='\033[0m'
RUNS="${1:-3}"

ms_now() { python3 -c 'import time;print(int(time.time()*1000))'; }

time_cmd() {
  local best=999999 i start end
  for ((i = 0; i < RUNS; i++)); do
    start=$(ms_now)
    "$@" >/dev/null 2>&1 || true
    end=$(ms_now)
    (( end - start < best )) && best=$((end - start))
  done
  echo "$best"
}

verdict() {
  local ms="$1" budget="$2"
  if [ "$ms" -lt "$budget" ]; then echo -e "${GRN}ok${NC}"
  elif [ "$ms" -lt $((budget * 2)) ]; then echo -e "${YLW}slow${NC}"
  else echo -e "${RED}over budget${NC}"; fi
}

echo -e "${BLD}Session start${NC}  ${DIM}best of $RUNS, budget in parentheses${NC}"
TOTAL=0
for h in "$CLAUDE_DIR"/hooks/*.sh; do
  [ -x "$h" ] || continue
  name="$(basename "$h")"
  case "$name" in
    session-context.sh | coursework-context.sh | kit-route.sh | statusline.sh) budget=400 ;;
    *) continue ;;
  esac
  ms=$(printf '{}' | time_cmd bash "$h")
  TOTAL=$((TOTAL + ms))
  printf '  %-26s %6sms  (%s)  %b\n' "$name" "$ms" "$budget" "$(verdict "$ms" "$budget")"
done
echo -e "  ${BLD}%-26s${NC}" >/dev/null
printf '  %-26s %6sms  (%s)  %b\n' "TOTAL before first token" "$TOTAL" "1000" "$(verdict "$TOTAL" 1000)"

echo -e "\n${BLD}Tools${NC}"
for spec in "./doctor.sh --quiet:8000" "python3 bin/slop-check README.md:1500"; do
  cmd="${spec%%:*}"; budget="${spec##*:}"
  # shellcheck disable=SC2086
  ms=$(time_cmd bash -c "cd '$ROOT' && $cmd")
  printf '  %-26s %6sms  (%s)  %b\n' "$cmd" "$ms" "$budget" "$(verdict "$ms" "$budget")"
done

if command -v people >/dev/null 2>&1; then
  ms=$(time_cmd people list --limit 1)
  printf '  %-26s %6sms  (%s)  %b\n' "people list" "$ms" "500" "$(verdict "$ms" 500)"
fi

echo -e "\n${DIM}Budgets are the kit's own targets, not the OS's. A number over budget"
echo -e "is a bug report, not a warning.${NC}"

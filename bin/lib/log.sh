#!/usr/bin/env bash
# chewbacca log: what the kit has actually been doing.
#
# Hooks ran on every session, wrote nothing down, and failed silently. Now
# they append here and this reads it back.
set -uo pipefail
LOGDIR="$HOME/.chewbacca/logs"
BLD='\033[1m'; DIM='\033[2m'; RED='\033[0;31m'; NC='\033[0m'
N="${2:-40}"

case "${1:-recent}" in
recent | "")
  [ -f "$LOGDIR/hooks.log" ] || { echo "No hook log yet. It fills as you use the kit."; exit 0; }
  echo -e "${BLD}Recent hook activity${NC} ${DIM}(when|hook|ms|status)${NC}"
  tail -n "$N" "$LOGDIR/hooks.log" | while IFS='|' read -r when hook ms status detail; do
    color=""; [ "$status" != "ok" ] && color="$RED"
    printf "  ${DIM}%s${NC}  %-22s %6sms  ${color}%s${NC} %s\n" \
      "$when" "$hook" "$ms" "$status" "${detail:-}"
  done
  ;;
slow)
  [ -f "$LOGDIR/hooks.log" ] || { echo "No hook log yet."; exit 0; }
  echo -e "${BLD}Slowest hook runs${NC}"
  sort -t'|' -k3 -rn "$LOGDIR/hooks.log" | head -n "$N" |
    while IFS='|' read -r when hook ms status _; do
      printf "  %6sms  %-22s ${DIM}%s${NC}\n" "$ms" "$hook" "$when"
    done
  ;;
errors)
  [ -f "$LOGDIR/hooks.log" ] || { echo "No hook log yet."; exit 0; }
  grep -v '|ok|' "$LOGDIR/hooks.log" 2>/dev/null | tail -n "$N" ||
    echo "No hook has failed since logging started."
  ;;
stats)
  [ -f "$LOGDIR/hooks.log" ] || { echo "No hook log yet."; exit 0; }
  echo -e "${BLD}Per-hook totals${NC}"
  awk -F'|' '{n[$2]++; t[$2]+=$3; if($4!="ok") e[$2]++}
    END{for(h in n) printf "  %-22s %5d runs  %7.0fms avg  %d failed\n", h, n[h], t[h]/n[h], e[h]+0}' \
    "$LOGDIR/hooks.log" | sort -k2 -rn
  ;;
path)
  echo "$LOGDIR"
  ;;
*)
  echo "usage: chewbacca log [recent|slow|errors|stats|path] [count]" >&2
  exit 2
  ;;
esac

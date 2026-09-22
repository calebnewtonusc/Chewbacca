#!/usr/bin/env bash
# Drives real gestures through the running Portal and reports what opened.
#
# Not a simulation of the detector: the replay pushes landmark frames through
# window.chewbaccaHands, the same entry point the camera uses, so it exercises
# the mapping, the detector, the state machine and the renderer together.
# Three separate times today a unit test passed while the application was
# broken, because the test built its input more carefully than the caller did.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG=/tmp/portal-live.log
DEMO="$HOME/.chewbacca/portal-demo"

pkill -f "Portal.app/Contents/MacOS/Portal" 2>/dev/null; sleep 1
"$ROOT/hud/build/Portal.app/Contents/MacOS/Portal" > "$LOG" 2>&1 &
sleep 5

run() { # name shape radius turns  -> prints OPENED/refused
  printf '%s %s %s %s %s' 5 "$4" "$3" "$2" "$1" > "$DEMO"
  local waited=0
  while [ "$waited" -lt 90 ]; do
    sleep 0.2; waited=$((waited+1))
    line=$(grep "^portal: RESULT $1 " "$LOG" | tail -1)
    [ -n "$line" ] && { echo "${line##* }"; return; }
  done
  echo "timeout"
}

pass=0; fail=0
check() { # name want shape radius turns
  got=$(run "$1" "$3" "$4" "$5")
  if [ "$got" = "$2" ]; then printf '  ok    %-22s %s\n' "$1" "$got"; pass=$((pass+1))
  else printf '  FAIL  %-22s wanted %s got %s\n' "$1" "$2" "$got"; fail=$((fail+1)); fi
}

echo "must open a portal:"
check small-circle   OPENED  circle  0.16 1.15
check medium-circle  OPENED  circle  0.30 1.15
check large-circle   OPENED  circle  0.42 1.15
check slow-circle    OPENED  circle  0.30 0.75
check overshoot      OPENED  circle  0.30 1.60
check oval-1-4       OPENED  oval14  0.24 1.15

echo "must not:"
check oval-2-5       refused oval25  0.18 1.15
check triangle       refused triangle 0.30 1.15
check square         refused square  0.30 1.15
check line           refused line    0.40 1.00
check zigzag         refused zigzag  0.40 1.00
check s-curve        refused scurve  0.40 1.00
check arc-70pct      refused arc70   0.30 1.00
check arc-90pct      refused arc90   0.30 1.00

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]

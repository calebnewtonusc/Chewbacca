#!/usr/bin/env bash
# Is Secure Input on? While it is, synthetic keystrokes are silently discarded.
# The flag lives in the IOConsoleUsers dict as kCGSSessionSecureInputPID.
# 0 or absent means off. Any other value is the pid holding it.
set -uo pipefail

pids=$(ioreg -l -w 0 -d 1 -k IOConsoleUsers 2>/dev/null \
  | grep -o 'kCGSSessionSecureInputPID"=[0-9]*' \
  | cut -d= -f2 | sort -u | grep -v '^0$' || true)

if [ -z "$pids" ]; then
  echo "secure_input=off"
  exit 0
fi

echo "secure_input=on"
for p in $pids; do
  name=$(ps -p "$p" -o comm= 2>/dev/null | sed 's|.*/||')
  echo "  held_by pid=$p ${name:-unknown}"
done
cat <<'NOTE'
  Synthetic keystrokes will be dropped with no error while this is on.
  Fix: move focus off the password field. Click a neutral area, or:
       open -a Finder
  If loginwindow is the holder, a system authentication dialog or the
  lock screen has focus somewhere. Dismiss it and re-check.
  A holder that never releases is a stuck app: focus and unfocus it, or quit it.
NOTE
exit 1

#!/usr/bin/env bash
# Live: mac-cli (macoscli.sh) can actually reach the apps the `mac-apps` skill
# tells Claude it can reach.
#
# This is the check doctor.sh structurally cannot be. `command -v mac` says yes
# on a machine where every Calendar read returns empty because TCC granted
# writeOnly and never full access. The skill then tells Claude that
# `mac calendar list` works, Claude calls it, gets nothing, and reports that the
# user has no events. Installed and usable are different questions.
#
# A capability macOS has not granted is UNPROVEN, not failed: the kit did not
# break it and cannot fix it from here. `mac doctor` prints the fix.
source "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
need mac "— see https://macoscli.sh, or: chewbacca setup"

ok   "mac doctor answers at all"     lt 25 mac doctor
says "doctor reports fullDiskAccess" "fullDiskAccess" lt 25 mac doctor

DOC="$(lt 25 mac doctor 2>&1)"

# granted <capability>   is this capability actually usable right now
granted() { printf '%s' "$DOC" | grep -qE "^$1: granted"; }

# Each capability: prove a real read, or say plainly that nothing was proven.
if granted reminders; then
  ok "reminders list returns valid JSON" \
    bash -c "lt 25 mac reminders list --json 2>/dev/null | python3 -m json.tool >/dev/null"
else
  unproven "reminders not granted — mac doctor prints the fix"
fi

if granted contacts; then
  ok "contacts find returns valid JSON" \
    bash -c "lt 25 mac contacts find a --json 2>/dev/null | python3 -m json.tool >/dev/null"
else
  unproven "contacts not granted — mac doctor prints the fix"
fi

# Calendar is the one that lies. writeOnly is a real TCC state: adds succeed,
# every read comes back empty, and nothing errors. Treating that as a pass is
# how the kit ends up telling someone their week is clear.
if granted calendar; then
  ok "calendar list returns valid JSON" \
    bash -c "lt 25 mac calendar list --from today --to +7d --json 2>/dev/null | python3 -m json.tool >/dev/null"
else
  unproven "calendar is NOT fully granted (writeOnly or denied) — reads will come back EMPTY, not error"
fi

# --json on every command is the contract the mac-apps skill is written against.
mutant "an invented subcommand is refused" lt 20 mac teleport --json
mutant "an invented flag is refused"       lt 20 mac reminders list --nonsense

finish

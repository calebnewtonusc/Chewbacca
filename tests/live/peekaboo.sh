#!/usr/bin/env bash
# Live: peekaboo can actually see the screen.
#
# The mac-see and mac-control skills tell Claude it can read the screen and the
# accessibility tree. Both die without a TCC grant, and both die QUIETLY: a
# denied screen capture can still write a file, so "the command exited 0 and a
# png exists" proves nothing. This asserts on the bytes.
source "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
need peekaboo "— run: chewbacca setup"

PERMS="$(lt 20 peekaboo permissions 2>&1)"
says "peekaboo reports its permissions" "Screen Recording" bash -c "printf '%s' \"\$0\"" "$PERMS"

if ! printf '%s' "$PERMS" | grep -qE 'Screen Recording.*Granted'; then
  unproven "Screen Recording is NOT granted — every capture returns a blank or fails"
  unproven "skipping the capture checks; run: chewbacca doctor, or the mac-permissions skill"
  finish
fi

SHOT="$LIVE_SCRATCH/shot.png"
ok "capture exits clean" lt 30 peekaboo image --mode screen --path "$SHOT"
ok "capture produced a file" test -f "$SHOT"

# The real assertion. A refused capture on macOS can still leave a file behind,
# so check the PNG magic bytes and that the image has actual dimensions.
ok "the file is a real PNG, not an empty placeholder" \
  bash -c "head -c8 '$SHOT' | od -An -tx1 | tr -d ' \n' | grep -qi '^89504e470d0a1a0a'"
ok "the PNG is larger than a blank frame (>20KB)" \
  bash -c "[ \"\$(wc -c < '$SHOT')\" -gt 20480 ]"

# The mutants: both assertions must be breakable by the failure they describe.
printf 'not a png' > "$LIVE_SCRATCH/fake.png"
mutant "a text file fails the PNG magic check" \
  bash -c "head -c8 '$LIVE_SCRATCH/fake.png' | od -An -tx1 | tr -d ' \n' | grep -qi '^89504e470d0a1a0a'"
mutant "a tiny file fails the size floor" \
  bash -c "[ \"\$(wc -c < '$LIVE_SCRATCH/fake.png')\" -gt 20480 ]"

# The accessibility tree is the layer mac-act clicks through. An empty tree is
# the single most common silent failure in Mac automation.
if printf '%s' "$PERMS" | grep -qE 'Accessibility.*Granted'; then
  ok "the accessibility tree is non-empty" \
    bash -c "lt 30 peekaboo list apps 2>/dev/null | grep -q ."
else
  unproven "Accessibility is NOT granted — every click and keystroke will no-op"
fi

finish

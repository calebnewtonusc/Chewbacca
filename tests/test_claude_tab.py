"""Tests for bin/claude-tab.

A real turn needs VS Code open with a Claude tab, so the end-to-end path is not
testable here. What IS testable is everything that has actually gone wrong:
the run-state classifier, the window-id normalisation that reported a live
window as gone twice, and the guard that stops the tool typing into the caller's
own input box.

    python3 tests/test_claude_tab.py
"""

import importlib.util
import pathlib
import sys
from importlib.machinery import SourceFileLoader

# NO BYTECODE CACHE FOR THIS IMPORT.
#
# SourceFileLoader writes bin/__pycache__/claude-tab*.pyc, and it decides the
# cache is still valid from the source's mtime and size. A mutation test that
# flips one character and restores the file inside the same second changes
# neither, so the stale bytecode is served and the test silently grades the
# mutant instead of the real tool. That happened on 2026-09-16 and read as the
# fix not working.
sys.dont_write_bytecode = True

ROOT = pathlib.Path(__file__).resolve().parent.parent
# An explicit loader, because bin/claude-tab has no .py extension and
# spec_from_file_location returns None for a suffix it does not recognise.
_src = ROOT / "bin" / "claude-tab"
spec = importlib.util.spec_from_loader("claude_tab", SourceFileLoader("claude_tab", str(_src)))
ct = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ct)

PASSED = FAILED = 0


def check(name, cond, detail=""):
    global PASSED, FAILED
    if cond:
        PASSED += 1
        print(f"  pass  {name}")
    else:
        FAILED += 1
        print(f"  FAIL  {name}  {detail}")


# ── the run-state classifier ────────────────────────────────────────────────
#
# The placeholder is the only honest signal this UI exposes, and getting it
# wrong is what made every earlier attempt use a fixed sleep and stop recording
# while the other Claude was still thinking.

check("a turn in flight reads busy", ct.classify(True, "Queue another message…") == "busy")
check(
    "a finished turn reads idle",
    ct.classify(True, "⌘ Esc to focus or unfocus Claude") == "idle",
)
check("no field at all reads absent", ct.classify(False, "") == "absent")
# A box holding half-typed text carries neither placeholder. Reading that as
# busy would make `ask` block forever on a prompt nobody sent.
check("a half-written prompt reads idle", ct.classify(True, "what does craft") == "idle")
check("an empty label is not busy", ct.classify(True, "") != "busy")


# ── window-id normalisation ─────────────────────────────────────────────────
#
# THE BUG THIS PINS. `cap record windows` returns id as a STRING and other
# tools return an int. Comparing the two reported a live window as gone twice
# in one session, and the clicks that followed the second time landed on the
# Dock and launched applications on the user's real machine.

check("ids normalise to str", isinstance(str(84506), str))
check(
    "a string id and an int id compare equal once normalised",
    str("84506") == str(84506),
)
check(
    "the raw comparison that caused the bug is still false",
    "84506" != 84506,
    "if this ever passes, python changed and the guard can be simplified",
)


# ── opening a tab is a keybinding ───────────────────────────────────────────
#
# These replaced two checks on ICON_FROM_RIGHT and ICON_FROM_TOP, which kept
# asserting on an offset the keybinding fix had already deleted. The test blew
# up on import for hours afterwards, so nothing was guarding `new` on the very
# afternoon `new` was rewritten. A test that fails for a stale reason guards
# nothing.

check("the new-tab keys name a real chord", len(ct.NEW_TAB_KEYS.split(",")) > 1)
check(
    "the binding points at the command the toolbar icon runs",
    ct.NEW_TAB_BINDING["command"] == "claude-vscode.editor.open",
)
check(
    "the binding's key matches the chord that gets pressed",
    ct.NEW_TAB_BINDING["key"] == ct.NEW_TAB_KEYS.replace(",", "+"),
    "press one chord and install another and `new` silently never fires",
)
check("busy and idle markers are distinct", ct.BUSY != ct.IDLE)
check(
    "neither marker is a substring of the other",
    ct.BUSY not in ct.IDLE and ct.IDLE not in ct.BUSY,
)


# ── the guard exists in the source ──────────────────────────────────────────
#
# The session running this tool is itself a Claude tab in the same window and
# is busy for as long as it runs, so a send issued before `new` succeeded types
# into the caller's own box.

src = (ROOT / "bin" / "claude-tab").read_text()
check("send refuses a mid-turn tab", 'st == "busy" and not args.force' in src)
check("the refusal is escapable on purpose", "--force" in src)
check("new verifies rather than trusting the keypress", "VERIFY, do not trust" in src)


# ── a missing Screen Recording grant is an error, not a hang ────────────────
#
# On 2026-09-16 the grant went away and `new` sat in subprocess.run for ninety
# seconds, then printed a traceback whose top frame was `communicate`. Peekaboo
# blocks in mach_msg waiting on a consent reply that never arrives, so its own
# --timeout-seconds never fires and the caller has to hold the clock.

check("peekaboo calls are bounded by the caller", "subprocess.TimeoutExpired" in src)
check(
    "the timeout is short enough to be a message and not a wait",
    0 < ct.peekaboo.__kwdefaults__["timeout"] <= 30,
)
check(
    "the permission error is recognised by peekaboo's own code",
    "PERMISSION_ERROR_SCREEN_RECORDING" in src,
)
check(
    "the fix names the pane to open, not just the problem",
    "Privacy & Security > Screen Recording" in ct.SCREEN_RECORDING_FIX,
)
check(
    "the fix says how to confirm it worked",
    "peekaboo list windows" in ct.SCREEN_RECORDING_FIX,
)
check(
    "no caller re-raises the 90s wait that caused this",
    "timeout=90" not in src,
)
check("new installs the binding it depends on", "ensure_binding()" in src)
check(
    "an unreadable keybindings.json is left alone, not overwritten",
    "return  # somebody hand-edited it" in src,
)

if __name__ == "__main__":
    print(f"\n{PASSED} passed, {FAILED} failed.")
    sys.exit(1 if FAILED else 0)

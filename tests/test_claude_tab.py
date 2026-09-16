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


# ── the offsets carry their measurement ─────────────────────────────────────

check("the icon offset is anchored to the right edge", ct.ICON_FROM_RIGHT > 0)
check("the icon offset is anchored below the top", ct.ICON_FROM_TOP > 0)
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
check("new verifies rather than trusting the click", "VERIFY, do not trust" in src)

if __name__ == "__main__":
    print(f"\n{PASSED} passed, {FAILED} failed.")
    sys.exit(1 if FAILED else 0)

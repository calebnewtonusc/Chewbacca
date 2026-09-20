#!/usr/bin/env python3
"""mac/lib/terminal.py, without a Terminal.

Everything that opens a window is in tests/live/terminal.sh. What is here is
the tab parser, the choice rule, and the one-paragraph collapse, because a
wrong tab choice pastes a prompt into someone's live shell.

    python3 tests/test_terminal.py
"""
import importlib.util
import pathlib
import sys
from importlib.machinery import SourceFileLoader

sys.dont_write_bytecode = True
ROOT = pathlib.Path(__file__).resolve().parent.parent
_src = ROOT / "mac" / "lib" / "terminal.py"
spec = importlib.util.spec_from_loader("terminal", SourceFileLoader("terminal", str(_src)))
t = importlib.util.module_from_spec(spec)
spec.loader.exec_module(t)

PASSED = FAILED = 0


def check(name, cond, detail=""):
    global PASSED, FAILED
    if cond:
        PASSED += 1
        print(f"  pass  {name}")
    else:
        FAILED += 1
        print(f"  FAIL  {name}  {detail}")


RAW = (
    "/dev/ttys001\ttrue\ttrue\tlogin,-zsh\n"
    "/dev/ttys002\tfalse\ttrue\tlogin,-zsh,claude\n"
    "/dev/ttys003\ttrue\tfalse\tlogin,-zsh,claude\n"
    "\n"
)

tabs = t.parse_tabs(RAW)
check("three tabs parsed, blank line ignored", len(tabs) == 3, str(tabs))
check("tty is the first field", tabs[0]["tty"] == "/dev/ttys001")
check("selected parses as bool", tabs[0]["selected"] is True and tabs[1]["selected"] is False)
check("front parses as bool", tabs[2]["front"] is False)
check("processes split on comma", tabs[1]["processes"] == ["login", "-zsh", "claude"])
check("empty output is no tabs", t.parse_tabs("") == [])

check("a tab running claude is a candidate", t.is_candidate(tabs[1]))
check("a plain shell is not", not t.is_candidate(tabs[0]))

check("the remembered tty wins", t.choose(tabs, "/dev/ttys003")["tty"] == "/dev/ttys003")
check(
    "a remembered tty that is gone is ignored",
    t.choose(tabs, "/dev/ttys999")["tty"] == "/dev/ttys002",
)
# ttys002 is a candidate in the front window but not selected; ttys003 is
# selected in a back window. With nothing remembered, front-and-selected
# would win, and neither is, so the first candidate does.
check("with nothing remembered, the first candidate", t.choose(tabs, None)["tty"] == "/dev/ttys002")
front_selected = t.parse_tabs(
    "/dev/ttys001\tfalse\ttrue\tlogin,-zsh,claude\n"
    "/dev/ttys002\ttrue\ttrue\tlogin,-zsh,claude\n"
)
check(
    "selected tab of the front window beats an earlier candidate",
    t.choose(front_selected, None)["tty"] == "/dev/ttys002",
)
check("no candidates is None", t.choose(t.parse_tabs("/dev/ttys001\ttrue\ttrue\tlogin,-zsh\n"), None) is None)

check("newlines collapse to one space", t.collapse("build a\nsignaler\n\nfor AAPL") == "build a signaler for AAPL")
check("runs of spaces collapse", t.collapse("a   b\t c") == "a b c")
check("ends trimmed", t.collapse("  hi \n") == "hi")

print(f"\n{PASSED} passed, {FAILED} failed")
sys.exit(1 if FAILED else 0)

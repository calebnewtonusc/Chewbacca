"""The watcher's restraint, which is the only part that matters.

Anyone can build a thing that interrupts. The reason proactive assistants are
rare and bad is that the budget is the hard part, so that is what this covers:
it says a thing once, it stays quiet afterwards, and it stops entirely when it
has spoken enough.
"""

from __future__ import annotations

import importlib.util
import os
import sys
import tempfile
import time
from importlib.machinery import SourceFileLoader
from pathlib import Path

BIN = Path(__file__).resolve().parent.parent / "bin" / "hud-watch"
failures: list[str] = []


def check(name: str, ok: bool, detail: str = "") -> None:
    print(f"  {'ok  ' if ok else 'FAIL'} {name} {detail}".rstrip())
    if not ok:
        failures.append(name)


def load(state_dir: str):
    os.environ["CHEWBACCA_STATE_DIR"] = state_dir
    spec = importlib.util.spec_from_file_location(
        "hud_watch", BIN, loader=SourceFileLoader("hud_watch", str(BIN))
    )
    m = importlib.util.module_from_spec(spec)
    sys.modules["hud_watch"] = m
    spec.loader.exec_module(m)
    return m


def main() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        m = load(tmp)
        now = time.time()

        f = m.Finding(key="k", severity=4, title="T", lines=["r x"])
        worse = m.Finding(key="k", severity=5, title="T", lines=["r x"])

        state = {"shown": {}, "times": []}
        check("nothing said yet is not a repeat", not m.already_said(state, f, now))

        state["shown"][f.fingerprint()] = now
        check("the same finding is a repeat", m.already_said(state, f, now))
        check(
            "the same finding getting worse is not a repeat",
            not m.already_said(state, worse, now),
            "severity is in the fingerprint",
        )
        check(
            "a repeat expires eventually",
            not m.already_said(state, f, now + m.REPEAT_AFTER + 1),
        )

        fresh = {"shown": {}, "times": []}
        for i in range(m.BUDGET_PER_HOUR):
            check(f"within budget at {i}", m.within_budget(fresh, now))
            fresh["times"].append(now)
        check("budget runs out", not m.within_budget(fresh, now))
        check(
            "budget refills after an hour",
            m.within_budget({"shown": {}, "times": [now - 3601]}, now),
        )

        # Colour codes must never reach the parser.
        check("ansi is stripped", m.plain("\x1b[31mred\x1b[0m") == "red")
        # A tool that exits non-zero on findings must still be read.
        check(
            "stdout is read whatever the exit code",
            m.run([sys.executable, "-c", "print('out'); raise SystemExit(1)"]).strip() == "out",
        )

    print()
    if failures:
        print(f"{len(failures)} failed: {', '.join(failures)}")
        return 1
    print("all passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())

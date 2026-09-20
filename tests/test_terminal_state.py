#!/usr/bin/env python3
"""One terminal state, folded from hook events. Run: python3 tests/test_terminal_state.py"""
import json
import sys
import tempfile
from importlib.machinery import SourceFileLoader
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ts = SourceFileLoader("terminal_state", str(ROOT / "bin" / "lib" / "terminal_state.py")).load_module()
# The writer, so the rotation is exercised through the code that does it
# rather than through a rename this file performs itself.
te = SourceFileLoader("terminal_events", str(ROOT / "mac" / "lib" / "terminal_events.py")).load_module()

PASSED = 0
FAILED = 0


def check(name: str, cond: bool, detail: str = "") -> None:
    global PASSED, FAILED
    if cond:
        PASSED += 1
        print(f"  pass  {name}")
    else:
        FAILED += 1
        print(f"  FAIL  {name}  {detail}")


def ev(event: str, **kw) -> dict:
    base = {"t": 100.0, "event": event, "tool": "", "summary": "", "session": "s", "ask": "", "held": False}
    base.update(kw)
    return base


def main() -> int:
    s = ts.initial()
    check("starts idle", s["state"] == "idle")
    check("idle is t off", ts.strip_line(s) == "t off")
    s = ts.fold(s, ev("PreToolUse", tool="Bash", summary="npm test"))
    check("a tool call is running with its summary", s["state"] == "running" and s["text"] == "npm test")
    check("running strip", ts.strip_line(s) == 't "npm test" state=running', ts.strip_line(s))
    s = ts.fold(s, ev("PostToolUse", tool="Bash"))
    check("after the tool, still running with no text", s["state"] == "running" and s["text"] == "")
    check("running with nothing named says working", ts.strip_line(s) == 't "working" state=running')
    s = ts.fold(s, ev("PermissionRequest", tool="Bash", summary="rm -rf build", ask="a1", held=True))
    check("a held ask is waiting, held", s["state"] == "waiting" and s["held"] is True and s["ask"] == "a1")
    check("waiting strip", ts.strip_line(s) == 't "waiting on you: rm -rf build" state=waiting', ts.strip_line(s))
    s = ts.fold(s, ev("ask_expired", ask="a1"))
    check("an expired ask is still waiting, no longer held", s["state"] == "waiting" and s["held"] is False)
    s = ts.fold(s, ev("ask_answered", ask="a1", summary="allow"))
    check("an answered ask is running", s["state"] == "running" and s["ask"] == "")
    s = ts.fold(s, ev("PermissionRequest", tool="Bash", summary="x", ask="", held=False))
    check("an unheld ask is waiting, not held", s["state"] == "waiting" and s["held"] is False)
    s = ts.fold(s, ev("PermissionDenied", tool="Bash"))
    check("a denial in the tab clears waiting", s["state"] == "running")
    s = ts.fold(s, ev("Stop", summary="All green."))
    check("stop is done with the sentence", s["state"] == "done" and s["text"] == "All green.")
    check("done strip", ts.strip_line(s) == 't "finished: All green." state=done', ts.strip_line(s))
    check("done is not expired early", ts.expire(s, 100.0 + ts.IDLE_AFTER_S - 1)["state"] == "done")
    check("done expires to idle", ts.expire(s, 100.0 + ts.IDLE_AFTER_S + 1)["state"] == "idle")
    s = ts.fold(s, ev("SessionEnd"))
    check("session end is idle", s["state"] == "idle")
    check("fold never mutates its input", ts.initial() == ts.fold(ts.initial(), ev("SessionEnd")))

    print("tail")
    tmp = Path(tempfile.mkdtemp()) / "events.jsonl"
    got, cur = ts.tail(tmp, ts.START)
    check("no file: nothing, the cursor stays at the start", got == [] and cur == ts.START)
    tmp.write_text(json.dumps(ev("PreToolUse")) + "\n")
    got, cur = ts.tail(tmp, ts.START)
    check("one line read", len(got) == 1 and cur == (tmp.stat().st_ino, tmp.stat().st_size), str(cur))
    got2, cur2 = ts.tail(tmp, cur)
    check("nothing new: nothing", got2 == [] and cur2 == cur)
    with tmp.open("a") as f:
        f.write("garbage\n" + json.dumps(ev("Stop")) + "\n")
    got3, cur3 = ts.tail(tmp, cur)
    check("appended lines read, garbage skipped",
          [g["event"] for g in got3] == ["Stop"] and cur3[1] == tmp.stat().st_size)
    tmp.write_text(json.dumps(ev("SessionEnd")) + "\n")
    got4, cur4 = ts.tail(tmp, cur3)
    check("a truncated file under the same inode restarts from the top",
          [g["event"] for g in got4] == ["SessionEnd"])

    print("rotation")
    # The bug this cursor exists for: the writer rotates the file past its
    # size cap, and a bare byte offset could not tell a new file from more
    # bytes in the old one. Every entry has to arrive exactly once.
    te.MEMORY = Path(tempfile.mkdtemp())
    te.EVENTS = te.MEMORY / "terminal-events.jsonl"
    te.EVENTS_MAX_BYTES = 400

    def line(i: int) -> dict:
        return {"t": 100.0 + i, "event": "PreToolUse", "tool": "Bash", "summary": str(i)}

    seen: list[str] = []
    cursor = ts.START
    for i in range(12):
        te.append(line(i))
        entries, cursor = ts.tail(te.EVENTS, cursor)
        seen.extend(e["summary"] for e in entries)
    check("polling every append: every entry exactly once across the rotations",
          seen == [str(i) for i in range(12)], str(seen))
    check("the log did rotate", te.EVENTS.with_name(te.EVENTS.name + ".1").exists())

    te.EVENTS = te.MEMORY / "batch.jsonl"
    te.EVENTS_MAX_BYTES = 10_000
    te.append(line(0))
    got5, cursor = ts.tail(te.EVENTS, ts.START)
    te.append(line(1))
    te.append(line(2))
    te.EVENTS_MAX_BYTES = 1  # the next append crosses the cap and rotates
    te.append(line(3))
    got6, cursor = ts.tail(te.EVENTS, cursor)
    check("entries written between polls are drained from .1, from the old offset",
          [e["summary"] for e in got6] == ["1", "2", "3"], str([e["summary"] for e in got6]))
    te.EVENTS_MAX_BYTES = 10_000
    te.append(line(4))
    got7, cursor = ts.tail(te.EVENTS, cursor)
    check("the file that replaced it is read from the top, once",
          [e["summary"] for e in got7] == ["4"], str([e["summary"] for e in got7]))
    got8, cursor8 = ts.tail(te.EVENTS, cursor)
    check("and then there is nothing new", got8 == [] and cursor8 == cursor)

    print(f"\n{PASSED} passed, {FAILED} failed")
    return 1 if FAILED else 0


if __name__ == "__main__":
    sys.exit(main())

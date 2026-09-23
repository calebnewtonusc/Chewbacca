#!/usr/bin/env python3
"""The hook, without Claude Code: fake events on stdin, a temp memory dir,
an injected front-app check and clock. Run: python3 tests/test_terminal_events.py"""
import contextlib
import io
import json
import sys
import tempfile
import time
from importlib.machinery import SourceFileLoader
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
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


def point_at(tmp: str) -> None:
    te.MEMORY = Path(tmp)
    te.EVENTS = Path(tmp) / "terminal-events.jsonl"
    te.AGENT_EVENTS = Path(tmp) / "agent-events.jsonl"
    te.ASKS = Path(tmp) / "asks"
    te.PROJECT = Path(tmp) / "project.json"


def event(name: str, cwd: str, **extra) -> dict:
    base = {"hook_event_name": name, "session_id": "abc123", "cwd": cwd, "transcript_path": "/x"}
    base.update(extra)
    return base


def entries() -> list[dict]:
    if not te.EVENTS.exists():
        return []
    return [json.loads(l) for l in te.EVENTS.read_text().splitlines() if l.strip()]


class Clock:
    def __init__(self) -> None:
        self.now = 1000.0

    def __call__(self) -> float:
        return self.now

    def sleep(self, s: float) -> None:
        self.now += s


def main() -> int:
    tmp = tempfile.mkdtemp()
    point_at(tmp)
    proj = tempfile.mkdtemp()
    Path(tmp, "project.json").write_text(json.dumps({"cwd": proj, "tty": "/dev/ttys002"}))

    print("summaries")
    check("bash is its command", te.summary(event("PreToolUse", proj, tool_name="Bash",
          tool_input={"command": "npm test"})) == "npm test")
    check("edit is the file's name", te.summary(event("PreToolUse", proj, tool_name="Edit",
          tool_input={"file_path": "/a/b/route.py"})) == "route.py")
    check("agent is its description", te.summary(event("PreToolUse", proj, tool_name="Agent",
          tool_input={"description": "Review the diff"})) == "Review the diff")
    check("other tools are their name", te.summary(event("PreToolUse", proj, tool_name="WebFetch",
          tool_input={"url": "x"})) == "WebFetch")
    check("stop is the first sentence", te.summary(event("Stop", proj,
          last_assistant_message="Done. Three files changed.\n\nNext I would...")) == "Done.")
    check("summaries are capped", len(te.summary(event("PreToolUse", proj, tool_name="Bash",
          tool_input={"command": "x" * 500}))) == te.SUMMARY_CHARS)
    check("whitespace collapses", te.summary(event("PreToolUse", proj, tool_name="Bash",
          tool_input={"command": "a\n  b\tc"})) == "a b c")

    print("the filter")
    Path(tmp, "project.json").unlink()
    te.handle(json.dumps(event("PreToolUse", proj, tool_name="Bash", tool_input={"command": "ls"})),
              front=lambda: "", sleep=lambda s: None, clock=lambda: 0.0)
    check("no project file: nothing written", not te.EVENTS.exists())
    Path(tmp, "project.json").write_text(json.dumps({"cwd": proj}))
    te.handle(json.dumps(event("PreToolUse", "/somewhere/else", tool_name="Bash", tool_input={"command": "ls"})),
              front=lambda: "", sleep=lambda s: None, clock=lambda: 0.0)
    check("another cwd: nothing written", not te.EVENTS.exists())
    board = [json.loads(l) for l in te.AGENT_EVENTS.read_text().splitlines()]
    check("another cwd still reaches the agent board", len(board) == 2
          and board[-1]["cwd"] == "/somewhere/else" and board[-1]["session"] == "abc123", str(board))
    te.handle(json.dumps(event("UserPromptSubmit", proj)), front=lambda: "", sleep=lambda s: None, clock=lambda: 0.0)
    check("an event outside the handled six: nothing written", not te.EVENTS.exists())
    te.handle("not json", front=lambda: "", sleep=lambda s: None, clock=lambda: 0.0)
    check("garbage on stdin: nothing written, no exception", not te.EVENTS.exists())
    check("unhandled events and garbage never reach the board",
          len(te.AGENT_EVENTS.read_text().splitlines()) == 2)
    link = Path(tmp, "link")
    link.symlink_to(proj)
    te.handle(json.dumps(event("PreToolUse", str(link), tool_name="Bash", tool_input={"command": "ls"})),
              front=lambda: "", sleep=lambda s: None, clock=lambda: 0.0)
    check("the cwd matches through a symlink", len(entries()) == 1, str(entries()))
    e = entries()[0]
    check("an entry carries event, tool, summary, session, ask, held",
          e["event"] == "PreToolUse" and e["tool"] == "Bash" and e["summary"] == "ls"
          and e["session"] == "abc123" and e["ask"] == "" and e["held"] is False, str(e))

    print("the log")
    rotated = te.EVENTS.with_name(te.EVENTS.name + ".1")

    def generation(path: Path) -> list[int]:
        return [json.loads(l)["i"] for l in path.read_text().splitlines() if l.strip()]

    te.EVENTS.unlink()
    te.EVENTS_MAX_BYTES = 10_000
    te.append({"event": "PreToolUse", "i": 0})
    first = te.EVENTS.read_bytes()
    te.append({"event": "PreToolUse", "i": 1})
    check("append only ever adds bytes", te.EVENTS.read_bytes().startswith(first))
    check("both entries are there", generation(te.EVENTS) == [0, 1], str(generation(te.EVENTS)))
    te.EVENTS_MAX_BYTES = 1
    te.append({"event": "PreToolUse", "i": 2})
    check("past the cap the file is rotated away", not te.EVENTS.exists())
    check(".1 holds everything up to the rotation", generation(rotated) == [0, 1, 2], str(generation(rotated)))
    te.EVENTS_MAX_BYTES = 10_000
    te.append({"event": "PreToolUse", "i": 3})
    check("the next append starts a fresh file", generation(te.EVENTS) == [3], str(generation(te.EVENTS)))
    te.EVENTS_MAX_BYTES = 1
    te.append({"event": "PreToolUse", "i": 4})
    check("a second rotation replaces the older .1", generation(rotated) == [3, 4], str(generation(rotated)))
    te.EVENTS_MAX_BYTES = 400_000
    rotated.unlink()

    print("the ask protocol")
    clock = Clock()
    ask = event("PermissionRequest", proj, tool_name="Bash", tool_input={"command": "rm -rf build"})
    out = te.hold(ask, front=lambda: "Terminal", sleep=clock.sleep, clock=clock)
    check("terminal in front: no hold, no output", out == "")
    check("terminal in front: the entry says held false", entries()[-1]["held"] is False and entries()[-1]["ask"] == "")
    check("terminal in front: no ask file", not any(te.ASKS.glob("*.json")))
    out = te.hold(ask, front=lambda: "", sleep=clock.sleep, clock=clock)
    check("front check failed: treated as in front", out == "" and entries()[-1]["held"] is False)

    def answer_after(text: str, delay: float):
        started = clock.now
        def sleep(s: float) -> None:
            clock.now += s
            if clock.now - started >= delay:
                for f in te.ASKS.glob("*.json"):
                    Path(str(f)[:-5] + ".answer").write_text(text)
        return sleep

    out = te.hold(ask, front=lambda: "Google Chrome", sleep=answer_after("allow", 2.0), clock=clock)
    check("an allow answer becomes the allow decision",
          json.loads(out)["hookSpecificOutput"]["decision"]["behavior"] == "allow", out)
    check("the ask entry was held, with an id", entries()[-2]["held"] is True and entries()[-2]["ask"] != "")
    check("the answer is recorded", entries()[-1]["event"] == "ask_answered" and entries()[-1]["summary"] == "allow")
    check("the ask files are gone", not list(te.ASKS.iterdir()))

    out = te.hold(ask, front=lambda: "Google Chrome", sleep=answer_after("deny stop", 1.0), clock=clock)
    d = json.loads(out)["hookSpecificOutput"]["decision"]
    check("deny stop is deny with interrupt", d["behavior"] == "deny" and d.get("interrupt") is True
          and d["message"] == "denied by voice", out)

    out = te.hold(ask, front=lambda: "Google Chrome", sleep=clock.sleep, clock=clock)
    check("no answer in time: no output", out == "")
    check("no answer in time: ask_expired recorded", entries()[-1]["event"] == "ask_expired")
    check("no answer in time: the ask file is gone", not list(te.ASKS.iterdir()))

    te.ASKS.mkdir(exist_ok=True)
    Path(te.ASKS, "held.json").write_text(json.dumps({"t": time.time()}))
    out = te.hold(ask, front=lambda: "Google Chrome", sleep=clock.sleep, clock=clock)
    check("a second ask while one is held falls through", out == "" and entries()[-1]["held"] is False)
    Path(te.ASKS, "held.json").unlink()

    print("stale and torn asks")
    # A hook killed at its timeout, or parked across a lid close, leaves its
    # ask file behind. That file used to disable the ask protocol for good.
    stale = Path(te.ASKS, "stale.json")
    stale.write_text(json.dumps({"t": time.time() - (te.ASK_WAIT_S + te.HOOK_TIMEOUT_S + 1)}))
    err = io.StringIO()
    with contextlib.redirect_stderr(err):
        out = te.hold(ask, front=lambda: "Google Chrome", sleep=answer_after("allow", 1.0), clock=clock)
    check("a stale ask does not block the next hold",
          json.loads(out)["hookSpecificOutput"]["decision"]["behavior"] == "allow", out)
    check("the stale ask file is cleared", not stale.exists())
    check("clearing it is said on stderr", "stale ask" in err.getvalue(), err.getvalue())
    Path(te.ASKS, "no-t.json").write_text("{}")
    with contextlib.redirect_stderr(io.StringIO()):
        out = te.hold(ask, front=lambda: "Google Chrome", sleep=answer_after("allow", 1.0), clock=clock)
    check("an ask file with no readable time is stale too",
          out != "" and not Path(te.ASKS, "no-t.json").exists(), out)

    def torn_answer(delay: float):
        started = clock.now
        def sleep(s: float) -> None:
            clock.now += s
            if clock.now - started >= delay:
                for f in te.ASKS.glob("*.json"):
                    Path(str(f)[:-5] + ".answer").write_bytes(b"\xff\xfe allo")
        return sleep

    err = io.StringIO()
    with contextlib.redirect_stderr(err):
        out = te.hold(ask, front=lambda: "Google Chrome", sleep=torn_answer(1.0), clock=clock)
    check("a non-utf-8 answer expires the ask instead of aborting the hold",
          out == "" and entries()[-1]["event"] == "ask_expired", out)
    check("a torn answer still removes the ask file", not list(te.ASKS.glob("*.json")))

    err = io.StringIO()
    with contextlib.redirect_stderr(err):
        out = te.hold(ask, front=lambda: "Google Chrome", sleep=answer_after("maybe", 1.0), clock=clock)
    check("an unrecognised answer word expires the ask", out == "")
    check("an unrecognised answer word is said on stderr",
          "not allow or deny" in err.getvalue(), err.getvalue())
    for leftover in te.ASKS.iterdir():
        leftover.unlink()

    check("an unknown answer word is no decision", te.decision("maybe") is None)
    check("the hook never allows on its own", te.decision("") is None)

    print("handle end to end")
    out = te.handle(json.dumps(event("Stop", proj, last_assistant_message="All green.")),
                    front=lambda: "", sleep=clock.sleep, clock=clock)
    check("stop is appended with its sentence", out == "" and entries()[-1]["event"] == "Stop"
          and entries()[-1]["summary"] == "All green.")

    print(f"\n{PASSED} passed, {FAILED} failed")
    return 1 if FAILED else 0


if __name__ == "__main__":
    sys.exit(main())

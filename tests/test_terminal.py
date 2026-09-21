#!/usr/bin/env python3
"""mac/lib/terminal.py, without a Terminal.

Everything that opens a window is in tests/live/terminal.sh. What is here is
the tab parser, the choice rule, and the one-paragraph collapse, because a
wrong tab choice pastes a prompt into someone's live shell.

    python3 tests/test_terminal.py
"""
import importlib.util
import json as _json
import os
import os as _os
import pathlib
import sys
import tempfile
import tempfile as _tempfile
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


def fake_osascript(script, *args):
    calls.append(("osascript", script.strip().splitlines()[0], args))
    if "processes of t" in script:
        return RAW
    if "do script" in script:
        return "/dev/ttys004"
    return "ok"


def fake_run(argv):
    calls.append(("run", tuple(argv)))
    class R:
        returncode = 0
        stdout = ""
        stderr = ""
    return R()


calls: list = []


def main() -> int:
    tabs = t.parse_tabs(RAW)
    check("three tabs parsed, blank line ignored", len(tabs) == 3, str(tabs))
    check("tty is the first field", tabs[0]["tty"] == "/dev/ttys001")
    check("selected parses as bool", tabs[0]["selected"] is True and tabs[1]["selected"] is False)
    check("front parses as bool", tabs[2]["front"] is False)
    check("processes split on comma", tabs[1]["processes"] == ["login", "-zsh", "claude"])
    check("empty output is no tabs", t.parse_tabs("") == [])

    check("a tab running claude is a candidate", t.is_candidate(tabs[1]))
    check("a plain shell is not", not t.is_candidate(tabs[0]))
    check("the tabs script never coerces Terminal's tab class to text", "& tab &" not in t.TABS_SCRIPT)
    check(
        "the homebrew claude.exe name is a candidate too",
        t.is_candidate(t.parse_tabs("/dev/ttys009\tfalse\tfalse\tlogin,-zsh,claude.exe\n")[0]),
    )

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

    # ── actions, with osascript and peekaboo replaced ────────────────────────
    t.osascript = fake_osascript
    t.run = fake_run
    t.secure_input_holder = lambda: None
    mem = pathlib.Path(_tempfile.mkdtemp())
    t.MEMORY, t.DRAFT, t.PROJECT = mem, mem / "draft.json", mem / "project.json"

    calls.clear()
    out = t.draft("build a\nsignaler", None)
    check("draft chose the first candidate", out["tty"] == "/dev/ttys002", str(out))
    check("draft collapsed the text", out["chars"] == len("build a signaler"))
    check("draft focused the tab before pasting",
          [c[0] for c in calls] == ["osascript", "osascript", "run"], str(calls))
    check("draft pasted through peekaboo, text as an argument",
          calls[-1][1][:3] == ("peekaboo", "paste", "--text") and calls[-1][1][3] == "build a signaler")
    check("no Return was pressed", not any("key code 36" in str(c) for c in calls))
    saved = _json.loads((mem / "draft.json").read_text())
    check("draft.json holds the tty and text", saved["tty"] == "/dev/ttys002" and saved["text"] == "build a signaler")
    check("project.json got last_sent", "last_sent" in _json.loads((mem / "project.json").read_text()))

    # submit refuses unless the bridge sets CHEWIE_TERMINAL_SUBMIT=1: the gate
    # that turns "the model was told never to submit" from a sentence in a
    # prompt into code that actually stops it.
    _os.environ.pop("CHEWIE_TERMINAL_SUBMIT", None)
    calls.clear()
    try:
        t.submit("/dev/ttys002")
        check("submit without CHEWIE_TERMINAL_SUBMIT refuses", False)
    except SystemExit as e:
        check("submit without the gate exits 3", e.code == 3)
    check("submit without the gate pressed nothing", calls == [], str(calls))
    check("submit without the gate left the draft in place", (mem / "draft.json").exists())

    _os.environ["CHEWIE_TERMINAL_SUBMIT"] = "1"
    calls.clear()
    t.submit("/dev/ttys002")
    check("submit focuses then presses Return",
          any("key code 36" in str(c) for c in calls) and calls[0][0] == "osascript")
    check("submit removes the draft", not (mem / "draft.json").exists())

    t.draft("again", "/dev/ttys003")
    calls.clear()
    t.clear("/dev/ttys003")
    check("clear presses Control-U", any("key code 32" in str(c) and "control down" in str(c) for c in calls))
    check("clear removes the draft", not (mem / "draft.json").exists())

    t.secure_input_holder = lambda: "loginwindow"
    try:
        t.draft("x", None)
        check("draft refuses under Secure Input", False)
    except SystemExit as e:
        check("draft refuses under Secure Input with exit 2", e.code == 2)

    # submit checks Secure Input too, same as draft and clear: the gate above
    # is a separate refusal, so it is set here to isolate this one.
    calls.clear()
    try:
        t.submit("/dev/ttys002")
        check("submit refuses under Secure Input", False)
    except SystemExit as e:
        check("submit refuses under Secure Input with exit 2", e.code == 2)
    check("submit under Secure Input pressed nothing", calls == [], str(calls))
    t.secure_input_holder = lambda: None

    no_tabs = t.parse_tabs("")
    check("choose on no tabs is None", t.choose(no_tabs, None) is None)
    try:
        t.osascript = lambda s, *a: ""
        t.draft("x", None)
        check("draft with no claude tab fails", False)
    except SystemExit as e:
        check("draft with no claude tab exits 1", e.code == 1)
    t.osascript = fake_osascript

    # ensure: an existing candidate is returned without opening anything
    calls.clear()
    got = t.ensure(None, timeout=0.1)
    check("ensure returns the existing candidate", got["tty"] == "/dev/ttys002")
    check("ensure did not run do script", not any("do script" in str(c) for c in calls))
    check("project.json remembers the tty", _json.loads((mem / "project.json").read_text())["tty"] == "/dev/ttys002")

    # ensure --fresh never reuses a tab it did not open. On 2026-09-20 the
    # live check let ensure choose, got the front tab (a real session), and
    # submitted its test prompt there.
    calls.clear()
    opened = []
    def fresh_osascript(script, *args):
        calls.append(("osascript", script, args))
        if "do script" in script:
            opened.append("/dev/ttys004\tfalse\ttrue\tlogin,-zsh,claude\n")
            return "/dev/ttys004"
        if "processes of t" in script:
            return RAW + "".join(opened)
        return "ok"
    t.osascript = fresh_osascript
    got = t.ensure(str(mem / "fresh"), timeout=1, fresh=True)
    check("ensure --fresh opens a new tab even with a candidate present", got["tty"] == "/dev/ttys004" and got["opened"], str(got))
    check("ensure --fresh ran do script", any("do script" in str(c) for c in calls))
    t.osascript = fake_osascript

    # answer / interrupt / focus: focus first, then one key. The key lines
    # are single-line scripts, so their first line is the whole script.
    t.osascript = fake_osascript

    # `answer yes` presses the same Return `submit` does, so it carries the
    # same gate. Every way hud-listen's terminal state can be wrong turns an
    # ungated Return into a prompt nobody read.
    _os.environ.pop("CHEWIE_TERMINAL_ANSWER", None)
    calls.clear()
    try:
        t.answer("yes", "/dev/ttys002")
        check("answer yes without CHEWIE_TERMINAL_ANSWER refuses", False)
    except SystemExit as e:
        check("answer yes without the gate exits 3", e.code == 3)
    check("answer yes without the gate pressed nothing", calls == [], str(calls))
    calls.clear()
    t.answer("no", "/dev/ttys002")
    check("answer no needs no gate: Escape costs a tool call at worst",
          any("key code 53" in str(c) for c in calls), str(calls))
    calls.clear()
    t.interrupt("/dev/ttys002")
    check("interrupt needs no gate either", any("key code 53" in str(c) for c in calls), str(calls))

    _os.environ["CHEWIE_TERMINAL_ANSWER"] = "1"
    calls.clear()
    got = t.answer("yes", "/dev/ttys002")
    keys = [c[1] for c in calls if c[0] == "osascript" and "key code" in c[1]]
    check("answer yes presses Return", keys == ['tell application "System Events" to key code 36'], str(keys))
    focus_idx = next(i for i, c in enumerate(calls) if c[2] == ("/dev/ttys002",))
    key_idx = next(i for i, c in enumerate(calls) if "key code" in c[1])
    check("answer focused the tab first", focus_idx < key_idx, str(calls))
    check("answer reports", got == {"tty": "/dev/ttys002", "answer": "yes"}, str(got))
    calls.clear()
    t.answer("no", "/dev/ttys002")
    keys = [c[1] for c in calls if "key code" in c[1]]
    check("answer no presses Escape", keys == ['tell application "System Events" to key code 53'], str(keys))
    calls.clear()
    t.interrupt("/dev/ttys002")
    keys = [c[1] for c in calls if "key code" in c[1]]
    check("interrupt presses Escape", keys == ['tell application "System Events" to key code 53'], str(keys))
    calls.clear()
    got = t.focus_tab("/dev/ttys002")
    check("focus presses nothing", not any("key code" in c[1] for c in calls), str(calls))
    check("focus reports", got == {"tty": "/dev/ttys002", "focused": True}, str(got))
    t.secure_input_holder = lambda: "loginwindow"
    try:
        t.answer("yes", "/dev/ttys002")
        check("answer under Secure Input refuses", False)
    except SystemExit as e:
        check("answer under Secure Input exits 2", e.code == 2)
    _os.environ.pop("CHEWIE_TERMINAL_ANSWER", None)
    try:
        t.interrupt("/dev/ttys002")
        check("interrupt under Secure Input refuses", False)
    except SystemExit as e:
        check("interrupt under Secure Input exits 2", e.code == 2)
    t.secure_input_holder = lambda: None

    # hook: stdin in, stdout out, exit 0 always, nothing else printed. The
    # events module is loaded lazily so this test file's stub-loaded
    # terminal.py does not need mac/lib on sys.path at import.
    import subprocess as _sp
    hookmem = tempfile.mkdtemp()
    proj = tempfile.mkdtemp()
    pathlib.Path(hookmem, "project.json").write_text(_json.dumps({"cwd": proj}))
    env = {**os.environ, "BOB_MEMORY_DIR": hookmem}
    ev = _json.dumps({"hook_event_name": "PreToolUse", "session_id": "s", "cwd": proj,
                      "tool_name": "Bash", "tool_input": {"command": "ls"}})
    r = _sp.run([sys.executable, str(ROOT / "mac" / "lib" / "terminal.py"), "hook"],
                input=ev, capture_output=True, text=True, env=env, timeout=20)
    check("hook exits 0", r.returncode == 0, r.stderr)
    check("hook prints nothing for a plain event", r.stdout == "", repr(r.stdout))
    check("hook wrote the event", "PreToolUse" in pathlib.Path(hookmem, "terminal-events.jsonl").read_text())
    r = _sp.run([sys.executable, str(ROOT / "mac" / "lib" / "terminal.py"), "hook"],
                input="{", capture_output=True, text=True, env=env, timeout=20)
    check("hook survives garbage with exit 0 and no output", r.returncode == 0 and r.stdout == "")

    print(f"\n{PASSED} passed, {FAILED} failed")
    return 1 if FAILED else 0


if __name__ == "__main__":
    sys.exit(main())

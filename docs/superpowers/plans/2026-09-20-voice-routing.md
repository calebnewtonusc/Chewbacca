# Voice routing implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A spoken sentence lands in the terminal, Chrome, or the voice assistant without the person naming the destination, and a terminal-bound sentence becomes a drafted prompt sitting un-submitted in Claude Code's input until the person presses Return or says "send it".

**Architecture:** A pure router (`bin/lib/route.py`) decides the destination from the sentence, the frontmost app, and a small on-disk memory (`bin/lib/voice_memory.py`, `~/.bob/memory/`). `hud-listen` calls the router before dispatching: browser sentences open Chrome directly, terminal sentences go to the existing voice agent with a drafting instruction, everything else goes to the agent unchanged. A new `chewie terminal` verb (`mac/lib/terminal.py`) finds the Terminal tab running `claude`, pastes a draft into it, and, only on a person's word, presses Return.

**Tech Stack:** Python 3 stdlib (no third-party imports; the dev Macs have no pytest), bash for `chewie`, AppleScript through `osascript` for Terminal.app, `peekaboo paste` for the clipboard paste, `claude -p --model haiku` for the classifier. Tests are plain scripts run by `tests/run.sh`.

**Spec:** `docs/superpowers/specs/2026-09-20-voice-routing-design.md`

## Global Constraints

- No em dashes and no emojis anywhere: code, comments, docs, commit messages.
- Commit messages are lowercase `feat:` / `fix:` / `test:` / `docs:` lines with no Co-Authored-By. Stage files by name, never `git add -A`.
- Python is stdlib only. Tests are plain scripts with a `check()` helper, runnable as `python3 tests/test_x.py`, exit code 1 on any failure, and registered in the `hud` group of `tests/run.sh`.
- Every constant that could plausibly be a different number carries a comment saying what set it, or `guessed, never measured`.
- `chewie terminal submit` is the only code path that presses Return in the terminal, and only `hud-listen`'s draft-word handler ever calls it. The voice agent's prompt says never to run it.
- Nothing in `~/.bob/memory/` leaves the machine. The classifier prompt carries the last five routed sentences, never the file.
- Memory locations honour `BOB_MEMORY_DIR` so tests never touch `~/.bob`.
- The person works on the same Mac these tests run on. Anything that opens a window or takes focus is opt-in (`tests/live/`) and is never run by `tests/run.sh`.
- Work happens on branch `feat/voice-routing` in the worktree at `/private/tmp/claude-501/-Users-gavinmunroe1/cab774ab-78b2-46aa-ba13-79542c05f503/scratchpad/wt-route`. Never touch `feat/hud-presence-field`.

## File structure

| File | Responsibility |
| --- | --- |
| `mac/lib/terminal.py` (new) | Terminal.app: list tabs, choose the `claude` tab, ensure one exists, draft (paste, no Return), submit (Return), clear (Control-U). Owns `draft.json` and the tty/cwd half of `project.json`. |
| `mac/bin/chewie` (modify) | `terminal` verb dispatching to `terminal.py`, usage line. |
| `bin/lib/voice_memory.py` (new) | `transcript.jsonl` append and rotation, `project.json` read and merge, `draft.json` read, the "what is warm" question. Shared path logic with `terminal.py` by convention, not import. |
| `bin/lib/route.py` (new) | `route()`, `draft_word()`, `browser_url()`, `seen_app()`, the haiku classifier and the project summariser. Pure except the two `claude -p` callers, which are injectable. |
| `bin/hud-listen` (modify) | Import the two modules; handle draft words in `ask()`; decide in `_run()`; open Chrome; add the terminal block and project line in `prompt_for()`; write the transcript; drive the pill. |
| `bin/hud-agent.md` (modify) | The drafting rules. |
| `tests/test_terminal.py`, `tests/test_memory.py`, `tests/test_route.py` (new) | Unit tables. |
| `tests/test_hud_listen.py` (modify) | Routing in the prompt, the browser path, the draft words, end to end against the fake display. |
| `tests/live/terminal.sh` (new) | The hand check: paste, Return, Control-U on a throwaway tab. |
| `tests/run.sh` (modify) | Register the three new test scripts. |
| `docs/VOICE-DESIGN.md` (modify) | The routing section. |

---

### Task 1: Terminal tab discovery and choice, pure

**Files:**
- Create: `mac/lib/terminal.py`
- Test: `tests/test_terminal.py`

**Interfaces:**
- Produces: `parse_tabs(raw: str) -> list[dict]` where each dict is `{"tty": str, "selected": bool, "front": bool, "processes": list[str]}`; `is_candidate(tab: dict) -> bool`; `choose(tabs: list[dict], remembered: str | None) -> dict | None`; `collapse(text: str) -> str`.

- [ ] **Step 1: Write the failing tests**

```python
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `python3 tests/test_terminal.py`
Expected: traceback, `FileNotFoundError` or `No such file` for `mac/lib/terminal.py`.

- [ ] **Step 3: Write the pure half of `mac/lib/terminal.py`**

```python
#!/usr/bin/env python3
"""Find the Terminal tab running Claude Code, and put a draft in it.

Layer 2, Terminal.app's scripting dictionary, plus one paste. Nothing here
presses Return except `submit`, and `submit` is only ever run because a person
said "send it" or "run it" (bin/hud-listen). A prompt that Chewbacca typed and
Chewbacca also submitted is a prompt nobody read.

    chewie terminal tabs                    every tab: tty, selected, front, processes
    chewie terminal ensure [--cwd DIR]      a tab running claude, opened if needed
    chewie terminal draft "<text>" [--tty]  paste into the claude tab, no Return
    chewie terminal submit [--tty]          press Return in that tab
    chewie terminal clear [--tty]           Control-U in that tab

Memory (`~/.bob/memory/`, or BOB_MEMORY_DIR): `draft.json` is the outstanding
draft, written by `draft`, removed by `submit` and `clear`. `project.json`
gets `tty`, `cwd`, `name`, `last_sent`, `updated` from here; `summary` is
written by hud-listen and left alone.
"""
import argparse
import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

MEMORY = Path(os.environ.get("BOB_MEMORY_DIR", str(Path.home() / ".bob" / "memory")))
DRAFT = MEMORY / "draft.json"
PROJECT = MEMORY / "project.json"
SECURE_INPUT = Path(__file__).resolve().parent / "secure-input.sh"

# One line per tab: tty, selected, in the front window, processes joined by
# commas. `if application "Terminal" is running` first, because a bare `tell`
# launches Terminal, and listing tabs must never open a window.
TABS_SCRIPT = '''
set AppleScript's text item delimiters to ","
set out to ""
if application "Terminal" is running then
  tell application "Terminal"
    set wi to 0
    repeat with w in windows
      set wi to wi + 1
      repeat with t in tabs of w
        set out to out & (tty of t) & tab & (selected of t) & tab & (wi = 1) & tab & ((processes of t) as text) & linefeed
      end repeat
    end repeat
  end tell
end if
return out
'''


def parse_tabs(raw: str) -> list[dict]:
    tabs = []
    for line in raw.splitlines():
        if not line.strip():
            continue
        parts = line.split("\t")
        if len(parts) < 4:
            continue
        tty, selected, front, procs = parts[0], parts[1], parts[2], parts[3]
        tabs.append({
            "tty": tty.strip(),
            "selected": selected.strip() == "true",
            "front": front.strip() == "true",
            "processes": [p for p in procs.split(",") if p],
        })
    return tabs


def is_candidate(tab: dict) -> bool:
    return "claude" in tab["processes"]


def choose(tabs: list[dict], remembered: str | None) -> dict | None:
    """The remembered tty, else the selected tab of the front window, else the
    first tab running claude. In that order because the remembered one is the
    project the person was talking about, and the front-selected one is the
    one they are looking at."""
    candidates = [t for t in tabs if is_candidate(t)]
    if not candidates:
        return None
    for t in candidates:
        if remembered and t["tty"] == remembered:
            return t
    for t in candidates:
        if t["front"] and t["selected"]:
            return t
    return candidates[0]


def collapse(text: str) -> str:
    """One paragraph. Claude Code's input treats a pasted newline as part of
    the text, but a draft the person has to read in a one-line box reads
    better as prose than as a stack."""
    return re.sub(r"\s+", " ", text).strip()
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `python3 tests/test_terminal.py`
Expected: every line `pass`, `18 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add mac/lib/terminal.py tests/test_terminal.py
git commit -m "feat: parse and choose the terminal tab running claude"
```

---

### Task 2: Terminal actions and the `chewie terminal` verb

**Files:**
- Modify: `mac/lib/terminal.py` (append)
- Modify: `mac/bin/chewie` (usage, one `cmd_` function, one `case` line)
- Modify: `tests/test_terminal.py` (append)
- Create: `tests/live/terminal.sh`

**Interfaces:**
- Consumes: `parse_tabs`, `choose`, `collapse` from Task 1.
- Produces: CLI `chewie terminal {tabs,ensure,draft,submit,clear}`; `draft` prints `{"tty":..., "chars":...}` and writes `draft.json` as `{"tty": str, "text": str, "t": iso}`; `ensure` prints `{"tty":..., "cwd":...}` and merges `{"tty","cwd","name","updated"}` into `project.json`; `submit`/`clear` remove `draft.json`; `draft` also sets `last_sent` in `project.json`. Exit codes: 0 ok, 1 not found or no tab, 2 Secure Input on.
- Module-level `osascript(script, *args) -> str` and `run(argv) -> subprocess.CompletedProcess` are the only subprocess callers, so tests replace them.

- [ ] **Step 1: Append the failing tests**

Append to `tests/test_terminal.py`, above the final `print`:

```python
# ── actions, with osascript and peekaboo replaced ────────────────────────────
import json as _json
import os as _os
import tempfile as _tempfile

calls: list = []


def fake_osascript(script, *args):
    calls.append(("osascript", script.strip().splitlines()[0][:40], args))
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `python3 tests/test_terminal.py`
Expected: `AttributeError: module 'terminal' has no attribute 'draft'` (or `osascript`).

- [ ] **Step 3: Append the actions to `mac/lib/terminal.py`**

```python
# Everything below talks to the machine. `osascript` and `run` are module
# level so tests replace them.

def osascript(script: str, *args: str) -> str:
    result = subprocess.run(
        ["osascript", "-e", script, *args], capture_output=True, text=True, timeout=15
    )
    if result.returncode != 0:
        raise SystemExit(f"terminal: osascript failed: {result.stderr.strip()}")
    return result.stdout


def run(argv: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(argv, capture_output=True, text=True, timeout=15)


def secure_input_holder() -> str | None:
    """The process name holding Secure Input, or None. Synthetic keystrokes
    and pastes are dropped with no error while it is on."""
    try:
        result = subprocess.run([str(SECURE_INPUT)], capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.TimeoutExpired):
        return None
    if result.returncode == 0:
        return None
    for line in result.stdout.splitlines():
        if "held_by" in line:
            return line.split()[-1]
    return "unknown"


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def read_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def merge_json(path: Path, patch: dict) -> dict:
    data = read_json(path)
    data.update(patch)
    MEMORY.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2), encoding="utf-8")
    return data


def tabs() -> list[dict]:
    return parse_tabs(osascript(TABS_SCRIPT))


FOCUS_SCRIPT = '''
on run argv
  set want to item 1 of argv
  tell application "Terminal"
    repeat with w in windows
      repeat with t in tabs of w
        if (tty of t) is want then
          set selected of t to true
          set index of w to 1
          activate
          return "ok"
        end if
      end repeat
    end repeat
  end tell
  return "missing"
end run
'''

# `do script` with no target opens a new window and returns its tab. Return
# is wanted here: this is a shell command, not a prompt.
OPEN_SCRIPT = '''
on run argv
  tell application "Terminal"
    activate
    set t to do script ("cd " & quoted form of (item 1 of argv) & " && claude")
    return tty of t
  end tell
end run
'''

KEY_RETURN = 'tell application "System Events" to key code 36'
KEY_CONTROL_U = 'tell application "System Events" to key code 32 using control down'


def pick(tty: str | None) -> dict:
    remembered = tty or read_json(PROJECT).get("tty")
    tab = choose(tabs(), remembered)
    if tab is None:
        raise SystemExit("terminal: no Terminal tab is running claude (chewie terminal ensure)")
    return tab


def focus(tty: str) -> None:
    if osascript(FOCUS_SCRIPT, tty).strip() != "ok":
        raise SystemExit(f"terminal: tab {tty} is gone")


def cwd_of(tty: str) -> str:
    """The working directory of the shell on a tty, through lsof on its
    first process. Empty if it cannot be read."""
    ps = run(["ps", "-t", tty.replace("/dev/", ""), "-o", "pid=", "-o", "comm="])
    for line in ps.stdout.splitlines():
        parts = line.split(None, 1)
        if len(parts) == 2 and parts[1].strip().endswith("claude"):
            lsof = run(["lsof", "-a", "-p", parts[0], "-d", "cwd", "-Fn"])
            for entry in lsof.stdout.splitlines():
                if entry.startswith("n/"):
                    return entry[1:]
    return ""


def remember(tab: dict) -> dict:
    cwd = cwd_of(tab["tty"])
    patch = {"tty": tab["tty"], "updated": now_iso()}
    if cwd:
        patch["cwd"] = cwd
        patch["name"] = Path(cwd).name
    return merge_json(PROJECT, patch)


def ensure(cwd: str | None, timeout: float = 10.0) -> dict:
    """A tab running claude, opened if there is none.

    Ten seconds: claude on this machine shows its prompt in about two, and
    a cold start with a big project has been seen take five. Guessed above
    that.
    """
    tab = choose(tabs(), read_json(PROJECT).get("tty"))
    if tab is not None:
        project = remember(tab)
        return {"tty": tab["tty"], "cwd": project.get("cwd", ""), "opened": False}
    folder = cwd or read_json(PROJECT).get("cwd")
    if not folder:
        raise SystemExit("terminal: no claude tab and no known folder; pass --cwd")
    folder = os.path.expanduser(folder)
    os.makedirs(folder, exist_ok=True)
    tty = osascript(OPEN_SCRIPT, folder).strip()
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        for t in tabs():
            if t["tty"] == tty and is_candidate(t):
                project = merge_json(PROJECT, {
                    "tty": tty, "cwd": folder, "name": Path(folder).name, "updated": now_iso(),
                })
                return {"tty": tty, "cwd": project["cwd"], "opened": True}
        time.sleep(0.5)
    raise SystemExit(f"terminal: opened {tty} but claude did not start within {timeout:.0f}s")


def draft(text: str, tty: str | None) -> dict:
    holder = secure_input_holder()
    if holder:
        print(f"terminal: Secure Input is on, held by {holder}; the paste would be dropped", file=sys.stderr)
        raise SystemExit(2)
    tab = pick(tty)
    body = collapse(text)
    focus(tab["tty"])
    result = run(["peekaboo", "paste", "--text", body])
    if result.returncode != 0:
        raise SystemExit(f"terminal: paste failed: {result.stderr.strip() or result.stdout.strip()}")
    MEMORY.mkdir(parents=True, exist_ok=True)
    DRAFT.write_text(json.dumps({"tty": tab["tty"], "text": body, "t": now_iso()}), encoding="utf-8")
    merge_json(PROJECT, {"tty": tab["tty"], "last_sent": now_iso(), "updated": now_iso()})
    return {"tty": tab["tty"], "chars": len(body)}


def _forget_draft() -> None:
    try:
        DRAFT.unlink()
    except OSError:
        pass


def submit(tty: str | None) -> dict:
    tab = pick(tty)
    focus(tab["tty"])
    osascript(KEY_RETURN)
    _forget_draft()
    return {"tty": tab["tty"], "submitted": True}


def clear(tty: str | None) -> dict:
    holder = secure_input_holder()
    if holder:
        print(f"terminal: Secure Input is on, held by {holder}", file=sys.stderr)
        raise SystemExit(2)
    tab = pick(tty)
    focus(tab["tty"])
    osascript(KEY_CONTROL_U)
    _forget_draft()
    return {"tty": tab["tty"], "cleared": True}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="chewie terminal")
    parser.add_argument("--json", action="store_true")
    sub = parser.add_subparsers(dest="verb", required=True)
    sub.add_parser("tabs")
    p = sub.add_parser("ensure"); p.add_argument("--cwd")
    p = sub.add_parser("draft"); p.add_argument("text"); p.add_argument("--tty")
    p = sub.add_parser("submit"); p.add_argument("--tty")
    p = sub.add_parser("clear"); p.add_argument("--tty")
    args = parser.parse_args(argv)

    if args.verb == "tabs":
        out = tabs()
    elif args.verb == "ensure":
        out = ensure(args.cwd)
    elif args.verb == "draft":
        out = draft(args.text, args.tty)
    elif args.verb == "submit":
        out = submit(args.tty)
    else:
        out = clear(args.tty)

    if args.json or args.verb == "tabs":
        print(json.dumps(out, indent=2))
    elif args.verb == "draft":
        print(f"draft in {out['tty']}, {out['chars']} chars, not submitted")
    elif args.verb == "ensure":
        print(f"{out['tty']} {out['cwd']}{' (opened)' if out['opened'] else ''}")
    else:
        print(f"{args.verb} {out['tty']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 4: Run the tests**

Run: `python3 tests/test_terminal.py`
Expected: all pass. If `draft focused the tab before pasting` fails, check that `pick()` calls `tabs()` once (one osascript), then `focus()` (second osascript), then `run` for the paste.

- [ ] **Step 5: Wire `chewie terminal`**

In `mac/bin/chewie`, add to the `usage()` heredoc after the `texts` line:

```
  chewie terminal tabs|ensure|draft|submit|clear   the Claude Code tab in Terminal
```

Add next to `cmd_texts`:

```bash
# ---------- terminal (layer 2) ----------
cmd_terminal() {
  local py="$CHEWIE_ROOT/lib/terminal.py"
  [ -f "$py" ] || die "missing $py"
  if [ "$DRY" = 1 ]; then echo "[dry-run] python3 $py $*"; return 0; fi
  python3 "$py" ${JSON:+--json} "$@"
}
```

The dispatch `case` at the bottom of the script gets one more line, placed before the `""|-h|--help|help)` entry so help stays last:

```bash
  terminal) shift; cmd_terminal "$@" ;;
```

- [ ] **Step 6: Check the verb dispatches**

Run: `bash mac/bin/chewie terminal --dry-run tabs`
Expected: `[dry-run] python3 .../mac/lib/terminal.py tabs`

Run: `bash mac/bin/chewie --help | grep terminal`
Expected: the usage line.

Run: `bash -n mac/bin/chewie && shellcheck -S error mac/bin/chewie`
Expected: no output.

- [ ] **Step 7: Write the live check**

`tests/live/terminal.sh`:

```bash
#!/usr/bin/env bash
# Live: a draft lands in Claude Code's input and does not submit; Return
# submits it; Control-U clears it. Opens a Terminal window and takes focus for
# about twenty seconds, so this is never run by tests/run.sh. Run it when the
# person says go, never on a live claude session: it opens its own in a temp
# folder.
source "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
need claude "npm i -g @anthropic-ai/claude-code"
need peekaboo "run install.sh"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CH="$REPO/mac/bin/chewie"
export BOB_MEMORY_DIR="$(mktemp -d)"
DIR="$(mktemp -d)"

TTY="$(bash "$CH" terminal ensure --cwd "$DIR" --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["tty"])')"
ok "ensure opened a claude tab" test -n "$TTY"
sleep 2
ok "draft pastes without submitting" bash "$CH" terminal draft "reply with exactly one word: chewbacca" --tty "$TTY"
echo "  LOOK: the text should sit in the input, unsent. 5 s."
sleep 5
ok "clear empties the input" bash "$CH" terminal clear --tty "$TTY"
sleep 1
ok "draft again" bash "$CH" terminal draft "reply with exactly one word: chewbacca" --tty "$TTY"
sleep 1
ok "submit presses Return" bash "$CH" terminal submit --tty "$TTY"
echo "  LOOK: claude should now answer 'chewbacca'. Close that window when done."
```

Run: `bash -n tests/live/terminal.sh`
Expected: no output. Do not run the script itself here: it opens a window on the person's Mac. Say in the task report that it is ready and needs their go.

- [ ] **Step 8: Register the unit test and commit**

In `tests/run.sh`, in the `if group "hud"; then` block, after the `test_hud_listen.py` line:

```bash
  check  "the terminal tab chooser never picks a plain shell" python3 "$ROOT/tests/test_terminal.py"
```

Run: `tests/run.sh hud`
Expected: the new line passes.

```bash
git add mac/lib/terminal.py mac/bin/chewie tests/test_terminal.py tests/live/terminal.sh tests/run.sh
git commit -m "feat: chewie terminal drafts into the claude tab and submits only on request"
```

---

### Task 3: Voice memory

**Files:**
- Create: `bin/lib/voice_memory.py`
- Test: `tests/test_memory.py`

**Interfaces:**
- Produces: `MEMORY: Path`; `append(entry: dict) -> None` (transcript, rotates at `CAP`); `recent(n: int, dest: str | None = None) -> list[dict]` (newest last); `last() -> dict | None`; `warm(now: float, window: float = WARM_S) -> str | None` (dest of the last routed line if within the window, using `entry["t"]` as an ISO timestamp); `project() -> dict`; `update_project(patch: dict) -> dict`; `draft(now: float, ttl: float = DRAFT_TTL_S) -> dict | None` (contents of `draft.json` if young enough); `terminal_count() -> int`.
- Entry shape (spec): `{"t": iso, "via": "voice|typed", "text", "dest", "confidence", "reason", "reply", "project", "draft", "submitted"}`.

- [ ] **Step 1: Write the failing tests**

```python
#!/usr/bin/env python3
"""~/.bob/memory, against a temp dir.

    python3 tests/test_memory.py
"""
import importlib.util
import json
import os
import pathlib
import sys
import tempfile
import time
from datetime import datetime, timedelta, timezone
from importlib.machinery import SourceFileLoader

sys.dont_write_bytecode = True
mem = pathlib.Path(tempfile.mkdtemp())
os.environ["BOB_MEMORY_DIR"] = str(mem)
ROOT = pathlib.Path(__file__).resolve().parent.parent
_src = ROOT / "bin" / "lib" / "voice_memory.py"
spec = importlib.util.spec_from_loader("voice_memory", SourceFileLoader("voice_memory", str(_src)))
vm = importlib.util.module_from_spec(spec)
spec.loader.exec_module(vm)

PASSED = FAILED = 0


def check(name, cond, detail=""):
    global PASSED, FAILED
    if cond:
        PASSED += 1
        print(f"  pass  {name}")
    else:
        FAILED += 1
        print(f"  FAIL  {name}  {detail}")


def iso(seconds_ago=0):
    return (datetime.now(timezone.utc) - timedelta(seconds=seconds_ago)).isoformat(timespec="seconds")


check("memory dir is the env override", vm.MEMORY == mem)
check("empty memory has no last", vm.last() is None)
check("empty memory has no warm dest", vm.warm(time.time()) is None)
check("empty project is a dict", vm.project() == {})

vm.append({"t": iso(700), "via": "voice", "text": "look up rust traits", "dest": "browser"})
vm.append({"t": iso(30), "via": "voice", "text": "add tests", "dest": "terminal"})
check("last is the newest line", vm.last()["text"] == "add tests")
check("recent returns newest last", [e["text"] for e in vm.recent(5)] == ["look up rust traits", "add tests"])
check("recent filters by dest", [e["text"] for e in vm.recent(5, "browser")] == ["look up rust traits"])
check("terminal is warm 30 s later", vm.warm(time.time()) == "terminal")
check("nothing is warm 11 minutes later", vm.warm(time.time() + 660) is None)
check("terminal_count counts terminal lines", vm.terminal_count() == 1)

check("update_project merges", vm.update_project({"tty": "/dev/ttys002"})["tty"] == "/dev/ttys002")
check("a second patch keeps the first", vm.update_project({"summary": "a signaler"})["tty"] == "/dev/ttys002")
check("project reads back", vm.project()["summary"] == "a signaler")

check("no draft file is None", vm.draft(time.time()) is None)
(mem / "draft.json").write_text(json.dumps({"tty": "/dev/ttys002", "text": "hi", "t": iso(10)}))
check("a young draft is returned", vm.draft(time.time())["text"] == "hi")
check("an old draft is None", vm.draft(time.time() + 400) is None)
(mem / "draft.json").write_text("not json")
check("a corrupt draft is None", vm.draft(time.time()) is None)

vm.CAP = 5
for i in range(8):
    vm.append({"t": iso(), "via": "voice", "text": f"line {i}", "dest": "assistant"})
lines = (mem / "transcript.jsonl").read_text().splitlines()
check("rotation keeps the newest CAP lines", len(lines) == 5 and json.loads(lines[-1])["text"] == "line 7", str(lines))

print(f"\n{PASSED} passed, {FAILED} failed")
sys.exit(1 if FAILED else 0)
```

- [ ] **Step 2: Run to verify it fails**

Run: `python3 tests/test_memory.py`
Expected: `FileNotFoundError` for `bin/lib/voice_memory.py`.

- [ ] **Step 3: Write `bin/lib/voice_memory.py`**

```python
"""What the voice remembers between chat windows.

Two files under ~/.bob/memory (BOB_MEMORY_DIR in tests), plus one it only
reads. `transcript.jsonl` is every routed utterance; `project.json` is the
terminal project; `draft.json` is written by `chewie terminal draft` and says
whether a prompt is sitting unsent in Claude Code.

Read on every turn, so everything here is a few lines of file. Nothing leaves
the machine.
"""
from __future__ import annotations

import json
import os
from datetime import datetime, timezone
from pathlib import Path

MEMORY = Path(os.environ.get("BOB_MEMORY_DIR", str(Path.home() / ".bob" / "memory")))
TRANSCRIPT = MEMORY / "transcript.jsonl"
PROJECT = MEMORY / "project.json"
DRAFT = MEMORY / "draft.json"

# 5,000 lines is a few weeks of talking at the rate the listen log shows
# (under two hundred turns a day). Guessed, never measured against disk or
# read time.
CAP = 5000
# Warm: a destination the last sentence went to under ten minutes ago. Guessed.
# The failure to watch for is a terminal sentence sent to Chrome after a long
# read; lower it if that happens.
WARM_S = 600.0
# A draft older than this is no longer "outstanding" and "send" is a normal
# word again. Guessed.
DRAFT_TTL_S = 300.0


def _epoch(iso: str) -> float:
    try:
        return datetime.fromisoformat(iso).timestamp()
    except (TypeError, ValueError):
        return 0.0


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def _lines() -> list[str]:
    try:
        return TRANSCRIPT.read_text(encoding="utf-8").splitlines()
    except OSError:
        return []


def append(entry: dict) -> None:
    MEMORY.mkdir(parents=True, exist_ok=True)
    lines = _lines()
    lines.append(json.dumps(entry, ensure_ascii=False))
    if len(lines) > CAP:
        lines = lines[-CAP:]
    TRANSCRIPT.write_text("\n".join(lines) + "\n", encoding="utf-8")


def recent(n: int, dest: str | None = None) -> list[dict]:
    out = []
    for line in reversed(_lines()):
        try:
            entry = json.loads(line)
        except ValueError:
            continue
        if dest is None or entry.get("dest") == dest:
            out.append(entry)
        if len(out) == n:
            break
    return list(reversed(out))


def last() -> dict | None:
    got = recent(1)
    return got[0] if got else None


def warm(now: float, window: float = WARM_S) -> str | None:
    entry = last()
    if entry and now - _epoch(entry.get("t", "")) < window:
        return entry.get("dest")
    return None


def terminal_count() -> int:
    return sum(1 for e in recent(CAP, "terminal"))


def _read(path: Path) -> dict:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def project() -> dict:
    return _read(PROJECT)


def update_project(patch: dict) -> dict:
    data = project()
    data.update(patch)
    data["updated"] = now_iso()
    MEMORY.mkdir(parents=True, exist_ok=True)
    PROJECT.write_text(json.dumps(data, indent=2), encoding="utf-8")
    return data


def draft(now: float, ttl: float = DRAFT_TTL_S) -> dict | None:
    data = _read(DRAFT)
    if data and now - _epoch(data.get("t", "")) < ttl:
        return data
    return None
```

- [ ] **Step 4: Run the tests**

Run: `python3 tests/test_memory.py`
Expected: `17 passed, 0 failed`.

- [ ] **Step 5: Register and commit**

In `tests/run.sh` hud group, after the terminal line:

```bash
  check  "voice memory rotates and reads back" python3 "$ROOT/tests/test_memory.py"
```

```bash
git add bin/lib/voice_memory.py tests/test_memory.py tests/run.sh
git commit -m "feat: voice memory that survives the chat window"
```

---

### Task 4: The router

**Files:**
- Create: `bin/lib/route.py`
- Test: `tests/test_route.py`

**Interfaces:**
- Consumes: nothing from other modules (pure; takes a memory dict, not the module).
- Produces:
  - `Decision` dataclass: `dest: str`, `confidence: float`, `reason: str`, `reroute: str | None = None`.
  - `route(said: str, context: dict, memory: dict, names: Sequence[str] = (), now: float | None = None, classify: Callable[[str, dict], str | None] | None = None) -> Decision`. `context = {"app": str, "claude_tab": bool}`. `memory = {"last": {"dest","t","text"} | None, "warm": str | None, "project": dict, "recent": list[dict]}`.
  - `draft_word(said: str) -> str | None`: `"submit"`, `"clear"`, `"reroute"` or `None`.
  - `browser_url(said: str) -> tuple[str, str]`: `(url, label)`.
  - `seen_app(seen: str) -> str`: the app from `hud-context`'s receipt line (`App · Window · N chars selected`).
  - `classify_with_haiku(said: str, memory: dict) -> str | None` (subprocess, 3 s timeout, `HUD_CLASSIFY_CMD` override, `off` disables).
  - `summarize(sentences: list[str]) -> str | None` (subprocess, `HUD_CLASSIFY_CMD` too).

- [ ] **Step 1: Write the failing tests**

```python
#!/usr/bin/env python3
"""The routing table. Every rule in the spec is a row here.

    python3 tests/test_route.py
"""
import importlib.util
import pathlib
import sys
import time
from datetime import datetime, timedelta, timezone
from importlib.machinery import SourceFileLoader

sys.dont_write_bytecode = True
ROOT = pathlib.Path(__file__).resolve().parent.parent
_src = ROOT / "bin" / "lib" / "route.py"
spec = importlib.util.spec_from_loader("route", SourceFileLoader("route", str(_src)))
r = importlib.util.module_from_spec(spec)
spec.loader.exec_module(r)

PASSED = FAILED = 0


def check(name, cond, detail=""):
    global PASSED, FAILED
    if cond:
        PASSED += 1
        print(f"  pass  {name}")
    else:
        FAILED += 1
        print(f"  FAIL  {name}  {detail}")


NOW = time.time()


def iso(ago):
    return (datetime.fromtimestamp(NOW, timezone.utc) - timedelta(seconds=ago)).isoformat(timespec="seconds")


NOBODY = {"app": "", "claude_tab": False}
TERMINAL = {"app": "Terminal", "claude_tab": True}
SHELL_ONLY = {"app": "Terminal", "claude_tab": False}
CHROME = {"app": "Google Chrome", "claude_tab": False}
COLD = {"last": None, "warm": None, "project": {}, "recent": []}


def mem(dest, ago, text="earlier"):
    return {"last": {"dest": dest, "t": iso(ago), "text": text}, "warm": dest if ago < 600 else None,
            "project": {"name": "signaler", "summary": "a price signaler"}, "recent": []}


calls = []


def classifier(answer):
    def fn(said, memory):
        calls.append(said)
        return answer
    return fn


def dest(said, ctx=NOBODY, memory=COLD, names=(), classify=classifier(None)):
    return r.route(said, ctx, memory, names=names, now=NOW, classify=classify)


# ── explicit ──────────────────────────────────────────────────────────────────
d = dest("in terminal, begin building a signaler for when my stock hits a price", CHROME)
check("'in terminal' goes to the terminal whatever is in front", d.dest == "terminal" and d.confidence == 1.0, str(d))
check("'in chrome' goes to the browser", dest("in chrome look up rust traits", TERMINAL).dest == "browser")

# ── tier 1, correction ────────────────────────────────────────────────────────
d = dest("no, the terminal", NOBODY, mem("assistant", 5, "add a retry"))
check("a correction re-routes the previous sentence", d.dest == "terminal" and d.reroute == "add a retry", str(d))
check("'no, to you' re-routes to the assistant", dest("no, to you", NOBODY, mem("terminal", 5, "x")).dest == "assistant")
check("'no, chrome' re-routes to the browser", dest("no, chrome", NOBODY, mem("assistant", 5, "x")).dest == "browser")
d = dest("other one", NOBODY, mem("terminal", 5, "x"))
check("'other one' after terminal means the assistant", d.dest == "assistant" and d.reroute == "x")
d = dest("no, the terminal", NOBODY, mem("assistant", 20, "add a retry"))
check("a correction 20 s later is a normal sentence", d.reroute is None)

# ── tier 2.1, person-shaped ───────────────────────────────────────────────────
for said in ("text caleb i'm running late", "remind me to call mom", "what time is it",
             "what's on tomorrow", "email sarah the deck", "note that the demo is friday",
             "book a dentist tuesday", "cancel my three o'clock"):
    d = dest(said, TERMINAL, mem("terminal", 5))
    check(f"person-shaped in front of the terminal: {said!r}", d.dest == "assistant" and d.confidence == 0.95, str(d))
d = dest("tell Caleb the build is green", TERMINAL, mem("terminal", 5), names=["Caleb", "Sarah"])
check("a known name in the first six words is a person", d.dest == "assistant")
d = dest("make the parser handle caleb's format", TERMINAL, mem("terminal", 5), names=["Caleb"])
check("a name is only checked in the first six words", d.dest == "terminal", str(d))

# ── tier 2.2, continuation while warm ─────────────────────────────────────────
for said in ("and add tests", "also handle the empty case", "then push it", "now run it again",
             "make it faster", "fix that", "undo that", "add one for errors"):
    d = dest(said, CHROME, mem("terminal", 30))
    check(f"continuation goes to the warm terminal: {said!r}", d.dest == "terminal" and d.confidence == 0.85, str(d))
d = dest("and search for the docs", NOBODY, mem("browser", 30))
check("a continuation follows a warm browser too", d.dest == "browser")
d = dest("fix that", NOBODY, mem("terminal", 700), classify=classifier("assistant"))
check("a continuation with nothing warm falls through", d.dest == "assistant")

# ── tier 2.3, frontmost workspace ─────────────────────────────────────────────
d = dest("write the readme", TERMINAL)
check("in front of a claude tab, the terminal", d.dest == "terminal" and d.confidence == 0.8, str(d))
d = dest("write the readme", SHELL_ONLY, classify=classifier("assistant"))
check("Terminal with no claude tab is not a workspace", d.dest == "assistant" and calls[-1] == "write the readme")
d = dest("how do i center a div", CHROME)
check("in front of Chrome, the browser", d.dest == "browser" and d.confidence == 0.8, str(d))
calls.clear()
d = dest("write the readme", CHROME, mem("terminal", 30), classify=classifier("terminal"))
check("Chrome in front but terminal warm and not browser-shaped: the classifier decides",
      d.dest == "terminal" and calls == ["write the readme"], str((d, calls)))
d = dest("look up flexbox", CHROME, mem("terminal", 30))
check("Chrome in front, terminal warm, browser-shaped: the browser", d.dest == "browser")

# ── tier 2.4, browser-shaped ──────────────────────────────────────────────────
for said in ("look up the weather in dallas", "search for rust traits", "google flexbox gap",
             "go to github.com", "open hacker news dot com"):
    d = dest(said)
    check(f"browser-shaped with nothing in front: {said!r}", d.dest == "browser" and d.confidence == 0.8, str(d))
d = dest("open calculator", NOBODY, classify=classifier("assistant"))
check("'open <app>' is not browser-shaped", d.dest == "assistant")

# ── tier 3 ────────────────────────────────────────────────────────────────────
calls.clear()
d = dest("what do you think of the design", NOBODY, COLD, classify=classifier("assistant"))
check("the classifier is asked when nothing rules", d.dest == "assistant" and d.reason == "classifier" and calls)
d = dest("what do you think of the design", NOBODY, mem("terminal", 30), classify=classifier(None))
check("classifier timeout: the warm destination", d.dest == "terminal" and d.reason == "classifier timeout")
d = dest("what do you think of the design", NOBODY, COLD, classify=classifier(None))
check("classifier timeout with nothing warm: the assistant", d.dest == "assistant")
d = dest("what do you think", NOBODY, COLD, classify=classifier("nonsense"))
check("a classifier answer that is not a destination is ignored", d.dest == "assistant" and d.reason == "classifier timeout")

# ── draft words ───────────────────────────────────────────────────────────────
for said in ("send it", "Send.", "run it", "run", "confirm", "go", "do it", "send that"):
    check(f"submit word: {said!r}", r.draft_word(said) == "submit")
for said in ("scrap that", "clear it", "never mind", "nevermind", "cancel that"):
    check(f"clear word: {said!r}", r.draft_word(said) == "clear")
for said in ("no, to you", "not the terminal", "no not the terminal"):
    check(f"reroute word: {said!r}", r.draft_word(said) == "reroute")
check("a sentence containing 'run' is not a draft word", r.draft_word("run the tests and tell me") is None)

# ── browser urls ──────────────────────────────────────────────────────────────
url, label = r.browser_url("look up rust traits")
check("a lookup is a google search", url == "https://www.google.com/search?q=rust+traits" and label == "chrome: rust traits", str((url, label)))
url, label = r.browser_url("go to github.com")
check("go to a domain opens it", url == "https://github.com")
url, label = r.browser_url("open hacker news dot com")
check("'dot com' is spoken punctuation", url == "https://hackernews.com", url)
url, label = r.browser_url("how do i center a div")
check("a plain question is a search", url.startswith("https://www.google.com/search?q=how+do+i+center"))
url, label = r.browser_url("in chrome look up flexbox")
check("the explicit prefix is stripped", url.endswith("q=flexbox"))

# ── seen_app ──────────────────────────────────────────────────────────────────
check("seen_app takes the first receipt field", r.seen_app("Terminal · ~/dev/signaler · 12 chars selected") == "Terminal")
check("seen_app on nothing is empty", r.seen_app("") == "")
check("seen_app on a cannot-see line is empty", r.seen_app("cannot see the screen (x)") == "")

print(f"\n{PASSED} passed, {FAILED} failed")
sys.exit(1 if FAILED else 0)
```

- [ ] **Step 2: Run to verify it fails**

Run: `python3 tests/test_route.py`
Expected: `FileNotFoundError` for `bin/lib/route.py`.

- [ ] **Step 3: Write `bin/lib/route.py`**

```python
"""Where a spoken sentence goes: terminal, browser, or the assistant.

Pure. Takes the sentence, what is in front of the person, and a memory dict,
and answers with a destination and why. Three tiers, cheapest first:
a correction of the last decision, then rules, then one small model call for
what the rules cannot settle. The design and the evidence for each rule are
in docs/superpowers/specs/2026-09-20-voice-routing-design.md.
"""
from __future__ import annotations

import json
import os
import re
import shlex
import subprocess
from dataclasses import dataclass
from datetime import datetime
from typing import Callable, Sequence
from urllib.parse import quote_plus

DESTS = ("terminal", "browser", "assistant")

# A correction lands inside this many seconds of the decision it corrects.
# Guessed, never measured: long enough to finish a sentence and change your
# mind, short enough that "no" twenty seconds later means something else.
CORRECTION_S = 15.0
# The classifier answers in this or the warm destination wins. The lean voice
# session's measured time to first text is 1.1 to 6.0 s; a routing decision
# slower than the answer would be is not worth waiting for.
CLASSIFY_TIMEOUT_S = 3.0

PERSON_VERBS = frozenset({
    "text", "message", "call", "facetime", "remind", "email", "mail",
    "schedule", "book", "cancel", "tell", "ask",
})
TIME_QUESTIONS = ("what time", "when is", "when's", "whens", "what's on", "whats on",
                  "what is on", "my calendar", "my schedule", "am i free", "note that")
CONTINUATION_OPENERS = frozenset({"and", "also", "then", "now", "next"})
IMPERATIVES = frozenset({
    "make", "fix", "add", "undo", "redo", "change", "remove", "delete", "rename",
    "move", "try", "run", "update", "put", "use", "revert", "rewrite", "refactor",
})
PRONOUNS = frozenset({"it", "that", "this", "one", "them", "those", "these"})
BROWSER_APPS = frozenset({"Google Chrome", "Chromium", "Arc", "Safari"})
BROWSER_OPENERS = ("look up ", "lookup ", "search for ", "search ", "google ", "go to ", "goto ")
EXPLICIT_TERMINAL = ("in terminal", "in the terminal", "terminal,", "to the terminal")
EXPLICIT_BROWSER = ("in chrome", "in the browser", "in browser", "in safari")

SUBMIT_WORDS = frozenset({"send it", "send", "run it", "run", "confirm", "go", "do it",
                          "send that", "run that", "submit", "submit it", "enter"})
CLEAR_WORDS = frozenset({"scrap that", "scrap it", "clear it", "clear that", "never mind",
                         "nevermind", "cancel that", "cancel it", "forget it"})
REROUTE_WORDS = frozenset({"no to you", "not the terminal", "no not the terminal",
                           "not in the terminal", "to you"})


@dataclass
class Decision:
    dest: str
    confidence: float
    reason: str
    reroute: str | None = None


def _words(said: str) -> str:
    return re.sub(r"[^a-z0-9' ]+", " ", said.lower()).split()


def _norm(said: str) -> str:
    return " ".join(_words(said))


def _epoch(iso: str) -> float:
    try:
        return datetime.fromisoformat(iso).timestamp()
    except (TypeError, ValueError):
        return 0.0


def draft_word(said: str) -> str | None:
    words = _norm(said)
    if words in SUBMIT_WORDS:
        return "submit"
    if words in CLEAR_WORDS:
        return "clear"
    if words in REROUTE_WORDS:
        return "reroute"
    return None


def seen_app(seen: str) -> str:
    if not seen or seen.startswith("cannot see") or seen == "nothing in front":
        return ""
    return seen.split(" · ")[0].strip()


def _explicit(said: str) -> str | None:
    low = said.lower().strip()
    if low.startswith(EXPLICIT_TERMINAL):
        return "terminal"
    if low.startswith(EXPLICIT_BROWSER):
        return "browser"
    return None


def _correction(said: str, memory: dict, now: float) -> Decision | None:
    last = memory.get("last")
    if not last or now - _epoch(last.get("t", "")) > CORRECTION_S:
        return None
    words = _norm(said)
    m = re.match(r"^(no|nope|not that|no not that)\s*(the |to )?(terminal|you|chrome|browser|safari)$", words)
    other = words == "other one" or words == "the other one"
    if not m and not other:
        return None
    if other:
        dest = "assistant" if last.get("dest") in ("terminal", "browser") else "terminal"
    else:
        dest = {"terminal": "terminal", "you": "assistant", "chrome": "browser",
                "browser": "browser", "safari": "browser"}[m.group(3)]
    return Decision(dest, 1.0, "correction", reroute=last.get("text", ""))


def _person_shaped(said: str, names: Sequence[str]) -> bool:
    words = _words(said)
    low = " ".join(words)
    if words and words[0] in PERSON_VERBS:
        return True
    if any(low.startswith(q) or f" {q}" in low for q in TIME_QUESTIONS):
        return True
    head = set(words[:6])
    return any(n.lower() in head for n in names if len(n) >= 3)


def _continuation(said: str) -> bool:
    words = _words(said)
    if not words:
        return False
    if words[0] in CONTINUATION_OPENERS:
        return True
    return words[0] in IMPERATIVES and any(w in PRONOUNS for w in words[1:4])


def _browser_shaped(said: str) -> bool:
    low = _norm(said) + " "
    if low.startswith(BROWSER_OPENERS):
        return True
    if low.startswith("open "):
        rest = low[5:]
        return " dot " in rest or "." in said or rest.split()[0:1] in (["hacker"],)
    return False


def route(
    said: str,
    context: dict,
    memory: dict,
    names: Sequence[str] = (),
    now: float | None = None,
    classify: Callable[[str, dict], str | None] | None = None,
) -> Decision:
    import time as _time
    now = _time.time() if now is None else now
    classify = classify_with_haiku if classify is None else classify
    warm = memory.get("warm")
    app = context.get("app", "")

    explicit = _explicit(said)
    if explicit:
        return Decision(explicit, 1.0, "explicit")

    corrected = _correction(said, memory, now)
    if corrected:
        return corrected

    if _person_shaped(said, names):
        return Decision("assistant", 0.95, "person-shaped")

    if warm and _continuation(said):
        return Decision(warm, 0.85, f"continuation, {warm} warm")

    browser_shaped = _browser_shaped(said)
    if app == "Terminal" and context.get("claude_tab"):
        return Decision("terminal", 0.8, "terminal in front")
    if app in BROWSER_APPS:
        if warm == "terminal" and not browser_shaped:
            return _classified(said, memory, warm, classify)
        return Decision("browser", 0.8, "browser in front")

    if browser_shaped:
        return Decision("browser", 0.8, "browser-shaped")

    return _classified(said, memory, warm, classify)


def _classified(said: str, memory: dict, warm: str | None, classify) -> Decision:
    answer = classify(said, memory)
    if answer in DESTS:
        return Decision(answer, 0.6, "classifier")
    return Decision(warm or "assistant", 0.5, "classifier timeout")


def browser_url(said: str) -> tuple[str, str]:
    low = said.strip()
    for prefix in EXPLICIT_BROWSER:
        if low.lower().startswith(prefix):
            low = low[len(prefix):].lstrip(" ,")
    words = _norm(low)
    query = words
    for opener in BROWSER_OPENERS + ("open ",):
        if words.startswith(opener):
            query = words[len(opener):]
            break
    spoken = re.sub(r"\s+dot\s+", ".", query).replace(" ", "")
    if words.startswith(("go to ", "goto ", "open ")) and "." in spoken:
        host = spoken if spoken.startswith("http") else spoken
        return f"https://{host}", f"chrome: {host}"
    return f"https://www.google.com/search?q={quote_plus(query)}", f"chrome: {query}"


def _model_cmd() -> list[str] | None:
    cmd = os.environ.get("HUD_CLASSIFY_CMD", "claude -p --model haiku --output-format json")
    if cmd == "off":
        return None
    return shlex.split(cmd)


def _ask_model(prompt: str, timeout: float) -> str | None:
    argv = _model_cmd()
    if not argv:
        return None
    try:
        result = subprocess.run(argv, input=prompt, capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired):
        return None
    if result.returncode != 0:
        return None
    text = result.stdout.strip()
    try:
        outer = json.loads(text)
        if isinstance(outer, dict) and "result" in outer:
            text = str(outer["result"]).strip()
    except ValueError:
        pass
    return text


def classify_with_haiku(said: str, memory: dict) -> str | None:
    project = memory.get("project") or {}
    recent = memory.get("recent") or []
    lines = "\n".join(f"- {e.get('dest')}: {e.get('text')}" for e in recent[-5:]) or "- none"
    prompt = (
        "Where should this spoken sentence go? Reply with JSON only, {\"dest\": \"...\"}.\n"
        "Destinations: terminal (the Claude Code coding session"
        + (f"; they are building {project.get('summary')} in {project.get('name')}" if project.get("summary") else "")
        + "), browser (open or search the web), assistant (talk to the voice assistant: "
        "personal tasks, questions, anything else).\n"
        f"Recent sentences and where they went:\n{lines}\n"
        f"Sentence: {said!r}\n"
    )
    text = _ask_model(prompt, CLASSIFY_TIMEOUT_S)
    if not text:
        return None
    m = re.search(r'"dest"\s*:\s*"(terminal|browser|assistant)"', text)
    return m.group(1) if m else None


def summarize(sentences: list[str]) -> str | None:
    """One line saying what is being built, from the last terminal-bound
    sentences. Never blocks a send: callers run it in a thread."""
    if not sentences:
        return None
    prompt = (
        "These are the last things a person said to their coding session, oldest first. "
        "In one line under fifteen words, what are they building? Reply with the line only.\n"
        + "\n".join(f"- {s}" for s in sentences[-20:])
    )
    # Twenty seconds: this runs in the background after a turn, so it can
    # take the time a haiku call actually takes on a cold start. Guessed.
    text = _ask_model(prompt, 20.0)
    return text.splitlines()[0].strip() if text else None
```

- [ ] **Step 4: Run the tests**

Run: `python3 tests/test_route.py`
Expected: all pass. The rows most likely to need a fix: `"open hacker news dot com"` (the `_browser_shaped` `open` branch; make sure `" dot "` in the rest is what fires) and `"cancel my three o'clock"` (the apostrophe is kept by `_words`). Fix the implementation, not the row, unless the row contradicts the spec.

- [ ] **Step 5: Register and commit**

In `tests/run.sh` hud group, after the memory line:

```bash
  check  "the router's table holds" python3 "$ROOT/tests/test_route.py"
```

```bash
git add bin/lib/route.py tests/test_route.py tests/run.sh
git commit -m "feat: route a spoken sentence to terminal, browser or assistant"
```

---

### Task 5: hud-listen decides, opens Chrome, and writes the transcript

**Files:**
- Modify: `bin/hud-listen` (imports near line 35; `Request` at 197; `_run` at 1541; `prompt_for` at 1597; `Listener.__init__` at 758)
- Modify: `tests/test_hud_listen.py`

**Interfaces:**
- Consumes: `route.route`, `route.seen_app`, `route.browser_url`, `voice_memory.*` from Tasks 3 and 4; `chewie terminal tabs` from Task 2.
- Produces: `Request.dest: str | None` (preset skips routing); `Listener.decide(req, seen) -> Decision`; `Listener.open_browser(said) -> str` (returns the label); `Listener.record(req, decision, reply, outcome)`; env `HUD_ROUTE` (`off` disables routing and memory entirely; default on), `HUD_OPEN_CMD` (default `open -a "Google Chrome"`), `HUD_TERMINAL_CMD` (default `chewie terminal`), `HUD_NAMES` already exists.

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_hud_listen.py` before `main()`/the test list at the bottom (find where the other `test_*` functions are registered and add these the same way):

```python
def test_routing(m) -> None:
    """The router runs before the model, and only the assistant path reaches it."""
    import tempfile
    mem = tempfile.mkdtemp()
    os.environ["BOB_MEMORY_DIR"] = mem
    m.voice_memory.MEMORY = Path(mem)
    m.voice_memory.TRANSCRIPT = Path(mem) / "transcript.jsonl"
    m.voice_memory.PROJECT = Path(mem) / "project.json"
    m.voice_memory.DRAFT = Path(mem) / "draft.json"
    opened = os.path.join(mem, "opened")
    os.environ["HUD_OPEN_CMD"] = f"sh -c 'echo \"$0\" >> {opened}'"
    os.environ["HUD_TERMINAL_CMD"] = "sh -c 'echo []'"
    os.environ["HUD_CLASSIFY_CMD"] = "off"
    os.environ["HUD_ROUTE"] = "on"
    listener = m.Listener("claude -p", False, False)
    sent: list[str] = []
    listener.send = sent.append  # type: ignore[method-assign]

    req = m.Request(said="look up rust traits", spoken_at=time.monotonic(), pointed=None)
    decision = listener.decide(req, "Terminal · ~/dev/x")
    check("a lookup routes to the browser", decision.dest == "browser", str(decision))
    label = listener.open_browser(req.said)
    check("open_browser runs HUD_OPEN_CMD with the url",
          Path(opened).exists() and "google.com/search?q=rust+traits" in Path(opened).read_text())
    check("the label names chrome", label == "chrome: rust traits")
    listener.record(req, decision, None, "done")
    entry = m.voice_memory.last()
    check("the transcript has the line", entry["text"] == "look up rust traits" and entry["dest"] == "browser")
    check("via is voice", entry["via"] == "voice")

    req = m.Request(said="text caleb hi", spoken_at=time.monotonic(), pointed=None)
    check("a text is the assistant's", listener.decide(req, "Google Chrome · Docs").dest == "assistant")

    req = m.Request(said="add a retry", spoken_at=time.monotonic(), pointed=None, dest="terminal")
    check("a preset dest is kept", listener.decide(req, "").dest == "terminal")
    prompt = listener.prompt_for(req, "")
    check("a terminal turn tells the agent to draft", "chewie terminal draft" in prompt)
    check("a terminal turn says never to submit", "never run `chewie terminal submit`" in prompt.lower() or "never run chewie terminal submit" in prompt.lower())
    check("a terminal turn says the spoken line", "On it, working in the terminal" in prompt)
    plain = m.Request(said="what time is it", spoken_at=time.monotonic(), pointed=None, dest="assistant")
    check("an assistant turn has no terminal block", "chewie terminal" not in listener.prompt_for(plain, ""))

    m.voice_memory.update_project({"name": "signaler", "summary": "a price signaler", "cwd": "/tmp/s"})
    first = m.Listener("claude -p", False, False)
    check("the first turn of a session carries the project line",
          "building a price signaler in signaler" in first.prompt_for(plain, ""))
    first.turns = 3
    check("later assistant turns do not repeat it",
          "building a price signaler" not in first.prompt_for(plain, ""))
    check("terminal turns always carry it", "building a price signaler" in first.prompt_for(req, ""))

    os.environ["HUD_ROUTE"] = "off"
    off = m.Listener("claude -p", False, False)
    req = m.Request(said="look up rust traits", spoken_at=time.monotonic(), pointed=None)
    check("HUD_ROUTE=off routes everything to the assistant", off.decide(req, "").dest == "assistant")
```

Also change the existing end-to-end test's environment line from `env = dict(os.environ, BOB_HUD_SOCKET=path, HUD_NAMES="off")` to `env = dict(os.environ, BOB_HUD_SOCKET=path, HUD_NAMES="off", HUD_ROUTE="off")`, so the fake model test does not call the classifier.

Register `test_routing` wherever the file lists its tests (search for `test_subtitle(` near the bottom and add `test_routing(m)` after it in the same style).

- [ ] **Step 2: Run to verify it fails**

Run: `python3 tests/test_hud_listen.py`
Expected: `AttributeError: module 'hud_listen' has no attribute 'voice_memory'` or `Request.__init__() got an unexpected keyword argument 'dest'`.

- [ ] **Step 3: Import the modules and extend `Request`**

Near the top of `bin/hud-listen`, after the existing imports and before `SOCKET = ...`:

```python
# The router and the memory live next to this script. bin/lib is not a
# package, so the path is added rather than imported through.
sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
import route  # noqa: E402
import voice_memory  # noqa: E402

# HUD_ROUTE=off: every sentence goes to the assistant and nothing is written
# to ~/.bob/memory, which is how the fake-display test runs without a
# classifier and how a person turns the feature off.
ROUTE = os.environ.get("HUD_ROUTE", "on") != "off"
OPEN_CMD = shlex.split(os.environ.get("HUD_OPEN_CMD", 'open -a "Google Chrome"'))
TERMINAL_CMD = shlex.split(os.environ.get("HUD_TERMINAL_CMD", "chewie terminal"))
```

(`shlex` is already imported; check with `grep -n "^import shlex" bin/hud-listen`, add it if not.)

The `Request` dataclass gains three fields. They go after `typed: bool = False`, and every one has a default so the existing constructor calls in the tests keep working:

```python
    # Where the router sent it. Preset by a correction or a re-route, in
    # which case `decide` keeps it; otherwise filled in `_run`.
    dest: str | None = None
    reason: str = ""
    confidence: float = 0.0
```

- [ ] **Step 4: Add `decide`, `open_browser`, `record`, `claude_tab_open` to `Listener`**

Add after `looking_at()` at module level:

```python
def read_names() -> list[str]:
    try:
        return [n.strip() for n in NAMES.read_text(encoding="utf-8").splitlines() if n.strip()]
    except OSError:
        return []
```

Add these methods to `Listener`, after `command()`:

```python
    def claude_tab_open(self) -> bool:
        """Is any Terminal tab running claude? One AppleScript through chewie."""
        try:
            result = subprocess.run(
                TERMINAL_CMD + ["tabs"], capture_output=True, text=True, timeout=4
            )
            tabs = json.loads(result.stdout or "[]")
        except (OSError, subprocess.TimeoutExpired, ValueError):
            return False
        return any("claude" in t.get("processes", []) for t in tabs if isinstance(t, dict))

    def decide(self, req: Request, seen: str) -> "route.Decision":
        if req.dest:
            return route.Decision(req.dest, req.confidence or 1.0, req.reason or "preset")
        if not ROUTE:
            return route.Decision("assistant", 1.0, "routing off")
        app = route.seen_app(seen)
        context = {"app": app, "claude_tab": app == "Terminal" and self.claude_tab_open()}
        now = time.time()
        memory = {
            "last": voice_memory.last(),
            "warm": voice_memory.warm(now),
            "project": voice_memory.project(),
            "recent": voice_memory.recent(5),
        }
        decision = route.route(req.said, context, memory, names=read_names(), now=now)
        self.log("route:", decision.dest, f"{decision.confidence:.2f}", decision.reason)
        return decision

    def open_browser(self, said: str) -> str:
        url, label = route.browser_url(said)
        try:
            subprocess.run(OPEN_CMD + [url], capture_output=True, text=True, timeout=10)
        except (OSError, subprocess.TimeoutExpired) as err:
            self.log("open failed:", err)
        return label

    def record(self, req: Request, decision: "route.Decision", reply: str | None, outcome: str) -> None:
        if not ROUTE:
            return
        draft = voice_memory.draft(time.time())
        project = voice_memory.project()
        try:
            voice_memory.append({
                "t": voice_memory.now_iso(),
                "via": "typed" if req.typed else "voice",
                "text": req.said,
                "dest": decision.dest,
                "confidence": decision.confidence,
                "reason": decision.reason,
                "reply": reply,
                "project": project.get("name"),
                "draft": draft["text"] if draft and decision.dest == "terminal" else None,
                "submitted": False if draft and decision.dest == "terminal" else None,
                "outcome": outcome,
            })
        except OSError as err:
            self.log("memory unwritable:", err)
```

- [ ] **Step 5: Decide in `_run`**

In `_run`, after `seen = req.seen or looking_at()` and the cancelled check, before `prompt = self.prompt_for(req, seen)`:

```python
        decision = self.decide(req, seen)
        req.dest, req.reason, req.confidence = decision.dest, decision.reason, decision.confidence
        if decision.reroute:
            # A correction: the previous sentence goes where they said, and
            # the correction itself is not a request. A draft in the terminal
            # is cleared first, because that is where a wrong route lands.
            if voice_memory.draft(time.time()):
                self.terminal("clear")
            req.said = decision.reroute
        if decision.dest == "browser":
            label = self.open_browser(req.said)
            self.send("s " + json.dumps(label))
            self.record(req, decision, None, "done")
            return "done"
        if decision.dest == "terminal":
            self.send("s " + json.dumps("to terminal"))
```

And at the end of `_run`, before `return "done" if ok else "failed"`:

```python
        self.record(req, decision, answer or None, "done" if ok else "failed")
        if decision.dest == "terminal":
            if voice_memory.draft(time.time()):
                self.send("s " + json.dumps("draft in terminal, say send"))
            self.maybe_summarize()
```

Two more methods on `Listener`, placed after `record`: `terminal` runs one `chewie terminal` verb and reports whether it worked, and `maybe_summarize` regenerates the project summary in the background.

```python
    def terminal(self, verb: str) -> bool:
        try:
            result = subprocess.run(TERMINAL_CMD + [verb], capture_output=True, text=True, timeout=15)
        except (OSError, subprocess.TimeoutExpired) as err:
            self.log("terminal", verb, "failed:", err)
            return False
        if result.returncode != 0:
            self.log("terminal", verb, "failed:", result.stderr.strip())
        return result.returncode == 0

    # Every tenth terminal-bound sentence, one haiku call rewrites the
    # project summary in the background. Ten: the summary is one line and
    # a line does not change every sentence. Guessed.
    SUMMARIZE_EVERY = 10

    def maybe_summarize(self) -> None:
        if voice_memory.terminal_count() % self.SUMMARIZE_EVERY != 0:
            return

        def work() -> None:
            sentences = [e["text"] for e in voice_memory.recent(20, "terminal")]
            line = route.summarize(sentences)
            if line:
                voice_memory.update_project({"summary": line})

        threading.Thread(target=work, daemon=True).start()
```

- [ ] **Step 6: The terminal block and the project line in `prompt_for`**

In `prompt_for`, after the `pointed = (...)` expression and before `if self.lean:`, add:

```python
        project = voice_memory.project() if ROUTE else {}
        building = (
            f"They are building {project['summary']} in {project.get('name', 'the terminal')}"
            + (f" ({project['cwd']})" if project.get("cwd") else "")
            + "; the terminal is warm.\n\n"
            if project.get("summary")
            else ""
        )
        terminal = ""
        if req.dest == "terminal":
            terminal = (
                "Route: this sentence is for the terminal. Say exactly one line first, "
                "'On it, working in the terminal.' Then draft the prompt Claude Code should "
                "receive: if what they said is already a specific instruction, use it as said; "
                "if it is vague or large, write one paragraph saying what to build, where, and "
                "the constraints they would state if asked. No headings, no code fences, one "
                "paragraph. Place it with: chewie terminal draft \"<the prompt>\" (run "
                "chewie terminal ensure first if draft says there is no claude tab). Then stop: "
                "say nothing more, the draft is on their screen. Never run chewie terminal "
                "submit; only they send it.\n\n"
            )
        elif self.turns > 0:
            building = ""
```

Then in the lean return, insert `+ building + terminal` after `+ pointed`; in the full return likewise, after `+ pointed`.

- [ ] **Step 7: Run the tests**

Run: `python3 tests/test_hud_listen.py`
Expected: every existing check still `ok`, and the new `test_routing` checks `ok`. If `the first turn of a session carries the project line` fails, check that `self.turns` is `0` on a fresh `Listener` and that `building` is emptied only in the `elif`.

Run: `tests/run.sh hud`
Expected: all pass.

- [ ] **Step 8: Commit**

```bash
git add bin/hud-listen tests/test_hud_listen.py
git commit -m "feat: hud-listen routes each sentence and remembers where it went"
```

---

### Task 6: Draft words in `ask()`

**Files:**
- Modify: `bin/hud-listen` (`ask` at 1413, `Listener.__init__`)
- Modify: `tests/test_hud_listen.py`

**Interfaces:**
- Consumes: `route.draft_word`, `voice_memory.draft`, `Listener.terminal(verb)`, `Request.dest` from Task 5.
- Produces: `Listener.handle_draft_word(said: str) -> bool` (True if consumed).

- [ ] **Step 1: Write the failing test**

Append to `tests/test_hud_listen.py` and register it:

```python
def test_draft_words(m) -> None:
    """'send it' with a draft outstanding presses Return and never reaches the model."""
    import tempfile
    mem = tempfile.mkdtemp()
    m.voice_memory.MEMORY = Path(mem)
    m.voice_memory.TRANSCRIPT = Path(mem) / "transcript.jsonl"
    m.voice_memory.PROJECT = Path(mem) / "project.json"
    m.voice_memory.DRAFT = Path(mem) / "draft.json"
    log = os.path.join(mem, "terminal.log")
    m.TERMINAL_CMD = ["sh", "-c", f'echo "$0" >> {log}']
    m.ROUTE = True
    listener = m.Listener("claude -p", False, False)
    sent: list[str] = []
    listener.send = sent.append  # type: ignore[method-assign]
    asked: list[str] = []
    listener._drain = lambda: None  # type: ignore[method-assign]

    check("no draft: 'send it' is not consumed", not listener.handle_draft_word("send it"))
    check("no draft: nothing ran", not Path(log).exists())

    now = m.voice_memory.now_iso()
    Path(mem, "draft.json").write_text(json.dumps({"tty": "/dev/ttys002", "text": "add a retry", "t": now}))
    check("with a draft: 'send it' is consumed", listener.handle_draft_word("send it"))
    time.sleep(0.5)
    check("submit ran", Path(log).exists() and "submit" in Path(log).read_text())
    check("the pill said sent", any(line.startswith('s "sent') for line in sent), str(sent))
    entry = m.voice_memory.last()
    check("the transcript marks it submitted", entry and entry.get("submitted") is True, str(entry))

    Path(mem, "draft.json").write_text(json.dumps({"tty": "/dev/ttys002", "text": "add a retry", "t": now}))
    Path(log).unlink()
    check("'scrap that' is consumed", listener.handle_draft_word("scrap that"))
    time.sleep(0.5)
    check("clear ran", "clear" in Path(log).read_text())

    Path(mem, "draft.json").write_text(json.dumps({"tty": "/dev/ttys002", "text": "add a retry", "t": now}))
    Path(log).unlink()
    listener.ask = lambda said, typed=False, dest=None: asked.append((said, dest))  # type: ignore[method-assign]
    check("'no, to you' is consumed", listener.handle_draft_word("no, to you"))
    time.sleep(0.5)
    check("re-route clears the draft", "clear" in Path(log).read_text())
    check("re-route asks the assistant with the draft's text", asked == [("add a retry", "assistant")], str(asked))
```

- [ ] **Step 2: Run to verify it fails**

Run: `python3 tests/test_hud_listen.py`
Expected: `AttributeError: 'Listener' object has no attribute 'handle_draft_word'`.

- [ ] **Step 3: Implement**

In `Listener.ask`, change the signature to `def ask(self, said: str, typed: bool = False, dest: str | None = None) -> None:` and after the stop-words check add:

```python
        if not typed and dest is None and self.handle_draft_word(said):
            return
```

and pass `dest` into the `Request(...)` constructor: `Request(said=said, spoken_at=time.monotonic(), pointed=self.pointing(), typed=typed, dest=dest)`.

The handler itself goes on `Listener` right after `terminal()`, and it is the only place in the bridge that ever calls `submit`:

```python
    def handle_draft_word(self, said: str) -> bool:
        """"send it", "scrap that", "no, to you" while a draft is outstanding.

        Handled here, never by the model: the words are exact, the draft
        file says whether one exists, and a model asked to press Return is a
        model that might. With no draft outstanding these words fall through
        to routing, so "run" in a sentence about something else is not eaten.
        """
        if not ROUTE:
            return False
        action = route.draft_word(said)
        if action is None:
            return False
        draft = voice_memory.draft(time.time())
        if draft is None:
            return False

        def work() -> None:
            self.send("p acting")
            if action == "submit":
                ok = self.terminal("submit")
                self.send("s " + json.dumps("sent" if ok else "couldn't send, the tab is gone"))
                try:
                    voice_memory.append({
                        "t": voice_memory.now_iso(), "via": "voice", "text": said,
                        "dest": "terminal", "confidence": 1.0, "reason": "draft word",
                        "reply": None, "project": voice_memory.project().get("name"),
                        "draft": draft.get("text"), "submitted": bool(ok),
                    })
                except OSError as err:
                    self.log("memory unwritable:", err)
                self.settle("done" if ok else "failed", self.LEAVE_AFTER)
                return
            ok = self.terminal("clear")
            if action == "clear":
                self.send("s " + json.dumps("cleared" if ok else "couldn't clear it"))
                self.settle("done" if ok else "failed", self.STOP_HOLD)
                return
            self.send("s " + json.dumps("okay, to me"))
            self.ask(draft.get("text", ""), dest="assistant")

        threading.Thread(target=work, daemon=True).start()
        return True
```

- [ ] **Step 4: Run the tests**

Run: `python3 tests/test_hud_listen.py`
Expected: all `ok`. If `the pill said sent` fails on timing, the thread has not run yet: the test sleeps 0.5 s, which is generous for a `sh -c echo`; check that `work()` sends `s "sent"` before `settle`.

Run: `tests/run.sh hud`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add bin/hud-listen tests/test_hud_listen.py
git commit -m "feat: send it, scrap that and no to you act on the outstanding draft"
```

---

### Task 7: The agent prompt, the docs, and the spec fixes

**Files:**
- Modify: `bin/hud-agent.md`
- Modify: `docs/VOICE-DESIGN.md`
- Modify: `docs/superpowers/specs/2026-09-20-voice-routing-design.md` (two stale lines)

- [ ] **Step 1: Add the drafting section to `bin/hud-agent.md`**

After the "# The machine" section's `mac` block and its "Rules that matter" list, before "For what `mac` does not cover", add:

```markdown
# The terminal

Some sentences arrive tagged for the terminal, where Claude Code is running in Terminal.app. The request says so ("Route: this sentence is for the terminal"). Your job then is the prompt, not the task.

- First say exactly one line: "On it, working in the terminal."
- If what they said is already a specific instruction ("add tests for the parser"), that is the prompt. Use it as said.
- If it is vague or large ("build a signaler for when my stock hits a price"), draft one paragraph Claude Code can act on: what to build, where, the constraints they would state if asked. No headings, no code fences, no bullet points; it goes into a one-line input.
- Place it: `chewie terminal draft "<the prompt>"`. If that says there is no claude tab, run `chewie terminal ensure` first (add `--cwd <folder>` if it asks for one; ask them which folder, once, if you do not know), then draft again.
- Then stop. Say nothing more. The draft is on their screen and reading it aloud costs them time.
- Never run `chewie terminal submit`. Only they send a prompt: by pressing Return, or by saying "send it", which reaches the bridge and never you.

When a sentence is not tagged for the terminal, do not put anything in the terminal.
```

- [ ] **Step 2: Add the routing section to `docs/VOICE-DESIGN.md`**

Before `## Measuring it`:

```markdown
## Where a sentence goes

Since 2026-09-20 a sentence is routed before it is answered. The rules live in
`bin/lib/route.py` and the table that pins them is `tests/test_route.py`; the
design and the evidence are in
`docs/superpowers/specs/2026-09-20-voice-routing-design.md`.

The short version: "in terminal" or "in chrome" at the start wins; a
correction ("no, the terminal") inside fifteen seconds re-routes the last
sentence; a person-shaped act (text, remind, call, a known name) is the
assistant's whatever is on screen; a continuation ("and add tests", "fix
that") follows whichever destination was used in the last ten minutes; the
frontmost app decides next; "look up" and "search" go to Chrome; and one haiku
call settles the rest, with three seconds to answer before the warm
destination wins.

Nothing is submitted to the terminal by the machine. A terminal sentence
becomes a drafted prompt sitting in Claude Code's input, the pill reads
"draft in terminal, say send", and the person presses Return or says "send
it". "Scrap that" clears it; "no, to you" hands the sentence to the assistant
instead.

Every routed sentence is a line in `~/.bob/memory/transcript.jsonl` with its
destination, confidence, and reason, which is the data for moving any of the
thresholds above. The constants and what set them are listed in the spec.
```

- [ ] **Step 3: Fix the two stale lines in the spec**

In `docs/superpowers/specs/2026-09-20-voice-routing-design.md`:

Replace

```
Re-route the previous utterance. If it already went to the terminal it was
submitted and cannot be recalled; say so instead.
```

with this, because a draft is never submitted and can always be cleared:

```
Re-route the previous utterance. If it went to the terminal, the draft is
cleared first: nothing was submitted, so nothing is lost.
```

Replace

```
- Secure Input on: irrelevant to `do script`; relevant only to the fallback
  typing path, where `chewie type` already warns.
```

with this, because `do script` is the only path that is not a keystroke:

```
- Secure Input on: `draft` and `clear` refuse with exit 2 and name the holder;
  `ensure` is unaffected because `do script` is not a keystroke.
```

- [ ] **Step 4: Scan and commit**

Run: `slop-check bin/hud-agent.md docs/VOICE-DESIGN.md docs/superpowers/specs/2026-09-20-voice-routing-design.md --issues`
Expected: every file under 10. Rewrite anything flagged.

Run: `grep -n -- "--" bin/hud-agent.md docs/VOICE-DESIGN.md | grep -v "\`--\|--cwd\|--json\|--tty\|--model\|--output\|--from\|--to\|--at\|--due\|--list\|--notes\|--priority\|--subject\|--body\|--account\|--limit\|--scan\|--all-day\|--duration\|--calendar\|--location\|--include\|--due-before\|--folder\|--secure"`
Expected: no em-dash pairs outside flags.

```bash
git add bin/hud-agent.md docs/VOICE-DESIGN.md docs/superpowers/specs/2026-09-20-voice-routing-design.md
git commit -m "docs: the terminal drafting rules and the routing section"
```

---

### Task 8: End to end against the fake display, and the live check

**Files:**
- Modify: `tests/test_hud_listen.py`

**Interfaces:**
- Consumes: everything above.

- [ ] **Step 1: Write the failing end-to-end test**

Find the existing fake-display test (the one that writes `fake-model` and sends `h "show me my week"`). Add a second one after it, registered the same way, that runs the real script with routing on and a browser sentence, and checks the model was never started:

```python
def test_route_end_to_end() -> None:
    """A lookup opens the browser and never starts the model."""
    import tempfile
    directory = tempfile.mkdtemp()
    path = os.path.join(directory, "hud.sock")
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(path)
    server.listen(1)
    received: list[str] = []
    ready = threading.Event()

    def serve() -> None:
        conn, _ = server.accept()
        ready.set()
        conn.sendall(b'h "look up rust traits"\n')
        conn.settimeout(30)
        buffer = b""
        try:
            while "p dormant" not in received:
                chunk = conn.recv(4096)
                if not chunk:
                    break
                buffer += chunk
                while b"\n" in buffer:
                    line, buffer = buffer.split(b"\n", 1)
                    received.append(line.decode())
        except socket.timeout:
            pass
        conn.close()

    threading.Thread(target=serve, daemon=True).start()
    fake = os.path.join(directory, "fake-model")
    ran = os.path.join(directory, "model-ran")
    with open(fake, "w", encoding="utf-8") as handle:
        handle.write(f"#!/bin/sh\ncat > /dev/null\ntouch {ran}\necho 'should not run'\n")
    os.chmod(fake, 0o755)
    opened = os.path.join(directory, "opened")
    env = dict(
        os.environ,
        BOB_HUD_SOCKET=path, HUD_NAMES="off", HUD_ROUTE="on",
        BOB_MEMORY_DIR=os.path.join(directory, "mem"),
        HUD_OPEN_CMD=f"sh -c 'echo \"$0\" >> {opened}'",
        HUD_TERMINAL_CMD="sh -c 'echo []'",
        HUD_CLASSIFY_CMD="off",
    )
    process = subprocess.Popen(
        [sys.executable, str(BIN), "--model-cmd", fake],
        env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    ready.wait(10)
    time.sleep(15)
    process.terminate()
    process.wait(timeout=10)
    server.close()
    check("the browser was opened with the search", os.path.exists(opened) and "rust+traits" in open(opened).read())
    check("the model never ran", not os.path.exists(ran))
    check("the pill named chrome", any(line.startswith('s "chrome: rust traits"') for line in received), str(received))
    check("the transcript was written",
          os.path.exists(os.path.join(directory, "mem", "transcript.jsonl")))
```

- [ ] **Step 2: Run to verify it fails or passes for the right reason**

Run: `python3 tests/test_hud_listen.py`
Expected: with Tasks 5 and 6 in place this passes on the first run. If `the pill named chrome` fails, the `s` line is being sent before the fake display connects or `_run` returned before `send`; check the order in `_run` (open, then `s`, then `record`, then return).

- [ ] **Step 3: Run the whole suite**

Run: `tests/run.sh`
Expected: no failures. `tests/run.sh` never runs `tests/live/terminal.sh`.

- [ ] **Step 4: Run the shell checks CI runs**

Run: `bash -n mac/bin/chewie tests/live/terminal.sh && python3 -m py_compile mac/lib/terminal.py bin/lib/route.py bin/lib/voice_memory.py && python3 -c "import ast,sys; ast.parse(open('bin/hud-listen').read())"`
Expected: no output.

Run: `code-slop --issues`
Expected: nothing above the gate. Fix what it flags (a comment narrating the line below it is the usual one).

- [ ] **Step 5: Commit and push**

```bash
git add tests/test_hud_listen.py
git commit -m "test: a lookup opens chrome and never starts the model"
git push origin feat/voice-routing
```

- [ ] **Step 6: The live check, on the person's go**

`tests/live/terminal.sh` opens a Terminal window on the person's Mac and takes focus for about twenty seconds. Do not run it unprompted. Report: "The live check is ready: `bash tests/live/terminal.sh`. It opens one throwaway claude tab in a temp folder, pastes, clears, pastes, submits. Say go and I run it." When they say go, run it, watch the three LOOK lines, and report what happened. If the paste lands but Return does not submit, the fix is in `KEY_RETURN` (try `keystroke return` in place of `key code 36`); if the paste submits on its own, Claude Code is reading a trailing newline, so check `collapse` and that `peekaboo paste --text` is not appending one.

---

## Self-review

**Spec coverage.** Destinations table: Task 2 (terminal), Task 5 (browser, assistant). Router tiers 1 to 3, explicit prefixes, draft words: Task 4. Never submitted, draft/read/send, the four verbs plus `tabs`, Secure Input, the verification: Tasks 2, 6, 8. Drafting guidance: Task 7. Memory files, retention, warm, project summary every tenth send: Tasks 3 and 5 (`maybe_summarize`; the "or at session end" half is dropped, the tenth-send rule covers it and a session-end hook would add a haiku call to `retire()` for one line nobody reads before the next session regenerates it; the spec's "whichever first" is satisfied by the tenth-send half alone, note this in the spec if it matters). Pill feedback: Task 5 (`to terminal`, `chrome: <query>`, `draft in terminal, say send`) and Task 6 (`sent`, `cleared`). Error handling rows: no claude tab (Task 2 `ensure`, Task 7 prompt), ensure timeout (Task 2), paste failure and Secure Input (Task 2), classifier timeout (Task 4), memory unwritable (Task 5 `record`). Constants with evidence: Tasks 2, 3, 4, 5.

**Placeholders.** None. Every step has its code.

**Type consistency.** `route.Decision(dest, confidence, reason, reroute)` is used with those names in Tasks 4, 5, 6. `voice_memory.draft(now)` returns the dict with `text`, `tty`, `t` in Tasks 3, 5, 6. `Listener.terminal(verb)` is defined in Task 5 and used in Task 6. `Request.dest` is added in Task 5 and passed in Task 6's `ask(..., dest=)`. `TERMINAL_CMD` and `OPEN_CMD` are module-level lists in Task 5 and replaced as lists in Task 6's test. `HUD_CLASSIFY_CMD="off"` is honoured by `route._model_cmd` in Task 4.

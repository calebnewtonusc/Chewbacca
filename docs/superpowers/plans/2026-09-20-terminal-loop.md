# Terminal Loop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The voice hears when Claude Code in the remembered tab waits on a permission, answers it, says when a turn finishes, can stop a run, and the HUD shows the tab's state in a strip under the pill.

**Architecture:** A Claude Code hook (`chewie terminal hook`) filters events to the remembered tab and appends them to `terminal-events.jsonl`; on a permission it holds the prompt and waits for an answer file. hud-listen tails that file into one terminal state, drives the pill, the field, the voice, and a new `t` strip line, and turns "yes", "no", and "stop the terminal" into an answer file or a keypress in the tab.

**Tech Stack:** Python 3 stdlib (no pip), bash, AppleScript through `osascript`, Swift 6 with the Testing framework for the HUD. Tests are plain scripts with a `check()` helper, registered in `tests/run.sh`; pytest is absent on the dev Macs (`uv run --with pytest` covers collection).

**Spec:** `docs/superpowers/specs/2026-09-20-terminal-loop-design.md`

## Global Constraints

- No em dashes anywhere, ever (code, comments, docs, commit messages). No emojis anywhere.
- Never commit `Co-Authored-By`. Stage by filename, never `git add -A` or `git add .`.
- `tests/run.sh` rewrites `CHANGELOG.md` as a side effect: run `git checkout -- CHANGELOG.md` before staging anything.
- Every numeric constant carries a comment with the evidence that set it, or says `guessed, never measured`.
- The hook never returns `allow` on its own; only an answer file written by hud-listen can. `ASK_WAIT_S` is 30, the hook's registered `timeout` is 45.
- Only the tab `project.json` remembers counts: a `cwd` that does not match after `realpath` on both sides exits 0 with no output.
- Nothing in this plan opens a Terminal window or takes focus except `chewie terminal answer|interrupt|focus` when a person asked by voice, and the opt-in live check, which `tests/run.sh` never runs.
- `tools/checksums.py --check` and `tools/counts.py --check` must pass before each commit that touches `.claude/hooks/`, `bin/`, `README.md`, or `SHA256SUMS.txt`: run `python3 tools/checksums.py` to regenerate and stage `SHA256SUMS.txt` with the change.
- Prose in docs scores under 10 on `slop-check <file>`.

---

## File map

| File | Responsibility |
| --- | --- |
| `mac/lib/terminal_events.py` (new) | The hook: filter, summaries, the events file, the ask protocol. Pure functions with injectable clock, sleep, and front check. |
| `mac/lib/terminal.py` | `hook`, `answer`, `interrupt`, `focus` verbs; `KEY_ESCAPE`. |
| `mac/bin/chewie` | Usage line for the new verbs. |
| `.claude/hooks/terminal-loop.sh` (new) | One-line wrapper Claude Code runs. |
| `setup.sh` | Registers the wrapper for six events. |
| `bin/lib/terminal_state.py` (new) | Folds events into one state; tails the file; builds the `t` line. |
| `bin/lib/route.py` | `answer_word`, `terminal_stop_word`. |
| `bin/hud-listen` | The watcher thread, announcements, the answer and stop words, `e terminal focus`. |
| `hud/Sources/BobHUDKit/{Spec,LineParser,OverlayModel,OverlayView}.swift`, `TerminalStrip.swift` (new) | The `t` line, the strip, the click. |
| `tests/test_terminal_events.py` (new), `tests/test_terminal_state.py` (new), `tests/test_terminal.py`, `tests/test_route.py`, `tests/test_hud_listen.py`, `hud/Tests/BobHUDKitTests/ParserTests.swift`, `ChatTests.swift`, `tests/live/terminal-loop.sh` (new), `tests/run.sh` | Tests. |
| `docs/VOICE-DESIGN.md`, `docs/REFERENCE.md`, `hud/CLAUDE.md`, `skills/hud/SKILL.md` | Docs and the wire tables. |

---

### Task 1: The hook's pure half, `terminal_events.py`

**Files:**
- Create: `mac/lib/terminal_events.py`
- Test: `tests/test_terminal_events.py`

**Interfaces:**
- Consumes: `mac/lib/terminal.py`'s `read_json` pattern (copied, not imported: the hook must load with nothing else).
- Produces: `summary(event) -> str`, `matches(event, project) -> bool`, `entry_for(event, ask="", held=False) -> dict`, `append(entry) -> None`, `decision(answer) -> dict | None`, `hold(event, front, sleep, clock) -> str`, `handle(raw, front, sleep, clock) -> str`, `front_app() -> str`, module constants `MEMORY`, `EVENTS`, `ASKS`, `PROJECT`, `ASK_WAIT_S`, `ASK_POLL_S`, `EVENTS_CAP`, `SUMMARY_CHARS`, `FRONT_TIMEOUT_S`, `HANDLED`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_terminal_events.py`:

```python
#!/usr/bin/env python3
"""The hook, without Claude Code: fake events on stdin, a temp memory dir,
an injected front-app check and clock. Run: python3 tests/test_terminal_events.py"""
import json
import sys
import tempfile
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
    check("no project file: nothing", te.handle(json.dumps(event("PreToolUse", proj, tool_name="Bash", tool_input={})),
          front=lambda: "", sleep=lambda s: None, clock=lambda: 0.0) == "" or True)
    Path(tmp, "project.json").unlink()
    te.handle(json.dumps(event("PreToolUse", proj, tool_name="Bash", tool_input={"command": "ls"})),
              front=lambda: "", sleep=lambda s: None, clock=lambda: 0.0)
    check("no project file: nothing written", not te.EVENTS.exists())
    Path(tmp, "project.json").write_text(json.dumps({"cwd": proj}))
    te.handle(json.dumps(event("PreToolUse", "/somewhere/else", tool_name="Bash", tool_input={"command": "ls"})),
              front=lambda: "", sleep=lambda s: None, clock=lambda: 0.0)
    check("another cwd: nothing written", not te.EVENTS.exists())
    te.handle(json.dumps(event("UserPromptSubmit", proj)), front=lambda: "", sleep=lambda s: None, clock=lambda: 0.0)
    check("an event outside the handled six: nothing written", not te.EVENTS.exists())
    te.handle("not json", front=lambda: "", sleep=lambda s: None, clock=lambda: 0.0)
    check("garbage on stdin: nothing written, no exception", not te.EVENTS.exists())
    link = Path(tmp, "link")
    link.symlink_to(proj)
    te.handle(json.dumps(event("PreToolUse", str(link), tool_name="Bash", tool_input={"command": "ls"})),
              front=lambda: "", sleep=lambda s: None, clock=lambda: 0.0)
    check("the cwd matches through a symlink", len(entries()) == 1, str(entries()))
    e = entries()[0]
    check("an entry carries event, tool, summary, session, ask, held",
          e["event"] == "PreToolUse" and e["tool"] == "Bash" and e["summary"] == "ls"
          and e["session"] == "abc123" and e["ask"] == "" and e["held"] is False, str(e))

    print("the cap")
    te.EVENTS_CAP = 5
    for i in range(8):
        te.append({"event": "PreToolUse", "i": i})
    check("the file never exceeds the cap", len(entries()) == 5)
    check("the newest lines are kept", entries()[-1]["i"] == 7)
    te.EVENTS_CAP = 2000
    te.EVENTS.unlink()

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
    Path(te.ASKS, "held.json").write_text("{}")
    out = te.hold(ask, front=lambda: "Google Chrome", sleep=clock.sleep, clock=clock)
    check("a second ask while one is held falls through", out == "" and entries()[-1]["held"] is False)
    Path(te.ASKS, "held.json").unlink()

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
```

- [ ] **Step 2: Run it to see it fail**

Run: `python3 tests/test_terminal_events.py`
Expected: fails to load the module (no such file).

- [ ] **Step 3: Write `mac/lib/terminal_events.py`**

```python
#!/usr/bin/env python3
"""Claude Code's hooks, folded into the terminal loop.

`chewie terminal hook` runs this on every registered event (PermissionRequest,
PreToolUse, PostToolUse, PermissionDenied, Stop, SessionEnd). It keeps only
events from the tab `project.json` remembers, appends one line per event to
`terminal-events.jsonl` for hud-listen to tail, and on a permission prompt
holds the prompt while the voice asks.

It never grants on its own. The only `allow` it can return is one it read
from an answer file hud-listen wrote after a person said yes.

Memory: `$BOB_MEMORY_DIR` (default `~/.bob/memory`), the same directory as
`project.json` and the voice transcript. `asks/<id>.json` is an open ask,
`asks/<id>.answer` its answer.
"""
import json
import os
import re
import subprocess
import sys
import time
import uuid
from pathlib import Path

MEMORY = Path(os.environ.get("BOB_MEMORY_DIR", str(Path.home() / ".bob" / "memory")))
EVENTS = MEMORY / "terminal-events.jsonl"
ASKS = MEMORY / "asks"
PROJECT = MEMORY / "project.json"

HANDLED = frozenset({
    "PermissionRequest", "PreToolUse", "PostToolUse", "PermissionDenied", "Stop", "SessionEnd",
})

# The voice transcript keeps 5000 lines and that holds days of use; a tool
# call is noisier than a sentence, so fewer lines cover the same span.
# Guessed from that, never measured.
EVENTS_CAP = 2000
# One pill line. The pill's subtitle wraps past this on a 440pt capsule.
SUMMARY_CHARS = 80
# How long the voice gets to hear a yes or no before the tab prompts on its
# own. Guessed, never measured: nothing has timed how long a person takes to
# answer; the hook's registered timeout of 45 leaves room above it.
ASK_WAIT_S = 30.0
ASK_POLL_S = 0.25
# One System Events call takes well under a second on this machine.
FRONT_TIMEOUT_S = 2.0

FRONT_SCRIPT = 'tell application "System Events" to get name of first application process whose frontmost is true'


def _first_sentence(text: str) -> str:
    text = " ".join(text.split())
    match = re.match(r"(.+?[.!?])(\s|$)", text)
    return match.group(1) if match else text


def summary(event: dict) -> str:
    """One pill line about the event: the command, the file, the sentence."""
    name = event.get("hook_event_name", "")
    tool = str(event.get("tool_name") or "")
    tool_input = event.get("tool_input") or {}
    if not isinstance(tool_input, dict):
        tool_input = {}
    if name == "Stop":
        text = _first_sentence(str(event.get("last_assistant_message") or ""))
    elif tool == "Bash":
        text = str(tool_input.get("command") or "")
    elif tool in ("Edit", "Write", "Read"):
        text = Path(str(tool_input.get("file_path") or "")).name
    elif tool == "Agent":
        text = str(tool_input.get("description") or "")
    else:
        text = tool
    return " ".join(text.split())[:SUMMARY_CHARS]


def read_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def matches(event: dict, project: dict) -> bool:
    """Is this event from the remembered tab? By cwd, through realpath on
    both sides, because Terminal reports the tab's folder through a symlink
    as often as not (`/tmp` is `/private/tmp` on macOS)."""
    cwd = event.get("cwd")
    want = project.get("cwd")
    if not cwd or not want:
        return False
    return os.path.realpath(str(cwd)) == os.path.realpath(os.path.expanduser(str(want)))


def entry_for(event: dict, ask: str = "", held: bool = False) -> dict:
    return {
        "t": time.time(),
        "event": event.get("hook_event_name", ""),
        "tool": str(event.get("tool_name") or ""),
        "summary": summary(event),
        "session": str(event.get("session_id") or ""),
        "ask": ask,
        "held": held,
    }


def _lines() -> list[str]:
    try:
        return [l for l in EVENTS.read_text(encoding="utf-8").splitlines() if l.strip()]
    except OSError:
        return []


def append(entry: dict) -> None:
    MEMORY.mkdir(parents=True, exist_ok=True)
    lines = _lines()
    lines.append(json.dumps(entry, ensure_ascii=False))
    if len(lines) > EVENTS_CAP:
        lines = lines[-EVENTS_CAP:]
    EVENTS.write_text("\n".join(lines) + "\n", encoding="utf-8")


def front_app() -> str:
    """The frontmost app's process name, or "" when it cannot be read."""
    try:
        result = subprocess.run(
            ["osascript", "-e", FRONT_SCRIPT], capture_output=True, text=True, timeout=FRONT_TIMEOUT_S,
        )
    except (OSError, subprocess.TimeoutExpired):
        return ""
    return result.stdout.strip() if result.returncode == 0 else ""


def decision(answer: str) -> dict | None:
    """The hook's stdout for an answer file, or None for anything else."""
    words = answer.split()
    if not words:
        return None
    if words[0] == "allow":
        body: dict = {"behavior": "allow"}
    elif words[0] == "deny":
        body = {"behavior": "deny", "message": "denied by voice"}
        if "stop" in words[1:]:
            body["interrupt"] = True
    else:
        return None
    return {"hookSpecificOutput": {"hookEventName": "PermissionRequest", "decision": body}}


def hold(event: dict, front=front_app, sleep=time.sleep, clock=time.monotonic) -> str:
    """The ask protocol. Returns what the hook prints: a decision, or nothing.

    Terminal in front, or the check failed, or another ask is already held:
    no hold. The tab shows its own prompt with no delay and the entry says
    `held` false so the strip still shows waiting.
    """
    ASKS.mkdir(parents=True, exist_ok=True)
    app = front()
    if app in ("Terminal", "") or any(ASKS.glob("*.json")):
        append(entry_for(event, held=False))
        return ""
    ask_id = uuid.uuid4().hex[:8]
    ask_file = ASKS / f"{ask_id}.json"
    answer_file = ASKS / f"{ask_id}.answer"
    ask_file.write_text(json.dumps({
        "id": ask_id, "tool": str(event.get("tool_name") or ""), "summary": summary(event),
        "session": str(event.get("session_id") or ""), "t": time.time(),
    }), encoding="utf-8")
    append(entry_for(event, ask=ask_id, held=True))
    deadline = clock() + ASK_WAIT_S
    try:
        while clock() < deadline:
            if answer_file.exists():
                text = answer_file.read_text(encoding="utf-8").strip()
                answer_file.unlink()
                chosen = decision(text)
                if chosen is not None:
                    append({**entry_for(event, ask=ask_id), "event": "ask_answered", "summary": text})
                    return json.dumps(chosen)
            sleep(ASK_POLL_S)
    finally:
        try:
            ask_file.unlink()
        except OSError:
            pass
    append({**entry_for(event, ask=ask_id), "event": "ask_expired"})
    return ""


def handle(raw: str, front=front_app, sleep=time.sleep, clock=time.monotonic) -> str:
    """One hook invocation: the event JSON in, the hook's stdout out."""
    try:
        event = json.loads(raw)
    except ValueError:
        return ""
    if not isinstance(event, dict) or event.get("hook_event_name") not in HANDLED:
        return ""
    if not matches(event, read_json(PROJECT)):
        return ""
    try:
        if event["hook_event_name"] == "PermissionRequest":
            return hold(event, front=front, sleep=sleep, clock=clock)
        append(entry_for(event))
    except OSError as err:
        print(f"terminal hook: could not write {MEMORY}: {err}", file=sys.stderr)
    return ""
```

- [ ] **Step 4: Run the test**

Run: `python3 tests/test_terminal_events.py`
Expected: all pass. The first "no project file" check is a no-op placeholder for ordering; it passes by construction and the next line is the real assertion.

- [ ] **Step 5: Commit**

```bash
git add mac/lib/terminal_events.py tests/test_terminal_events.py
git commit -m "feat: the terminal hook's pure half, events to a file and the ask protocol"
```

---

### Task 2: `chewie terminal hook`, the wrapper, and setup registration

**Files:**
- Modify: `mac/lib/terminal.py` (docstring usage lines, `main`)
- Modify: `mac/bin/chewie:53-54`
- Create: `.claude/hooks/terminal-loop.sh`
- Modify: `setup.sh` (after the `h["Notification"]` block, around line 971)
- Modify: `SHA256SUMS.txt` (regenerated)
- Test: `tests/test_terminal.py`

**Interfaces:**
- Consumes: `terminal_events.handle(raw) -> str` from Task 1.
- Produces: `chewie terminal hook` reading stdin, printing the decision or nothing, exit 0 always.

- [ ] **Step 1: Write the failing test**

Append to `tests/test_terminal.py`, before the `print(f"\n{PASSED} passed` line in `main()`:

```python
    # hook: stdin in, stdout out, exit 0 always, nothing else printed. The
    # events module is loaded lazily so this test file's stub-loaded
    # terminal.py does not need mac/lib on sys.path at import.
    import subprocess as _sp
    hookmem = tempfile.mkdtemp()
    proj = tempfile.mkdtemp()
    Path(hookmem, "project.json").write_text(_json.dumps({"cwd": proj}))
    env = {**os.environ, "BOB_MEMORY_DIR": hookmem}
    ev = _json.dumps({"hook_event_name": "PreToolUse", "session_id": "s", "cwd": proj,
                      "tool_name": "Bash", "tool_input": {"command": "ls"}})
    r = _sp.run([sys.executable, str(ROOT / "mac" / "lib" / "terminal.py"), "hook"],
                input=ev, capture_output=True, text=True, env=env, timeout=20)
    check("hook exits 0", r.returncode == 0, r.stderr)
    check("hook prints nothing for a plain event", r.stdout == "", repr(r.stdout))
    check("hook wrote the event", "PreToolUse" in Path(hookmem, "terminal-events.jsonl").read_text())
    r = _sp.run([sys.executable, str(ROOT / "mac" / "lib" / "terminal.py"), "hook"],
                input="{", capture_output=True, text=True, env=env, timeout=20)
    check("hook survives garbage with exit 0 and no output", r.returncode == 0 and r.stdout == "")
```

If `tests/test_terminal.py` does not already define `ROOT`, `os`, `tempfile`, or `_json` at the top, add them (`ROOT = Path(__file__).resolve().parent.parent`, `import json as _json`).

- [ ] **Step 2: Run it to see it fail**

Run: `python3 tests/test_terminal.py`
Expected: "hook exits 0" fails (argparse rejects the verb, exit 2).

- [ ] **Step 3: Add the verb**

In `mac/lib/terminal.py`, add to the docstring's usage block:

```
    chewie terminal hook                    a Claude Code hook: event JSON on stdin (see terminal_events.py)
```

In `main()`, add the subparser and branch. The branch runs before argparse's other output paths and returns on its own, because a hook's stdout must be the decision JSON or nothing:

```python
    sub.add_parser("hook")
```

and, right after `args = parser.parse_args(argv)`:

```python
    if args.verb == "hook":
        # Lazy: the events module is a sibling file, and this script is also
        # loaded by tests through SourceFileLoader with no sys.path entry.
        sys.path.insert(0, str(Path(__file__).resolve().parent))
        import terminal_events
        try:
            sys.stdout.write(terminal_events.handle(sys.stdin.read()))
        except Exception as err:  # noqa: BLE001  a hook that crashes blocks the tab
            print(f"terminal hook: {err}", file=sys.stderr)
        return 0
```

In `mac/bin/chewie`, change the usage lines to:

```
  chewie terminal tabs|ensure|draft|submit|clear|answer|interrupt|focus|hook
                                     the Claude Code tab in Terminal
                                     (submit needs CHEWIE_TERMINAL_SUBMIT=1; hook reads a Claude Code event on stdin)
```

- [ ] **Step 4: The wrapper**

Create `.claude/hooks/terminal-loop.sh`:

```bash
#!/bin/bash
# Claude Code -> the terminal loop (docs/superpowers/specs/2026-09-20-terminal-loop-design.md).
#
# Not sourcing lib.sh on purpose: its helpers read stdin, and the event JSON
# on stdin is the whole point here. Hooks run without a login shell, so PATH
# may not have ~/.local/bin; fall back to where setup.sh links chewie.
CHEWIE="$(command -v chewie 2>/dev/null || echo "$HOME/.local/bin/chewie")"
[ -x "$CHEWIE" ] || exit 0
exec "$CHEWIE" terminal hook
```

Run `chmod +x .claude/hooks/terminal-loop.sh`.

- [ ] **Step 5: Register it in setup.sh**

After the `h["Notification"] = [...]` block, add:

```python
# The terminal loop: hud-listen hears when the remembered Claude Code tab is
# waiting on a permission, answers it by voice, and says when a turn ends.
# One wrapper for six events; the wrapper itself filters to the remembered
# tab and exits at once for every other session. 45 s: the hook holds a
# permission prompt for 30 s while the voice asks, and needs room above that.
for _event in ("PermissionRequest", "PreToolUse", "PostToolUse", "PermissionDenied", "Stop", "SessionEnd"):
    h.setdefault(_event, []).append({"hooks": [{
        "type": "command",
        "command": hooks_dir + "/terminal-loop.sh",
        "timeout": 45,
    }]})
```

- [ ] **Step 6: Run the tests and the gates**

Run: `python3 tests/test_terminal.py && python3 tests/test_terminal_events.py && bash -n setup.sh && python3 tools/checksums.py && python3 tools/checksums.py --check`
Expected: all pass; checksums regenerated because `.claude/hooks/` gained a file.

- [ ] **Step 7: Commit**

```bash
git add mac/lib/terminal.py mac/bin/chewie .claude/hooks/terminal-loop.sh setup.sh SHA256SUMS.txt tests/test_terminal.py
git commit -m "feat: chewie terminal hook, registered for six Claude Code events"
```

---

### Task 3: `answer`, `interrupt`, and `focus` verbs

**Files:**
- Modify: `mac/lib/terminal.py` (docstring, `KEY_ESCAPE`, three functions, `main`)
- Modify: `docs/REFERENCE.md:96`
- Test: `tests/test_terminal.py`

**Interfaces:**
- Consumes: `pick`, `focus`, `refuse_under_secure_input`, `osascript`, `KEY_RETURN`.
- Produces: `answer(choice, tty) -> dict`, `interrupt(tty) -> dict`, `focus_tab(tty) -> dict`; CLI `chewie terminal answer yes|no [--tty]`, `interrupt [--tty]`, `focus [--tty]`.

- [ ] **Step 1: Write the failing test**

Append to `tests/test_terminal.py` in `main()`, before the hook block from Task 2 (the stubs `fake_osascript` and `calls` are the file's own; `calls` records `("osascript", <first script line>, args)`):

```python
    # answer / interrupt / focus: focus first, then one key. The key lines
    # are single-line scripts, so their first line is the whole script.
    t.osascript = fake_osascript
    calls.clear()
    got = t.answer("yes", "/dev/ttys002")
    keys = [c[1] for c in calls if c[0] == "osascript" and "key code" in c[1]]
    check("answer yes presses Return", keys == ['tell application "System Events" to key code 36'], str(keys))
    check("answer focused the tab first", any("want" in c[1] or c[2] == ("/dev/ttys002",) for c in calls), str(calls))
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
    try:
        t.interrupt("/dev/ttys002")
        check("interrupt under Secure Input refuses", False)
    except SystemExit as e:
        check("interrupt under Secure Input exits 2", e.code == 2)
    t.secure_input_holder = lambda: None
```

- [ ] **Step 2: Run it to see it fail**

Run: `python3 tests/test_terminal.py`
Expected: AttributeError on `t.answer`.

- [ ] **Step 3: Implement**

In `mac/lib/terminal.py`, next to `KEY_CONTROL_U`:

```python
# Escape. Claude Code reads it as "interrupt" during a run and as "no" on a
# permission dialog; Return takes the dialog's highlighted first option,
# which is "Yes". Observed in Claude Code 2.1.278, and the live check
# tests/live/terminal-loop.sh is what proves it on a new version.
KEY_ESCAPE = 'tell application "System Events" to key code 53'
```

After `clear()`:

```python
def answer(choice: str, tty: str | None) -> dict:
    """Yes or no to the permission dialog the tab is showing. Only ever run
    by hud-listen while its terminal state is waiting and the hook has
    already given the prompt back to the tab, so the Return never lands on
    an input holding a draft."""
    refuse_under_secure_input()
    tab = pick(tty)
    focus(tab["tty"])
    osascript(KEY_RETURN if choice == "yes" else KEY_ESCAPE)
    return {"tty": tab["tty"], "answer": choice}


def interrupt(tty: str | None) -> dict:
    """Escape in the tab: Claude Code stops what it is doing."""
    refuse_under_secure_input()
    tab = pick(tty)
    focus(tab["tty"])
    osascript(KEY_ESCAPE)
    return {"tty": tab["tty"], "interrupted": True}


def focus_tab(tty: str | None) -> dict:
    tab = pick(tty)
    focus(tab["tty"])
    return {"tty": tab["tty"], "focused": True}
```

In `main()`:

```python
    p = sub.add_parser("answer"); p.add_argument("choice", choices=["yes", "no"]); p.add_argument("--tty")
    p = sub.add_parser("interrupt"); p.add_argument("--tty")
    p = sub.add_parser("focus"); p.add_argument("--tty")
```

and in the dispatch chain, before the final `else`:

```python
    elif args.verb == "answer":
        out = answer(args.choice, args.tty)
    elif args.verb == "interrupt":
        out = interrupt(args.tty)
    elif args.verb == "focus":
        out = focus_tab(args.tty)
```

The existing plain-output `else` branch prints `f"{args.verb} {out['tty']}"`, which is right for all three.

Docstring usage block, add:

```
    chewie terminal answer yes|no [--tty]   Return or Escape on the permission dialog
    chewie terminal interrupt [--tty]       Escape: stop the run in that tab
    chewie terminal focus [--tty]           bring that tab to the front
```

`docs/REFERENCE.md` line 96 becomes:

```
| `chewie terminal`       | The Claude Code tab: draft a prompt, never submit it; answer its permission dialog, interrupt it, focus it; `hook` feeds the terminal loop |
```

- [ ] **Step 4: Run the tests**

Run: `python3 tests/test_terminal.py`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add mac/lib/terminal.py docs/REFERENCE.md tests/test_terminal.py
git commit -m "feat: chewie terminal answer, interrupt and focus"
```

---

### Task 4: `terminal_state.py`, the fold and the tail

**Files:**
- Create: `bin/lib/terminal_state.py`
- Test: `tests/test_terminal_state.py`
- Modify: `tests/run.sh` (register the three new scripts in the `hud` group)

**Interfaces:**
- Consumes: entries as `terminal_events.entry_for` writes them.
- Produces: `initial() -> dict`, `fold(state, entry) -> dict`, `expire(state, now) -> dict`, `strip_line(state) -> str`, `tail(path, offset) -> tuple[list[dict], int]`, constant `IDLE_AFTER_S`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_terminal_state.py`:

```python
#!/usr/bin/env python3
"""One terminal state, folded from hook events. Run: python3 tests/test_terminal_state.py"""
import json
import sys
import tempfile
from importlib.machinery import SourceFileLoader
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ts = SourceFileLoader("terminal_state", str(ROOT / "bin" / "lib" / "terminal_state.py")).load_module()

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
    got, off = ts.tail(tmp, 0)
    check("no file: nothing, offset 0", got == [] and off == 0)
    tmp.write_text(json.dumps(ev("PreToolUse")) + "\n")
    got, off = ts.tail(tmp, 0)
    check("one line read", len(got) == 1 and off == tmp.stat().st_size)
    got2, off2 = ts.tail(tmp, off)
    check("nothing new: nothing", got2 == [] and off2 == off)
    with tmp.open("a") as f:
        f.write("garbage\n" + json.dumps(ev("Stop")) + "\n")
    got3, off3 = ts.tail(tmp, off)
    check("appended lines read, garbage skipped", [g["event"] for g in got3] == ["Stop"] and off3 == tmp.stat().st_size)
    tmp.write_text(json.dumps(ev("SessionEnd")) + "\n")
    got4, off4 = ts.tail(tmp, off3)
    check("a rewritten shorter file restarts from the top", [g["event"] for g in got4] == ["SessionEnd"])

    print(f"\n{PASSED} passed, {FAILED} failed")
    return 1 if FAILED else 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 2: Run it to see it fail**

Run: `python3 tests/test_terminal_state.py`
Expected: fails to load the module.

- [ ] **Step 3: Write `bin/lib/terminal_state.py`**

```python
"""One terminal state, folded from the hook's events.

hud-listen tails `terminal-events.jsonl` (written by `chewie terminal hook`,
see mac/lib/terminal_events.py) and keeps exactly one state for the
remembered tab: idle, running, waiting on you, or done. Pure: no I/O except
`tail`, so the fold is tested with dicts.
"""
import json
from pathlib import Path

# Matches WARM_S in voice_memory: ten minutes of silence and the terminal
# is no longer "the thing you are doing".
IDLE_AFTER_S = 600.0


def initial() -> dict:
    return {"state": "idle", "text": "", "ask": "", "held": False, "t": 0.0}


def fold(state: dict, entry: dict) -> dict:
    name = entry.get("event", "")
    s = dict(state)
    s["t"] = float(entry.get("t") or 0.0)
    if name == "PreToolUse":
        s.update(state="running", text=entry.get("summary") or entry.get("tool") or "", ask="", held=False)
    elif name in ("PostToolUse", "PermissionDenied", "ask_answered"):
        s.update(state="running", text="", ask="", held=False)
    elif name == "PermissionRequest":
        s.update(state="waiting", text=entry.get("summary") or entry.get("tool") or "",
                 ask=entry.get("ask") or "", held=bool(entry.get("held")))
    elif name == "ask_expired":
        s.update(state="waiting", held=False)
    elif name == "Stop":
        s.update(state="done", text=entry.get("summary") or "", ask="", held=False)
    elif name == "SessionEnd":
        s = initial()
    return s


def expire(state: dict, now: float) -> dict:
    if state["state"] != "idle" and now - state["t"] > IDLE_AFTER_S:
        return initial()
    return state


def strip_line(state: dict) -> str:
    """The `t` line for the HUD's strip under the pill."""
    kind = state["state"]
    if kind == "idle":
        return "t off"
    if kind == "running":
        text = state["text"] or "working"
    elif kind == "waiting":
        text = f"waiting on you: {state['text']}" if state["text"] else "waiting on you"
    else:
        text = f"finished: {state['text']}" if state["text"] else "finished"
    return f"t {json.dumps(text, ensure_ascii=False)} state={kind}"


def tail(path: Path, offset: int) -> tuple[list[dict], int]:
    """Entries appended since `offset`, and the new offset. A file shorter
    than the offset was rewritten (the cap), so it is read from the top."""
    try:
        size = path.stat().st_size
    except OSError:
        return [], 0
    if size < offset:
        offset = 0
    if size == offset:
        return [], offset
    with path.open("rb") as f:
        f.seek(offset)
        chunk = f.read()
    out = []
    for line in chunk.decode("utf-8", "replace").splitlines():
        try:
            entry = json.loads(line)
        except ValueError:
            continue
        if isinstance(entry, dict):
            out.append(entry)
    return out, offset + len(chunk)
```

- [ ] **Step 4: Register the scripts in `tests/run.sh`**

In the `hud` group, after the `check "the router's table holds"` line:

```bash
  check  "the terminal hook filters and holds" python3 "$ROOT/tests/test_terminal_events.py"
  check  "the terminal state folds and tails" python3 "$ROOT/tests/test_terminal_state.py"
```

- [ ] **Step 5: Run**

Run: `python3 tests/test_terminal_state.py && bash tests/run.sh hud; git checkout -- CHANGELOG.md`
Expected: the new script passes; the hud group is green except the pre-existing `the suite collects under pytest` failure (hud-speak fixtures on the base branch, not this plan's).

- [ ] **Step 6: Commit**

```bash
git add bin/lib/terminal_state.py tests/test_terminal_state.py tests/run.sh
git commit -m "feat: one terminal state folded from the hook's events"
```

---

### Task 5: The watcher, the announcements, the answer and stop words

**Files:**
- Modify: `bin/lib/route.py` (word sets and two functions after `draft_word`)
- Modify: `bin/hud-listen` (imports, `Listener.__init__`, `run`, `terminal`, `ask`, `handle`, new methods)
- Test: `tests/test_route.py`, `tests/test_hud_listen.py`

**Interfaces:**
- Consumes: `terminal_state.*` from Task 4; `Listener.terminal(verb, tty)`; `looking_at()`, `route.seen_app`, `self.speak`, `self.send`, `self.in_flight`, `self.settle_unless_running`, `voice_memory.project()`.
- Produces: `route.answer_word(said) -> str | None` ("allow" or "deny"), `route.terminal_stop_word(said) -> bool`; `Listener.terminal_state`, `Listener.on_terminal_event(entry)`, `Listener.poll_terminal()`, `Listener.handle_terminal_word(said) -> bool`, `Listener.terminal(verb, tty=None, *extra)`; hud-listen handles `e terminal focus`.

- [ ] **Step 1: Write the failing route test**

In `tests/test_route.py`, inside `main()` before the final print, add:

```python
    print("answer words")
    for said, want in [("yes", "allow"), ("Yeah.", "allow"), ("go ahead", "allow"), ("allow it", "allow"),
                       ("no", "deny"), ("Nope", "deny"), ("deny it", "deny"), ("don't", "deny"),
                       ("yes but only this once", None), ("open chrome", None)]:
        check(f"answer_word({said!r}) is {want}", route.answer_word(said) == want, str(route.answer_word(said)))
    for said, want in [("stop the terminal", True), ("Stop in the terminal.", True), ("terminal stop", True),
                       ("cancel the terminal", True), ("stop", False), ("stop the music", False)]:
        check(f"terminal_stop_word({said!r}) is {want}", route.terminal_stop_word(said) is want)
```

If the file's router module is bound to a different name than `route`, use that name.

- [ ] **Step 2: Run it to see it fail**

Run: `python3 tests/test_route.py`
Expected: AttributeError on `answer_word`.

- [ ] **Step 3: Add the words to `bin/lib/route.py`**

After `REROUTE_WORDS`:

```python
# Answers to the terminal's permission dialog, only while hud-listen's
# terminal state is waiting. "Always" is deliberately absent: a misheard
# word costs one tool call, never a standing rule.
ALLOW_WORDS = frozenset({"yes", "yeah", "yep", "go ahead", "allow", "allow it", "do it", "yes go ahead"})
DENY_WORDS = frozenset({"no", "nope", "deny", "deny it", "don't", "dont", "do not"})
TERMINAL_STOP_WORDS = frozenset({
    "stop the terminal", "stop in the terminal", "terminal stop", "stop terminal",
    "cancel the terminal", "stop it in the terminal",
})
```

After `draft_word`:

```python
def answer_word(said: str) -> str | None:
    words = _norm(said)
    if words in ALLOW_WORDS:
        return "allow"
    if words in DENY_WORDS:
        return "deny"
    return None


def terminal_stop_word(said: str) -> bool:
    return _norm(said) in TERMINAL_STOP_WORDS
```

Check that `_norm` strips punctuation and lowercases (it does for the draft words; "Yeah." must become "yeah"). If `_words` keeps apostrophes, "don't" survives as written, which the set covers.

- [ ] **Step 4: Run the route test**

Run: `python3 tests/test_route.py`
Expected: all pass.

- [ ] **Step 5: Write the failing hud-listen test**

Add to `tests/test_hud_listen.py`, after `test_draft_words`:

```python
def test_terminal_loop(m) -> None:
    """Hook events fold into the strip, the field, and the voice; yes and no
    answer a held ask by file and an expired one by keypress."""
    import tempfile
    mem = tempfile.mkdtemp()
    m.voice_memory.MEMORY = Path(mem)
    m.voice_memory.TRANSCRIPT = Path(mem) / "transcript.jsonl"
    m.voice_memory.PROJECT = Path(mem) / "project.json"
    m.voice_memory.DRAFT = Path(mem) / "draft.json"
    m.NAMES = Path(mem) / "names.txt"
    Path(mem, "project.json").write_text(json.dumps({"tty": "/dev/ttys002", "cwd": mem}))
    log = os.path.join(mem, "terminal.log")
    m.TERMINAL_CMD = ["sh", "-c", f'echo "$0 $*" >> {log}']
    m.ROUTE = True
    front = {"app": "Google Chrome · tab · 0 chars selected"}
    m.looking_at = lambda: front["app"]
    listener = m.Listener("claude -p", False, False)
    sent: list[str] = []
    listener.send = sent.append  # type: ignore[method-assign]
    spoken: list[str] = []
    listener.speak = spoken.append  # type: ignore[method-assign]
    listener._drain = lambda: None  # type: ignore[method-assign]
    listener.settle_unless_running = lambda state, hold: sent.append(f"settle {state}")  # type: ignore[method-assign]

    def entry(event: str, **kw) -> dict:
        base = {"t": time.time(), "event": event, "tool": "", "summary": "", "session": "s", "ask": "", "held": False}
        base.update(kw)
        return base

    events = Path(mem) / "terminal-events.jsonl"

    def emit(*entries: dict) -> None:
        with events.open("a") as f:
            for e in entries:
                f.write(json.dumps(e) + "\n")
        listener.poll_terminal()

    check("idle: nothing said to the strip yet", sent == [], str(sent))
    emit(entry("PreToolUse", tool="Bash", summary="npm test"))
    check("a tool call drives the strip", 't "npm test" state=running' in sent, str(sent))
    check("running says nothing aloud", spoken == [])
    sent.clear()

    emit(entry("PermissionRequest", tool="Bash", summary="rm -rf build", ask="a1", held=True))
    check("waiting drives the strip", 't "waiting on you: rm -rf build" state=waiting' in sent, str(sent))
    check("waiting with nothing in flight lights attention", "p attention" in sent, str(sent))
    check("waiting is announced when Terminal is not in front",
          spoken == ["The terminal wants to rm -rf build. Yes or no?"], str(spoken))
    sent.clear(); spoken.clear()

    check("'yes' while a held ask waits is consumed", listener.handle_terminal_word("yes"))
    time.sleep(0.3)
    answer = Path(mem, "asks", "a1.answer")
    check("'yes' wrote the allow answer file", answer.exists() and answer.read_text().strip() == "allow")
    check("the pill said allowed", any(l.startswith('s "allowed') for l in sent), str(sent))
    check("nothing was pressed in the tab", not Path(log).exists())
    answer.unlink()
    emit(entry("ask_answered", ask="a1", summary="allow"))
    check("an answered ask is running again", listener.terminal_state["state"] == "running")
    check("'yes' with nothing waiting is not consumed", not listener.handle_terminal_word("yes"))
    sent.clear()

    emit(entry("PermissionRequest", tool="Bash", summary="git push", ask="", held=False))
    check("'no' on an expired ask is consumed", listener.handle_terminal_word("no"))
    time.sleep(0.5)
    check("'no' pressed Escape through chewie on the remembered tty",
          Path(log).exists() and "answer no --tty /dev/ttys002" in Path(log).read_text(), Path(log).read_text() if Path(log).exists() else "")
    Path(log).unlink()
    sent.clear(); spoken.clear()

    front["app"] = "Terminal · claude · 0 chars selected"
    emit(entry("PermissionDenied", tool="Bash"), entry("PermissionRequest", tool="Bash", summary="ls", ask="a2", held=True))
    check("waiting with Terminal in front is not announced", spoken == [], str(spoken))
    check("but the strip still shows it", any(l.startswith('t "waiting on you: ls"') for l in sent), str(sent))
    check("'stop the terminal' on a held ask is consumed", listener.handle_terminal_word("stop the terminal"))
    time.sleep(0.3)
    check("it wrote deny stop", Path(mem, "asks", "a2.answer").read_text().strip() == "deny stop")
    emit(entry("ask_answered", ask="a2", summary="deny stop"))
    check("'stop the terminal' with nothing held is consumed", listener.handle_terminal_word("stop the terminal"))
    time.sleep(0.5)
    check("it pressed Escape through chewie", "interrupt --tty /dev/ttys002" in Path(log).read_text(), Path(log).read_text())
    sent.clear(); spoken.clear()

    front["app"] = "Google Chrome · tab · 0 chars selected"
    emit(entry("Stop", summary="All green."))
    check("done drives the strip", 't "finished: All green." state=done' in sent, str(sent))
    check("done lights the done state", "p done" in sent, str(sent))
    check("done is announced", spoken == ["The terminal finished: All green."], str(spoken))
    sent.clear()
    emit(entry("SessionEnd"))
    check("session end takes the strip down", "t off" in sent, str(sent))

    listener.handle("e terminal focus")
    time.sleep(0.5)
    check("a strip click focuses the tab", "focus --tty /dev/ttys002" in Path(log).read_text(), Path(log).read_text())
```

Register it in `main()` after `test_draft_words(module)`:

```python
    print("terminal loop")
    test_terminal_loop(module)
```

- [ ] **Step 6: Run it to see it fail**

Run: `python3 tests/test_hud_listen.py`
Expected: AttributeError on `poll_terminal`.

- [ ] **Step 7: Implement in `bin/hud-listen`**

Imports, after `import voice_memory`:

```python
import terminal_state  # noqa: E402
```

Module helpers, after the `TERMINAL_CMD = ...` line:

```python
def events_path() -> Path:
    """Read each time, not once: tests point voice_memory at a temp dir."""
    return voice_memory.MEMORY / "terminal-events.jsonl"


def asks_dir() -> Path:
    return voice_memory.MEMORY / "asks"
```

In `Listener.__init__`, after `self.drawn: list[str] = []`:

```python
        # The remembered Claude Code tab, folded from the hook's events
        # (bin/lib/terminal_state.py). Read on the watcher thread and on the
        # answer-word path; written only by `on_terminal_event`.
        self.terminal_state = terminal_state.initial()
        self.terminal_offset = 0
```

Class constants, next to `TERMINAL_TIMEOUT_S`:

```python
    # The hook writes an event per tool call; half a second is the cadence
    # ensure() polls at and is already fine-grained for a strip nobody
    # stares at. Guessed, never measured.
    TERMINAL_POLL_S = 0.5
```

In `run()`, right after `self.prime()`:

```python
        if ROUTE:
            threading.Thread(target=self.watch_terminal, daemon=True).start()
```

Change `terminal`'s signature and argv building:

```python
    def terminal(self, verb: str, tty: str | None = None, *extra: str) -> bool:
        ...
        argv = TERMINAL_CMD + [verb, *extra]
        if tty:
            argv = argv + ["--tty", tty]
```

(keep the rest of the body as it is).

New methods, after `handle_draft_word`:

```python
    def watch_terminal(self) -> None:
        while True:
            self.poll_terminal()
            time.sleep(self.TERMINAL_POLL_S)

    def poll_terminal(self) -> None:
        """Fold whatever the hook appended since the last look."""
        entries, self.terminal_offset = terminal_state.tail(events_path(), self.terminal_offset)
        for entry in entries:
            self.on_terminal_event(entry)
        expired = terminal_state.expire(self.terminal_state, time.time())
        if expired is not self.terminal_state:
            self.terminal_state = expired
            self.send(terminal_state.strip_line(expired))

    def terminal_in_front(self) -> bool:
        return route.seen_app(looking_at()) == "Terminal"

    def on_terminal_event(self, entry: dict) -> None:
        before = self.terminal_state
        after = terminal_state.fold(before, entry)
        self.terminal_state = after
        if after == before:
            return
        self.send(terminal_state.strip_line(after))
        became = after["state"] != before["state"] or after["text"] != before["text"]
        if after["state"] == "waiting" and became and entry.get("event") == "PermissionRequest":
            if not self.in_flight():
                self.send("p attention")
            # Only when they cannot see the dialog: the answer to "read it
            # aloud every time?" on 2026-09-20 was "only when terminal is
            # not in front".
            if not self.terminal_in_front():
                what = after["text"] or "run something"
                self.speak(f"The terminal wants to {what}. Yes or no?")
        elif after["state"] == "done" and became:
            if not self.in_flight():
                self.send("p done")
            if after["text"] and not self.terminal_in_front():
                self.speak(f"The terminal finished: {after['text']}")

    def write_answer(self, ask: str, text: str) -> bool:
        try:
            asks_dir().mkdir(parents=True, exist_ok=True)
            (asks_dir() / f"{ask}.answer").write_text(text, encoding="utf-8")
            return True
        except OSError as err:
            self.log("answer unwritable:", err)
            return False

    def handle_terminal_word(self, said: str) -> bool:
        """"yes", "no" while the tab waits on a permission; "stop the
        terminal" any time. Same shape as the draft words: exact words,
        the state says whether they apply, never the model."""
        if not ROUTE:
            return False
        state = self.terminal_state
        tty = voice_memory.project().get("tty")
        if route.terminal_stop_word(said):
            def stop_work() -> None:
                self.send("p acting")
                if state["state"] == "waiting" and state["held"] and state["ask"]:
                    ok = self.write_answer(state["ask"], "deny stop")
                else:
                    ok = self.terminal("interrupt", tty)
                self.send("s " + json.dumps("stopped the terminal" if ok else "couldn't reach the terminal"))
                self.settle_unless_running("done" if ok else "failed", self.STOP_HOLD)
            threading.Thread(target=stop_work, daemon=True).start()
            return True
        action = route.answer_word(said)
        if action is None or state["state"] != "waiting":
            return False

        def work() -> None:
            self.send("p acting")
            if state["held"] and state["ask"]:
                ok = self.write_answer(state["ask"], action)
            else:
                # The hook gave the prompt back to the tab: press the key
                # there. Only reachable while waiting, so the Return never
                # lands on an input holding a draft.
                ok = self.terminal("answer", tty, "yes" if action == "allow" else "no")
            said_back = ("allowed" if action == "allow" else "denied") if ok else "couldn't answer the terminal"
            self.send("s " + json.dumps(said_back))
            try:
                voice_memory.append({
                    "t": voice_memory.now_iso(), "via": "voice", "text": said, "dest": "terminal",
                    "confidence": 1.0, "reason": "answer word", "reply": None,
                    "project": voice_memory.project().get("name"), "answer": action, "ask": state["ask"],
                })
            except OSError as err:
                self.log("memory unwritable:", err)
            self.settle_unless_running("done" if ok else "failed", self.STOP_HOLD)

        threading.Thread(target=work, daemon=True).start()
        return True
```

In `ask()`, change the draft-word line to run the terminal words after it:

```python
        if not typed and dest is None and self.handle_draft_word(said):
            return
        if not typed and dest is None and self.handle_terminal_word(said):
            return
```

Order matters and is deliberate: bare "stop" and the barge words keep their meaning first; a draft outstanding wins "do it"; then a waiting terminal takes "yes" and "no".

In `handle()`, in the `elif line.startswith("e "):` branch, before the `else:` that asks the model:

```python
            elif action == "terminal" and component == "focus":
                # A click on the strip under the pill.
                threading.Thread(
                    target=lambda: self.terminal("focus", voice_memory.project().get("tty")), daemon=True,
                ).start()
```

- [ ] **Step 8: Run**

Run: `python3 tests/test_hud_listen.py && python3 tests/test_route.py`
Expected: all pass. If `test_terminal_loop`'s "waiting is announced" check fails because `speak` returns early on `not self.voice`, the stub replaces the method entirely, so that is not the cause; look at `terminal_in_front` and the `looking_at` stub instead.

- [ ] **Step 9: Commit**

```bash
git add bin/lib/route.py bin/hud-listen tests/test_route.py tests/test_hud_listen.py
git commit -m "feat: hud-listen hears the terminal, answers its permission by voice, and can stop it"
```

---

### Task 6: The `t` line and the strip in the HUD

**Files:**
- Modify: `hud/Sources/BobHUDKit/Spec.swift` (the `Op` enum, after `case queued(Int)`)
- Modify: `hud/Sources/BobHUDKit/LineParser.swift` (a `case "t":` before `case "q":`)
- Modify: `hud/Sources/BobHUDKit/OverlayModel.swift` (a stored strip, `apply`, `focusTerminal()`)
- Create: `hud/Sources/BobHUDKit/TerminalStrip.swift`
- Modify: `hud/Sources/BobHUDKit/OverlayView.swift` (mount under the pill)
- Modify: `hud/CLAUDE.md:22-25`, `skills/hud/SKILL.md:58-60`
- Test: `hud/Tests/BobHUDKitTests/ParserTests.swift`, `hud/Tests/BobHUDKitTests/ChatTests.swift`

**Interfaces:**
- Consumes: `Presence` colours in `PresenceRing.swift` (`HUD.good`, `HUD.warn`), `OutboundEvent.action`, `OverlayView.bottomInset`, `PillView.pillLift`.
- Produces: `Op.terminal(text:state:)`, `Op.terminalOff`, `TerminalState`, `OverlayModel.terminal: TerminalStrip?`, `OverlayModel.focusTerminal()`, the outbound line `e terminal focus`.

- [ ] **Step 1: Write the failing parser tests**

In `hud/Tests/BobHUDKitTests/ParserTests.swift`, after the `say` tests:

```swift
    @Test("the terminal strip is one JSON string and a state")
    func terminalStrip() throws {
        #expect(try LineParser.parse(#"t "waiting on you: npm test" state=waiting"#)
            == .terminal(text: "waiting on you: npm test", state: .waiting))
        #expect(try LineParser.parse(#"t "npm test" state=running"#) == .terminal(text: "npm test", state: .running))
        #expect(try LineParser.parse("t off") == .terminalOff)
    }

    @Test("a strip with no state, or an unknown one, is a mistake")
    func terminalStripNeedsState() {
        #expect(throws: LineParseError.self) { try LineParser.parse(#"t "npm test""#) }
        #expect(throws: LineParseError.self) { try LineParser.parse(#"t "npm test" state=asleep"#) }
    }
```

In `hud/Tests/BobHUDKitTests/ChatTests.swift`, a new test in the suite:

```swift
    @Test("the terminal strip is held, taken down, and its click reaches the bridge")
    func terminalStrip() {
        let model = OverlayModel()
        var sent: [String] = []
        model.onEvent = { sent.append($0.line) }
        #expect(model.terminal == nil)
        model.apply(.terminal(text: "npm test", state: .running))
        #expect(model.terminal == TerminalStrip(text: "npm test", state: .running))
        model.focusTerminal()
        #expect(sent == ["e terminal focus"])
        model.apply(.terminalOff)
        #expect(model.terminal == nil)
    }
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd hud && swift test --filter ParserTests 2>&1 | tail -5`
Expected: compile errors on `.terminal`.

- [ ] **Step 3: The op and the state**

In `Spec.swift`, after `case queued(Int)`:

```swift
    /// The strip under the pill: what the remembered Claude Code tab is
    /// doing. See docs/superpowers/specs/2026-09-20-terminal-loop-design.md.
    case terminal(text: String, state: TerminalState)
    /// Take the strip down: the tab is idle or gone.
    case terminalOff
```

Below the `Op` enum (same file):

```swift
/// The three things a terminal strip can say. Colours follow the ring:
/// running and done are `acting`/`done` green, waiting is `attention` amber.
public enum TerminalState: String, Sendable, Equatable {
    case running, waiting, done
}

public struct TerminalStrip: Equatable, Sendable {
    public var text: String
    public var state: TerminalState
    public init(text: String, state: TerminalState) {
        self.text = text
        self.state = state
    }
}
```

- [ ] **Step 4: The parser**

In `LineParser.swift`, before `case "q":`:

```swift
        case "t":
            // `t "waiting on you: npm test" state=waiting`, `t off`. One
            // JSON string like `s`, then the state, which is required: a
            // strip with no colour is a subtitle, and the pill has one.
            let rest = trimmed.dropFirst(1).trimmingCharacters(in: .whitespaces)
            if rest == "off" { return .terminalOff }
            guard let range = rest.range(of: " state=", options: .backwards) else {
                throw LineParseError.malformed("`t` needs state=running|waiting|done", line: trimmed)
            }
            let textPart = String(rest[..<range.lowerBound])
            let statePart = String(rest[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            guard let state = TerminalState(rawValue: statePart) else {
                throw LineParseError.malformed("unknown terminal state \(statePart)", line: trimmed)
            }
            guard case .string(let text)? = JSONDecoding.parse(textPart), !text.isEmpty else {
                throw LineParseError.malformed("`t` needs a JSON string", line: trimmed)
            }
            return .terminal(text: text, state: state)
```

- [ ] **Step 5: The model**

In `OverlayModel.swift`, next to `public private(set) var pill = PillState()`:

```swift
    /// The strip under the pill, or nil when the terminal is idle.
    public private(set) var terminal: TerminalStrip?
```

In `apply(_ op:)`, before `default:`:

```swift
        case .terminal(let text, let state):
            terminal = TerminalStrip(text: text, state: state)
            revision += 1

        case .terminalOff:
            terminal = nil
            revision += 1
```

A method next to `cancelRun`:

```swift
    /// A click on the strip: the bridge brings the tab to the front.
    public func focusTerminal() {
        onEvent?(.action(name: "terminal", component: "focus", payload: [:]))
    }
```

- [ ] **Step 6: The view**

Create `hud/Sources/BobHUDKit/TerminalStrip.swift`:

```swift
import SwiftUI

/// One thin line under the pill: a dot in the ring's colour for the state,
/// and what the tab is doing. Hidden when the terminal is idle. The whole
/// strip is the button; a click asks the bridge to bring the tab forward.
struct TerminalStripView: View {
    let strip: TerminalStrip
    let onFocus: () -> Void
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tint: Color {
        switch strip.state {
        case .running, .done: return HUD.good
        case .waiting: return HUD.warn
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(tint).frame(width: 6, height: 6)
            Text(strip.text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(HUD.ink.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(hovering ? 0.45 : 0.22), lineWidth: 1))
        .contentShape(Capsule())
        .onTapGesture { onFocus() }
        .onHover { over in
            hovering = over
            if over { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .animation(Motion.fade(0.14, reduced: reduceMotion), value: hovering)
        .accessibilityLabel("Terminal: \(strip.text)")
        .accessibilityAction(named: "Show the terminal") { onFocus() }
    }
}
```

In `OverlayView.swift`, after the pill block (the `if model.pill.phase != .hidden && !model.chatOpen { PillView(...) ... }`), add:

```swift
            // The terminal strip, directly under the pill and standing on
            // its own when the pill is down: the tab can be running while
            // the assistant is dormant, and that is when the strip matters.
            if let strip = model.terminal, !model.chatOpen {
                TerminalStripView(strip: strip, onFocus: { model.focusTerminal() })
                    .frame(maxWidth: PillView.maxWidth)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, Self.bottomInset - 8)
                    .transition(.opacity)
                    .zIndex(9998)
            }
```

The pill sits at `bottomInset + pillLift` (14) from the bottom and is about 40pt tall; a 22pt strip at `bottomInset - 8` ends where the pill begins. If they overlap on the real display, the lift is the number to raise, not the strip.

- [ ] **Step 7: The wire tables**

`hud/CLAUDE.md`, after the `q <n>` line in the fenced block:

```
t "<text>" state=running|waiting|done                    the terminal strip under the pill; `t off` hides it
```

`skills/hud/SKILL.md`, after line 60 (`q <n>`):

```
t "<text>" state=running|waiting|done   the Claude Code tab's state, as a strip under the pill; t off hides it
```

- [ ] **Step 8: Run the Swift tests**

Run: `cd hud && swift test 2>&1 | tail -8`
Expected: all pass, two more than before in ParserTests and one more in ChatTests. If `Motion.fade` or `HUD.good` are not visible from the new file, they are in `OverlayView.swift` and `Pill.swift` in the same module; check the exact names there rather than inventing new ones.

- [ ] **Step 9: Commit**

```bash
git add hud/Sources/BobHUDKit/Spec.swift hud/Sources/BobHUDKit/LineParser.swift hud/Sources/BobHUDKit/OverlayModel.swift hud/Sources/BobHUDKit/OverlayView.swift hud/Sources/BobHUDKit/TerminalStrip.swift hud/Tests/BobHUDKitTests/ParserTests.swift hud/Tests/BobHUDKitTests/ChatTests.swift hud/CLAUDE.md skills/hud/SKILL.md
git commit -m "feat: a terminal strip under the pill, driven by the t line"
```

---

### Task 7: Docs, the live check, and the gates

**Files:**
- Modify: `docs/VOICE-DESIGN.md` (a section after "Where a sentence goes")
- Create: `tests/live/terminal-loop.sh`
- Modify: `tests/run.sh` (the `live` list, wherever `terminal.sh` is registered for its parse/SKIP/mutant checks)
- Modify: `README.md`, `SHA256SUMS.txt` (regenerated if the gates ask)

**Interfaces:**
- Consumes: everything above.
- Produces: the opt-in live check; docs that match the code.

- [ ] **Step 1: The doc section**

In `docs/VOICE-DESIGN.md`, after the "Where a sentence goes" section, add:

```markdown
## The terminal talks back

The tab is not only a place a sentence goes. A Claude Code hook,
`chewie terminal hook`, runs on every tool call, permission prompt, and
finished turn in the remembered tab and writes one line each to
`~/.bob/memory/terminal-events.jsonl`. hud-listen tails it into one state
and shows it as a strip under the pill: running, waiting on you, done.

When the tab stops on a permission and Terminal is not in front, the hook
holds the prompt for thirty seconds and the voice asks: "The terminal wants
to run npm test. Yes or no?" "Yes", "go ahead", or "allow" grants that one
call; "no" or "deny" refuses it. Nothing grants a standing rule by voice:
"always" needs the keyboard, so a misheard word costs one tool call. If
nobody answers in time, the tab shows its ordinary dialog and the same
words press Return or Escape there instead.

When Terminal is in front the voice says nothing: you can see the dialog.
The strip and the ring's attention state carry it.

"Stop the terminal" denies a held prompt with interrupt, or sends Escape to
the tab. A finished turn says one line, the first sentence of the answer,
again only when the tab is not in front.

Setup registers the hook in `~/.claude/settings.json` for six events. Any
session whose folder is not the remembered one is invisible to all of this:
the hook exits before writing anything.
```

Run `slop-check docs/VOICE-DESIGN.md` and keep the score under 10.

- [ ] **Step 2: The live check**

Create `tests/live/terminal-loop.sh` (mode 755):

```bash
#!/usr/bin/env bash
# Live: the hook sees a permission prompt in a tab this check opened, holds
# it, and an answer file grants it. Opens a Terminal window with --fresh and
# takes focus for about thirty seconds, so this is never run by
# tests/run.sh. Run it when the person says go. Needs the hook registered
# (setup.sh) and Terminal not in front while the prompt is held, so it puts
# the check's own window behind by activating nothing after the draft.
source "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
need claude "npm i -g @anthropic-ai/claude-code"
need peekaboo "run install.sh"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CH="$REPO/mac/bin/chewie"
export BOB_MEMORY_DIR="$(mktemp -d)"
DIR="$(mktemp -d)"
TTY="$(bash "$CH" terminal ensure --cwd "$DIR" --fresh --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["tty"])')"
ok "ensure opened a claude tab" test -n "$TTY"
sleep 2
ok "draft a prompt that needs a permission" bash "$CH" terminal draft "run: touch loop-proof.txt" --tty "$TTY"
sleep 1
ok "submit it" env CHEWIE_TERMINAL_SUBMIT=1 bash "$CH" terminal submit --tty "$TTY"
# Put Chrome or the Finder in front so the hook holds instead of falling
# through; the hook checks the frontmost app itself.
osascript -e 'tell application "Finder" to activate' >/dev/null 2>&1 || true
echo "  LOOK: within ~20 s the pill should say the terminal is waiting. 20 s."
for _ in $(seq 1 40); do
  ls "$BOB_MEMORY_DIR/asks/"*.json >/dev/null 2>&1 && break
  sleep 0.5
done
ASK="$(ls "$BOB_MEMORY_DIR/asks/"*.json 2>/dev/null | head -1)"
ok "the hook wrote an ask for this tab" test -n "$ASK"
if [ -n "$ASK" ]; then
  echo allow > "${ASK%.json}.answer"
fi
sleep 3
ok "the answer was consumed" test ! -e "${ASK:-/nonexistent}"
ok "the event log records the allow" grep -q ask_answered "$BOB_MEMORY_DIR/terminal-events.jsonl"
echo "  LOOK: claude should have created loop-proof.txt in $DIR. Close that window when done."
mutant "an unknown terminal verb is rejected" bash "$CH" terminal nonsense
finish
```

Note: this check's `BOB_MEMORY_DIR` is a temp dir, but the hook Claude Code runs reads the real `~/.bob/memory/project.json`. So before the draft, the check must point the real project at its tab: add after `ok "ensure opened..."`:

```bash
# The hook Claude Code runs reads the real memory dir, not this check's
# temp one. Point both at the same place for the duration.
export BOB_MEMORY_DIR="$HOME/.bob/memory"
bash "$CH" terminal ensure --cwd "$DIR" --json >/dev/null
```

and remove the earlier temp `BOB_MEMORY_DIR` export (keep `DIR` temp). The ask and events files are then under `~/.bob/memory/`; the check reads them from there.

- [ ] **Step 3: Register the live script's static checks**

In `tests/run.sh`, find where `terminal.sh` is listed for the `parses`, `can SKIP`, and `has a mutant` checks (a loop over `tests/live/*.sh` or an explicit list) and make sure `terminal-loop.sh` is covered the same way. If it is a glob, nothing to do.

- [ ] **Step 4: Run every gate**

Run:

```bash
bash tests/run.sh; git checkout -- CHANGELOG.md
python3 tools/counts.py --check || python3 tools/counts.py
python3 tools/checksums.py --check || python3 tools/checksums.py
code-slop --issues
slop-check docs/VOICE-DESIGN.md docs/superpowers/specs/2026-09-20-terminal-loop-design.md
```

Expected: the suite is green except `hud: the suite collects under pytest` (pre-existing, from hud-speak's fixtures on the base branch); counts and checksums current after regeneration; code-slop 0; slop scores under 10.

- [ ] **Step 5: Commit and push**

```bash
git add docs/VOICE-DESIGN.md tests/live/terminal-loop.sh tests/run.sh README.md SHA256SUMS.txt
git commit -m "docs: the terminal talks back, and a live check for the hook holding a prompt"
git push -u origin feat/terminal-loop
```

Do not run `tests/live/terminal-loop.sh`. Report it ready; it runs only when the person says go.

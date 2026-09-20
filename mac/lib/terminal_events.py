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
# Guessed, never measured: fast enough that an answer lands within a quarter
# second of being written, slow enough that 30 s of polling is 120 stats.
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

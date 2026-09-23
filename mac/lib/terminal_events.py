#!/usr/bin/env python3
"""Claude Code's hooks, folded into the terminal loop.

`chewie terminal hook` runs this on every registered event (PermissionRequest,
PreToolUse, PostToolUse, PermissionDenied, Stop, SessionEnd). It keeps only
events from the tab `project.json` remembers, appends one line per event to
`terminal-events.jsonl` for hud-listen to tail, and on a permission prompt
holds the prompt while the voice asks.

Every session, whatever its folder, also gets a line in `agent-events.jsonl`:
that is the board bin/lib/agent_board.py folds, so one voice can see and run
many agents. Only the remembered tab's prompts are ever held. Each board line
carries the Terminal tty the session runs on (found once per session, see
`session_tty`) and its transcript path, which is where the board reads the
session's title.

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
AGENT_EVENTS = MEMORY / "agent-events.jsonl"
ASKS = MEMORY / "asks"
TTYS = MEMORY / "agent-ttys"
PROJECT = MEMORY / "project.json"

HANDLED = frozenset({
    "PermissionRequest", "PreToolUse", "PostToolUse", "PermissionDenied", "Stop", "SessionEnd",
})

# The file is append-only and rotates by size, because hud-listen tails it by
# byte offset: a rewrite that dropped the oldest lines shifted every byte
# after it, and the reader either replayed the whole log or read a fragment
# and lost the entry it was sitting on. 400 KB is about 2000 entries, which is
# the span the old line cap aimed at: a measured entry with a Bash summary and
# a uuid session is 190 bytes, and one with a full 80-character summary is
# 232, so 2000 x 200 = 400 KB. The line count was guessed from the voice
# transcript's 5000; the bytes are measured, the span still is not.
EVENTS_MAX_BYTES = 400_000
# One pill line. The pill's subtitle wraps past this on a 440pt capsule.
SUMMARY_CHARS = 80
# How long the voice gets to hear a yes or no before the tab prompts on its
# own. Guessed, never measured: nothing has timed how long a person takes to
# answer; the hook's registered timeout of 45 leaves room above it.
ASK_WAIT_S = 30.0
# Guessed, never measured: fast enough that an answer lands within a quarter
# second of being written, slow enough that 30 s of polling is 120 stats.
ASK_POLL_S = 0.25
# The `timeout` setup.sh registers this hook with. Claude Code kills the hook
# at that point and hold()'s finally never runs, so anything still on disk
# after ASK_WAIT_S plus this long belongs to a hook that is gone.
HOOK_TIMEOUT_S = 45.0
# One System Events call takes well under a second on this machine.
FRONT_TIMEOUT_S = 2.0

# Hops from the hook up to the claude process that ran it. Counted from the
# scripts on 2026-09-23, not observed live: python under chewie (bash) under
# terminal-loop.sh under claude is four, five if Claude Code wraps hooks in a
# shell. Eight leaves room for that without walking up to launchd.
TTY_HOPS = 8
# A session's cached tty outlives the session by this much, then the next
# first-sight write clears it. Guessed, never measured: a day is well past
# agent_board.STALE_AFTER_S, so a file is never cleared under a live session.
TTY_KEEP_S = 86400.0
SESSION_ID = re.compile(r"[0-9A-Za-z-]{1,64}")

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
        "cwd": str(event.get("cwd") or ""),
        "transcript": str(event.get("transcript_path") or ""),
        "ask": ask,
        "held": held,
    }


def tty_of_claude(start: int, table: str) -> str:
    """The tty of the nearest `claude` above `start` in a `ps -A -o
    pid=,ppid=,tty=,comm=` table, as `/dev/ttysNNN`, or "" when that claude
    has no terminal (`claude -p` under hud-listen, the desktop app) or none
    is found within TTY_HOPS."""
    rows = {}
    for line in table.splitlines():
        parts = line.split(None, 3)
        if len(parts) == 4 and parts[0].isdigit() and parts[1].isdigit():
            rows[int(parts[0])] = (int(parts[1]), parts[2], parts[3].strip())
    pid = start
    for _ in range(TTY_HOPS):
        row = rows.get(pid)
        if row is None:
            return ""
        ppid, tty, comm = row
        if Path(comm).name == "claude":
            return "" if tty in ("??", "-", "") else f"/dev/{tty}"
        pid = ppid
    return ""


def session_tty(session: str, ps=None) -> str:
    """Which Terminal tab this session is in, so the voice can type into it.

    Hooks run with no controlling terminal (`/dev/tty` fails with ENXIO), so
    the tty is read off the claude process above this one. That is one `ps`,
    paid on the session's first event only: the answer, empty or not, is
    cached in `agent-ttys/<session>`, because every hook sits on the tool
    call's critical path.
    """
    if not SESSION_ID.fullmatch(session):
        return ""
    path = TTYS / session
    try:
        return path.read_text(encoding="utf-8").strip()
    except OSError:
        pass
    if ps is None:
        try:
            ps = subprocess.run(
                ["ps", "-A", "-o", "pid=,ppid=,tty=,comm="], capture_output=True, text=True,
                timeout=FRONT_TIMEOUT_S,
            ).stdout
        except (OSError, subprocess.TimeoutExpired):
            return ""
    tty = tty_of_claude(os.getpid(), ps)
    try:
        TTYS.mkdir(parents=True, exist_ok=True)
        cutoff = time.time() - TTY_KEEP_S
        for old in TTYS.iterdir():
            if old.stat().st_mtime < cutoff:
                old.unlink()
        path.write_text(tty, encoding="utf-8")
    except OSError:
        pass
    return tty


def append(entry: dict, path: Path | None = None) -> None:
    """One line, appended. Never a rewrite.

    Claude Code runs tool calls concurrently and waits on every hook, so this
    is on the critical path: one O_APPEND write of a short line, no read, no
    lock. Past the size cap the whole file is renamed to `<name>.1` and the
    next append starts a fresh one, so the reader sees a new inode rather
    than bytes that moved under it. Only one generation is kept.
    """
    path = path or EVENTS
    MEMORY.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(entry, ensure_ascii=False) + "\n")
    try:
        if path.stat().st_size > EVENTS_MAX_BYTES:
            os.replace(path, path.with_name(path.name + ".1"))
    except OSError:
        pass


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


def live_asks() -> list[Path]:
    """Ask files young enough that a hook could still be holding one.

    Only hold()'s own `finally` removes an ask file, and it does not run when
    the process dies. Claude Code kills the hook at its registered timeout,
    and `clock` is monotonic, which does not advance across system sleep, so
    a lid closed mid-hold outlives the hold. One file left behind used to
    make every later permission prompt fall through to the tab, silently and
    for good. A file with no readable `t` is treated as stale: the field has
    been written since the first version.
    """
    cutoff = time.time() - (ASK_WAIT_S + HOOK_TIMEOUT_S)
    live = []
    for path in ASKS.glob("*.json"):
        try:
            when = float(read_json(path).get("t") or 0.0)
        except (TypeError, ValueError):
            when = 0.0
        if when > cutoff:
            live.append(path)
            continue
        print(f"terminal hook: clearing a stale ask {path.name}", file=sys.stderr)
        try:
            path.unlink()
        except OSError:
            pass
    return live


def hold(event: dict, front=front_app, sleep=time.sleep, clock=time.monotonic) -> str:
    """The ask protocol. Returns what the hook prints: a decision, or nothing.

    Terminal in front, or the check failed, or another ask is already held:
    no hold. The tab shows its own prompt with no delay and the entry says
    `held` false so the strip still shows waiting.
    """
    ASKS.mkdir(parents=True, exist_ok=True)
    app = front()
    if app in ("Terminal", "") or live_asks():
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
                try:
                    text = answer_file.read_text(encoding="utf-8").strip()
                except (OSError, ValueError):
                    # A torn or non-UTF-8 write. UnicodeDecodeError is a
                    # ValueError, so it used to escape hold() entirely and
                    # leave the ask file behind, and that one file then
                    # disabled the ask protocol for every later prompt.
                    text = ""
                try:
                    answer_file.unlink()
                except OSError:
                    pass
                chosen = decision(text)
                if chosen is not None:
                    append({**entry_for(event, ask=ask_id), "event": "ask_answered", "summary": text})
                    return json.dumps(chosen)
                # Nobody is told otherwise: the hold just runs out. The
                # hook's own stderr is where the expiry gets explained.
                print(f"terminal hook: answer {text!r} is not allow or deny", file=sys.stderr)
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
    try:
        tty = session_tty(str(event.get("session_id") or ""))
        append({**entry_for(event), "tty": tty}, AGENT_EVENTS)
    except OSError as err:
        print(f"terminal hook: could not write {AGENT_EVENTS}: {err}", file=sys.stderr)
    if not matches(event, read_json(PROJECT)):
        return ""
    try:
        if event["hook_event_name"] == "PermissionRequest":
            return hold(event, front=front, sleep=sleep, clock=clock)
        append(entry_for(event))
    except OSError as err:
        print(f"terminal hook: could not write {MEMORY}: {err}", file=sys.stderr)
    return ""

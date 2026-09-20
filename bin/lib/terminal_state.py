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

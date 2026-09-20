"""One terminal state, folded from the hook's events.

hud-listen tails `terminal-events.jsonl` (written by `chewie terminal hook`,
see mac/lib/terminal_events.py) and keeps exactly one state for the
remembered tab: idle, running, waiting on you, or done. Pure: no I/O except
`tail`, so the fold is tested with dicts.
"""
import json
import os
from pathlib import Path

# Guessed, never measured: nothing has timed how long a tab sits quiet before
# the strip is stale rather than informative. Ten minutes because it matches
# WARM_S in voice_memory, where the same guess decides when the last project
# stops being "the thing you are doing".
IDLE_AFTER_S = 600.0

# Where a cursor starts: no inode seen yet, no bytes read. See `tail`.
START = (0, 0)


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


def _read(path: Path, offset: int) -> tuple[list[dict], int]:
    """Whole entries after `offset`, and how many bytes were consumed."""
    try:
        with path.open("rb") as f:
            f.seek(offset)
            chunk = f.read()
    except OSError:
        return [], 0
    out = []
    for line in chunk.decode("utf-8", "replace").splitlines():
        try:
            entry = json.loads(line)
        except ValueError:
            continue
        if isinstance(entry, dict):
            out.append(entry)
    return out, len(chunk)


def tail(path: Path, cursor: tuple[int, int]) -> tuple[list[dict], tuple[int, int]]:
    """Entries appended since `cursor`, and the new cursor.

    The cursor is `(inode, offset)`, not a bare offset. The hook appends to
    this file and renames it to `<name>.1` past its size cap, so a bare
    offset cannot tell "nothing new" from "a different file that happens to
    be this long". On a new inode the rotated file is drained from the old
    offset first, so the entries written just before the rename are read
    exactly once rather than lost.

    A file shorter than the offset under the same inode was truncated by
    something other than the hook, and is read from the top.
    """
    ino, offset = cursor
    try:
        st: os.stat_result | None = path.stat()
    except OSError:
        st = None

    if st is None or st.st_ino != ino:
        out = []
        if ino:
            rotated = path.with_name(path.name + ".1")
            try:
                same = rotated.stat().st_ino == ino
            except OSError:
                same = False
            if same:
                drained, _ = _read(rotated, offset)
                out.extend(drained)
        if st is None:
            return out, START
        fresh, read = _read(path, 0)
        return out + fresh, (st.st_ino, read)

    if st.st_size < offset:
        offset = 0
    if st.st_size == offset:
        return [], cursor
    entries, read = _read(path, offset)
    return entries, (ino, offset + read)

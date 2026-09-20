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

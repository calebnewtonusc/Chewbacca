"""Every Claude Code session on the machine, folded from the hook's events.

`terminal_state` keeps one state for the remembered tab. This keeps one per
session, from `agent-events.jsonl`, which the hook writes for every session
whatever its folder. It is what lets one voice run many agents: the board says
who is running, who is waiting on you, who is done, and `pick` asks Jev which
of them a spoken sentence is for.

The option list Jev chooses from is rebuilt from the live board on every call,
never cached: a session that ended a second ago must not be choosable
(Movez, "Jev Engineering" step 06, research/jev-engineering in the brain).
Exact rules stay in code: with one session there is nothing to decide, so Jev
is not called.

A session's topic is the `ai-title` Claude Code writes into its own transcript
("Kyber terminal and agent communication"), read from the transcript's tail.
The folder alone could not tell two sessions in one repo apart: the eval's one
miss, "the heads up display one", was a session the menu only knew as
`Chewbacca`.
"""
import json
import os
import jev
from pathlib import Path

MEMORY = Path(os.environ.get("BOB_MEMORY_DIR", str(Path.home() / ".bob" / "memory")))
EVENTS = MEMORY / "agent-events.jsonl"

# Guessed, never measured: a Claude session can sit waiting on a person for an
# hour and still be live, so the ten minutes terminal_state uses for its strip
# would drop real agents. Two hours of silence with no SessionEnd is taken as
# a window closed without the hook firing.
STALE_AFTER_S = 7200.0
# Measured 2026-09-23 with tests/eval_agent_board_jev.py, four sessions and 20
# hand-labelled sentences: every right pick scored 0.96 or higher, and the
# nearest miss, "Commit everything" (meant for nobody), came back none at 0.57.
# 19/20 right and zero sentences sent to the wrong agent; the one miss ("the
# heads up display one") fell to none, so the voice would ask, not misroute.
PICK_FLOOR = 0.7
# Jev's own 2.5 s timeout is the router's, which answers before anything else
# happens. A picked agent is followed by a model run of 20 s or more, so a
# slower pick costs little and a timed-out one costs a "which one?". Measured
# 2026-09-23 afternoon on the eval's 20 sentences: p50 0.66 s, worst 6.12 s,
# and 4 of 20 timed out at 2.5 s (none misrouted, all fell to asking).
PICK_TIMEOUT_S = 8.0
# One board read never needs more than the tail: 400 KB is the rotation cap
# the hook writes with, so this reads at most one generation.
READ_MAX_BYTES = 400_000
# How far back into a transcript to look for its title. Measured 2026-09-23 on
# eight live transcripts: Claude Code rewrites the `ai-title` line every few
# turns (104 of them in a 9.6 MB transcript, 10 in a 750 KB one), so the
# newest is always well inside the last 256 KB.
TITLE_TAIL_BYTES = 256_000
# A permission prompt older than this is not answered by voice: the dialog
# may be long gone (answered at the keyboard, the run interrupted) and a
# "yes" presses Return in that tab. Guessed, never measured.
ANSWERABLE_S = 900.0


def fold(board: dict, entry: dict) -> dict:
    session = str(entry.get("session") or "")
    if not session:
        return board
    b = dict(board)
    name = entry.get("event", "")
    if name == "SessionEnd":
        b.pop(session, None)
        return b
    s = dict(b.get(session) or {"session": session, "state": "idle", "text": "", "ask": ""})
    cwd = entry.get("cwd") or s.get("cwd") or ""
    s.update(
        cwd=cwd, folder=Path(cwd).name if cwd else "unknown", t=float(entry.get("t") or 0.0),
        tty=entry.get("tty") or s.get("tty") or "",
        transcript=entry.get("transcript") or s.get("transcript") or "",
    )
    if name == "PreToolUse":
        s.update(state="running", text=entry.get("summary") or entry.get("tool") or "", ask="")
    elif name in ("PostToolUse", "PermissionDenied", "ask_answered"):
        s.update(state="running", ask="")
    elif name == "PermissionRequest":
        s.update(state="waiting", text=entry.get("summary") or entry.get("tool") or "", ask=entry.get("ask") or "")
    elif name == "Stop":
        s.update(state="done", text=entry.get("summary") or "", ask="")
    b[session] = s
    return b


def expire(board: dict, now: float) -> dict:
    return {k: v for k, v in board.items() if now - float(v.get("t") or 0.0) <= STALE_AFTER_S}


_titles: dict[str, tuple[tuple[int, int], str]] = {}


def topic_of(transcript: str) -> str:
    """The newest `ai-title` in a transcript's tail, or "". Cached on the
    file's size and mtime, because hud-listen asks on every sentence."""
    if not transcript.endswith(".jsonl"):
        return ""
    path = Path(transcript)
    try:
        st = path.stat()
    except OSError:
        return ""
    stamp = (st.st_size, st.st_mtime_ns)
    hit = _titles.get(transcript)
    if hit and hit[0] == stamp:
        return hit[1]
    title = ""
    try:
        with path.open("rb") as f:
            f.seek(max(0, st.st_size - TITLE_TAIL_BYTES))
            tail = f.read().decode("utf-8", errors="replace")
    except OSError:
        return ""
    for line in reversed(tail.splitlines()):
        if '"ai-title"' not in line:
            continue
        try:
            title = str(json.loads(line).get("aiTitle") or "").strip()
        except ValueError:
            continue
        if title:
            break
    _titles[transcript] = (stamp, title)
    return title


def with_topics(board: dict) -> dict:
    return {k: {**v, "topic": topic_of(v.get("transcript") or "")} for k, v in board.items()}


def typeable(board: dict, exclude: str = "") -> dict:
    """Sessions in a Terminal tab, which is the only kind a sentence can be
    typed into. `exclude` is the caller's own session: hud-listen's model runs
    as a Claude Code session too, with no tab."""
    return {k: v for k, v in board.items() if v.get("tty") and k != exclude}


def answerable(board: dict, now: float, exclude: str = "") -> list[dict]:
    """Sessions whose tab is showing a permission prompt a voice yes can answer."""
    return [s for s in ordered(typeable(board, exclude))
            if s["state"] == "waiting" and now - float(s.get("t") or 0.0) <= ANSWERABLE_S]


def load(path: Path | None = None, now: float | None = None) -> dict:
    import time
    path = path or EVENTS
    board: dict = {}
    try:
        with path.open("rb") as f:
            size = f.seek(0, 2)
            f.seek(max(0, size - READ_MAX_BYTES))
            raw = f.read().decode("utf-8", errors="replace")
    except OSError:
        return board
    lines = raw.splitlines()
    if len(raw) >= READ_MAX_BYTES and lines:
        lines = lines[1:]  # the first line of a mid-file read is a fragment
    for line in lines:
        try:
            entry = json.loads(line)
        except ValueError:
            continue
        if isinstance(entry, dict):
            board = fold(board, entry)
    return with_topics(expire(board, time.time() if now is None else now))


def ordered(board: dict) -> list[dict]:
    """Waiting first (someone is blocked on you), then running, then done."""
    rank = {"waiting": 0, "running": 1, "done": 2, "idle": 3}
    return sorted(board.values(), key=lambda s: (rank.get(s["state"], 4), -float(s.get("t") or 0.0)))


def name(s: dict) -> str:
    """What the voice calls a session: its title, else its folder."""
    return s.get("topic") or s["folder"]


def describe(s: dict, spoken: bool = False) -> str:
    """`spoken` drops what a running session is doing: that is a raw tool
    call ("cd ~/Chewbacca && python3 - <<'EOF'..."), which reads fine on the
    board and is noise read aloud."""
    what = s.get("text") or ""
    who = name(s)
    if s["state"] == "waiting":
        return f"{who} is waiting on you" + (f" to {what}" if what else "")
    if s["state"] == "running":
        return f"{who} is working" + (f": {what}" if what and not spoken else "")
    if s["state"] == "done":
        return f"{who} is done" + (f": {what}" if what else "")
    return f"{who} is idle"


def summary(board: dict) -> str:
    """One spoken line for "what are my agents doing". No model."""
    rows = ordered(board)
    if not rows:
        return "No agents are running."
    head = "One agent" if len(rows) == 1 else f"{len(rows)} agents"
    return head + ". " + ". ".join(describe(s, spoken=True).rstrip(".!? ") for s in rows) + "."


def menu(board: dict) -> tuple[dict, dict]:
    """The Choice criteria for the live board, and option key -> session id.

    Keys are positional (`agent_1`...) because Jev reads the descriptions, not
    the keys; the folder and current work are what let it tell two agents in
    the same repo apart.
    """
    criteria, keys = {}, {}
    for i, s in enumerate(ordered(board), 1):
        key = f"agent_{i}"
        about = f" Its conversation is titled \"{s['topic']}\"." if s.get("topic") else ""
        criteria[key] = (f"The Claude Code session working in the folder `{s['folder']}`.{about} "
                         f"Right now: {describe(s)}.")
        keys[key] = s["session"]
    criteria["none"] = "Not meant for any one of these sessions: talking to the assistant, or about all of them."
    return criteria, keys


def pick(said: str, board: dict, ask=None) -> dict:
    """Which agent is `said` for? Returns {"session", "confidence", "why"}.

    `session` is None when nobody should get it: no agents, Jev unsure, Jev
    down. The caller then asks the person rather than guessing, because a
    sentence typed into the wrong agent is an instruction run in the wrong repo.
    """
    rows = ordered(board)
    if not rows:
        return {"session": None, "confidence": 1.0, "why": "no agents"}
    if len(rows) == 1:
        return {"session": rows[0]["session"], "confidence": 1.0, "why": "only one agent"}
    if ask is None:
        def ask(state, questions):
            return jev.ask(state, questions, timeout=PICK_TIMEOUT_S)
    criteria, keys = menu(board)
    answers = ask({"spoken": said}, {"agent": {
        "type": "choice",
        "instructions": {
            "question": "The user said `spoken` out loud while several AI coding sessions run on their Mac. "
                        "Which session is it meant for?",
            "note": "People name a session by its folder, its project, or what it is doing. Speech-to-text "
                    "mishears names, so match on meaning. If no single session is clearly meant, choose none.",
        },
        "criteria": criteria,
    }})
    answer = answers.get("agent") if isinstance(answers, dict) else None
    validated = jev.validate_choice(answer, criteria)
    if validated is None:
        return {"session": None, "confidence": 0.0, "why": "jev did not provide a valid choice"}
    choice, confidence = validated
    if choice == "none" or confidence < PICK_FLOOR:
        return {"session": None, "confidence": confidence, "why": f"jev chose {choice} at {confidence:.2f}"}
    return {"session": keys[choice], "confidence": confidence, "why": f"jev chose {choice}"}

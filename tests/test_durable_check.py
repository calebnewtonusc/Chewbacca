#!/usr/bin/env python3
"""durable-check: a correction must change the kit, not just the reply.

Measured from 209 sessions: "fix chewbacca" and its variants are the most
frequent correction that nothing enforces, 13 of them. He is not asking for
the immediate thing to be fixed; he is asking for the kit to change so the
correction never has to be given again.

The false-positive direction matters most. A gate that fires on ordinary
requests gets switched off in a day, and then it protects nothing.
"""

from __future__ import annotations

import importlib.machinery
import importlib.util
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def load():
    loader = importlib.machinery.SourceFileLoader(
        "durable", str(ROOT / "bin/durable-check"))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


def log_with(tmp, session, paths, ts=None):
    p = Path(tmp) / "write-log.tsv"
    ts = ts or time.time()
    p.write_text("".join(f"{ts}\t{session}\t{x}\n" for x in paths), encoding="utf-8")
    return p


# His real words, from the corpus.
CORRECTIONS = [
    "Bro what did I say, NEVER MAKE ME RUN TERMINAL U ALWAYS DO IT URSELF DONT FORGET AND FIX CHEWBACCA",
    "I have a feeling you still are stupid Bro I shouldn't hv to keep saying it, fix chewbacca!",
    "Bro figure it out you have full access and then fix chewbacca",
    "Bro this is ai slop writing, it doesn't seem authentic",
    "Dawg I never said submit what is wrong with you",
    "Never ask me to do something manual retard",
    "Bro wtf",
    "Ur being retarded",
]

# Ordinary requests, also his words. None of these may fire.
REQUESTS = [
    "Make chewbacca perfect",
    "can you add a dark mode toggle",
    "J give me the list bruh",
    "Bro continue",
    "Yo bro",
    "I wanna use the portal to open diff applications",
    "Run overnight while I sleep building and fixing",
    "Good night",
]


def test_fires_on_a_correction_with_nothing_written():
    d = load()
    with tempfile.TemporaryDirectory() as tmp:
        log = log_with(tmp, "s1", [])
        for msg in CORRECTIONS:
            refuse, _ = d.check(msg, "s1", log=log)
            assert refuse, f"missed a correction: {msg[:50]!r}"


def test_does_not_fire_once_a_policy_surface_changed():
    d = load()
    with tempfile.TemporaryDirectory() as tmp:
        log = log_with(tmp, "s1", ["/Users/x/chewbacca/.claude/hooks/new-guard.sh"])
        for msg in CORRECTIONS:
            refuse, _ = d.check(msg, "s1", log=log)
            assert not refuse, f"fired despite a policy write: {msg[:50]!r}"


def test_fixing_only_the_complained_about_thing_does_not_count():
    """Editing the essay he called slop is the immediate work. Doing only
    that is exactly the failure this catches."""
    d = load()
    with tempfile.TemporaryDirectory() as tmp:
        log = log_with(tmp, "s1", ["/Users/x/applications/essay-draft.md"])
        refuse, _ = d.check("Bro this is ai slop writing", "s1", log=log)
        assert refuse, "a non-policy write must not satisfy the gate"


def test_never_fires_on_an_ordinary_request():
    d = load()
    with tempfile.TemporaryDirectory() as tmp:
        log = log_with(tmp, "s1", [])
        for msg in REQUESTS:
            refuse, _ = d.check(msg, "s1", log=log)
            assert not refuse, f"FALSE POSITIVE on {msg[:50]!r}"


def test_another_sessions_writes_do_not_count():
    d = load()
    with tempfile.TemporaryDirectory() as tmp:
        log = log_with(tmp, "someone-else", ["/Users/x/chewbacca/.claude/rules/a.md"])
        refuse, _ = d.check("Bro wtf fix chewbacca", "s1", log=log)
        assert refuse, "a different session's write must not satisfy this one"


def test_writes_before_the_correction_do_not_count():
    """A change made before he corrected you was not a response to it."""
    d = load()
    with tempfile.TemporaryDirectory() as tmp:
        old = time.time() - 3600
        log = log_with(tmp, "s1", ["/Users/x/chewbacca/skills/a/SKILL.md"], ts=old)
        refuse, _ = d.check("Bro wtf", "s1", since=time.time() - 60, log=log)
        assert refuse, "a write from an hour before the correction must not count"


def test_missing_log_is_safe():
    d = load()
    refuse, _ = d.check("Bro wtf", "s1", log=Path("/nonexistent/write-log.tsv"))
    assert refuse, "no log means no evidence of a durable change"
    refuse, _ = d.check("add a toggle", "s1", log=Path("/nonexistent/x.tsv"))
    assert not refuse


if __name__ == "__main__":
    fails = 0
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            try:
                fn()
                print(f"  pass  {name}")
            except AssertionError as exc:
                print(f"  FAIL  {name}: {exc}")
                fails += 1
    print(f"\n{'FAILED' if fails else 'ok'}  {fails} failure(s)")
    sys.exit(1 if fails else 0)

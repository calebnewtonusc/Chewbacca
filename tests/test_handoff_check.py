#!/usr/bin/env python3
"""handoff-check: refuse a reply that hands the user something to run.

do-it-yourself.md is ALWAYS ON and Caleb still had to say it twice in one
night. A rule that does not fire is not a rule, so these cases are the rule
turned into something that executes.

The false-positive cases matter more than the true positives. A guard that
fires on correct replies gets switched off, and then it protects nothing.
"""

from __future__ import annotations

import importlib.machinery
import importlib.util
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def load():
    loader = importlib.machinery.SourceFileLoader(
        "handoff", str(ROOT / "bin/handoff-check"))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


MUST_FIRE = [
    "All set. Just run `cd ~/project && ./install.sh` to finish.",
    "You'll need to brew install jq first.",
    "Rebuild to see it:\n\n```bash\ncd ~/kit && ./install.sh\n```",
    "You should run the suite before merging.",
    "Try running it again with --force.",
    "Open a terminal and paste this in.",
    "Make sure you run the migration after pulling.",
    "Don't forget to set ANTHROPIC_API_KEY.",
    "Now run the tests and tell me what happens.",
    "You'll have to grant Accessibility yourself.",
]

MUST_NOT_FIRE = [
    # Reporting what was actually done. The honest, correct shape.
    "I ran the suite: 278 passed, 0 failed.",
    "I pushed to main. I ran `swift build` first and it was clean.",
    "I installed it and linked it:\n\n```\nhud-voice -> ~/.local/bin\n```",
    # Showing a command as evidence, in past tense.
    "I ran this:\n\n```bash\ngit commit -- bin/portal\n```\n\nand it worked.",
    # A genuine blocker, named the sanctioned way.
    "BLOCKED: Portal.app needs Accessibility. That is a click only you can make.",
    "BLOCKED: the 2FA prompt is on your phone.",
    # Explaining what a command does, not instructing.
    "The `--json` flag makes evals.py write a row per case.",
    "`fitness --run` costs model calls, which is why it had never been run.",
    # Ordinary prose with the word run in it.
    "The loop has never run once.",
    "That test run took sixteen seconds.",
]


def test_fires_on_every_handoff():
    h = load()
    for msg in MUST_FIRE:
        assert h.check(msg), f"MISSED a handoff: {msg[:60]!r}"


def test_never_fires_on_an_honest_report():
    h = load()
    for msg in MUST_NOT_FIRE:
        hits = h.check(msg)
        assert not hits, f"FALSE POSITIVE on {msg[:60]!r}: {hits}"


def test_blocked_is_an_escape():
    """BLOCKED: is the sanctioned way to name a real blocker, so a reply that
    uses it must pass even when it also contains an instruction."""
    h = load()
    msg = "BLOCKED: only you can approve this.\nThen run `./install.sh`."
    assert not h.check(msg)


def test_an_explicit_request_is_an_escape():
    """He asked for a runnable prompt for a parallel tab on the same night the
    rule was being broken. Handing one over was correct."""
    h = load()
    msg = "Here you go:\n\n```\ncd ~/kit && claude\n```\n\nJust run that."
    assert h.check(msg), "sanity: this is a handoff with no request"
    assert not h.check(msg, user_text="give me a prompt to go ham there")
    assert not h.check(msg, user_text="what's the command?")


def test_empty_and_none_are_safe():
    h = load()
    assert h.check("") == []
    assert h.check(None) == []


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

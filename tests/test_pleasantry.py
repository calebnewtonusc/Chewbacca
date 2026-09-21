#!/usr/bin/env python3
"""A greeting must not cost a model turn.

2026-09-21: Caleb said "Good morning" and waited 21.4 seconds. The reply was
"Morning.", eight characters. The usage record says output_tokens 861, of
which thinking_tokens 854. The model reasoned for 854 tokens to produce one
word, and output is serial, so that reasoning was the twenty seconds.

No prompt fixes it. "Simple gets simple" was already in the prompt and was
obeyed: the ANSWER was one word. The cost sat in the thinking before it,
which no wording reaches. The only fix is not calling the model.

The risk is over-matching. "Good morning, what's on my calendar" is a
request with a greeting on the front, and answering it with "Morning." would
drop the half that mattered.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = (ROOT / "bin/hud-listen").read_text(encoding="utf-8")


def sets_from_source():
    """Read the vocabulary out of the source without running the daemon."""
    out = {}
    for name in ("GREETINGS", "FAREWELLS", "THANKS"):
        m = re.search(rf"{name} = \{{(.*?)\}}", SRC, re.S)
        assert m, f"{name} not found in hud-listen"
        out[name] = set(re.findall(r'"([^"]+)"', m.group(1)))
    return out


def test_the_vocabulary_exists_and_is_lowercase():
    sets = sets_from_source()
    for name, words in sets.items():
        assert words, f"{name} is empty"
        for w in words:
            assert w == w.lower(), f"{name} has {w!r}, which normalise can never match"
            assert not w.strip(".,!?") != w, f"{name} has punctuation in {w!r}"


def test_good_morning_is_covered():
    sets = sets_from_source()
    for phrase in ("good morning", "hey", "yo", "hi"):
        assert phrase in sets["GREETINGS"], f"{phrase!r} should be a greeting"
    assert "thanks" in sets["THANKS"]
    assert "good night" in sets["FAREWELLS"]


def test_it_matches_whole_utterances_only():
    """The guard against answering the wrong half of a sentence."""
    m = re.search(r"def pleasantry\(self, said: str\) -> bool:(.*?)\n    def ",
                  SRC, re.S)
    assert m, "pleasantry() not found"
    body = m.group(1)
    assert "words in self.GREETINGS" in body, (
        "matching must be equality on the whole utterance, never a substring "
        "or a prefix")
    for bad in ("startswith", "in said", ".find(", "search("):
        assert bad not in body, f"pleasantry uses {bad}, which would match a prefix"


def test_it_never_calls_a_model():
    m = re.search(r"def pleasantry\(self, said: str\) -> bool:(.*?)\n    def ",
                  SRC, re.S)
    body = m.group(1)
    for forbidden in ("subprocess", "self.ask(", "Answerer", "model_cmd", "claude"):
        assert forbidden not in body, (
            f"pleasantry reaches {forbidden}; the whole point is that it does not")


def test_it_is_asked_before_anything_expensive():
    """First in the chain, because recognising a greeting is free and
    sending one to a model is 21 seconds."""
    m = re.search(r"def ask\(self, said: str.*?\n        req = Request\(", SRC, re.S)
    assert m, "ask() chain not found"
    chain = m.group(0)
    i_pleasant = chain.find("self.pleasantry(")
    i_bubble = chain.find("self.bubble_request(")
    assert i_pleasant != -1, "pleasantry is not wired into ask()"
    assert i_bubble == -1 or i_pleasant < i_bubble, (
        "pleasantry must be tested before the other handlers")


def test_replies_rotate():
    """The prompt forbids repeating an acknowledgement, and a canned line
    that never varies is worse than a slow one that does."""
    m = re.search(r"PLEASANTRY_REPLIES = \{(.*?)\n    \}", SRC, re.S)
    assert m, "PLEASANTRY_REPLIES not found"
    for kind in ("greeting", "farewell", "thanks"):
        assert f'"{kind}"' in m.group(1), f"no replies for {kind}"
    body = re.search(r"def pleasantry.*?\n    def ", SRC, re.S).group(0)
    assert "_last_pleasantry" in body, "replies must not repeat back to back"
    assert "random.choice" in body


def test_random_is_imported():
    """py_compile passes on a missing import; the crash waits for runtime."""
    assert re.search(r"^import random$", SRC, re.M), "random is used and not imported"


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

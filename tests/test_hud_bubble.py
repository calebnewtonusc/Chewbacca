#!/usr/bin/env python3
"""bin/hud-bubble, with no display running.

The words are the whole risk. The bubble exists because the router cannot tell
"create a bubble" from terminal work, so the request that creates it is read
deterministically and never reaches a model. That only holds if the vocabulary
catches what he actually says and refuses what he does not mean, and both halves
are tested here: the utterances from ~/.bob on 2026-09-21 that went to the model
and came back wrong, and the sentences that merely contain the word.

No socket is opened. `send` is stubbed, so the lines are checked as text.
"""

from __future__ import annotations

import importlib.machinery
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TOOL = ROOT / "bin" / "hud-bubble"

failures = 0


def check(name: str, ok: bool, detail: str = "") -> None:
    global failures
    print(f"  {'ok  ' if ok else 'FAIL'} {name}" + (f": {detail}" if detail and not ok else ""))
    if not ok:
        failures += 1


def load(name: str, path: Path):
    loader = importlib.machinery.SourceFileLoader(name, str(path))
    spec = importlib.util.spec_from_loader(name, loader)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    loader.exec_module(module)
    return module


# What he actually said to the voice, from the session log on 2026-09-21. Both
# of these reached the model and came back as something else.
REAL = ["Open up a bubble", "Create a bubble"]

WANTS_ONE = [
    "create a bubble",
    "make a bubble",
    "make me a bubble",
    "generate a bubble",
    "spawn a bubble",
    "give me a bubble",
    "drop a bubble",
    "new bubble",
    "put up a bubble",
    "bring up a bubble",
    "hey can you create a bubble please",
    "give me a talk to text bubble",
    "create a dictation bubble",
    "spawn a voice bubble",
]

WANTS_THEM_GONE = [
    "take the bubble down",
    "take that bubble down",
    "put the bubble away",
    "close the bubble",
    "get rid of the bubble",
    "remove the bubbles",
    "clear the bubbles",
    "dismiss the bubble",
    "kill the bubble",
    "bubbles off",
    "no more bubbles",
]

# Sentences with the word in them that belong to the assistant. A substring
# match would take every one of these, which is how a deterministic shortcut
# becomes a thing people learn to talk around.
NOT_A_COMMAND = [
    "the create a bubble button is broken",
    "what is a bubble",
    "how do bubbles work",
    "why did the bubble not bind",
    "remind me to fix the bubble tomorrow",
    "tell caleb about the bubble feature",
    "the bubble is in the wrong place",
    "write a commit message about the bubble",
    "play a song",
    "what time is it",
    "open up a terminal",
    "create a repo",
]


def main() -> int:
    bubble = load("hud_bubble", TOOL)

    print("the words he actually said")
    for said in REAL:
        check(f"{said!r} is a bubble, not a model turn", bubble.parse(said) == "new")

    print("asking for one")
    for said in WANTS_ONE:
        check(f"{said!r}", bubble.parse(said) == "new", repr(bubble.parse(said)))

    print("taking them down")
    for said in WANTS_THEM_GONE:
        check(f"{said!r}", bubble.parse(said) == "clear", repr(bubble.parse(said)))

    print("everything else belongs to the assistant")
    for said in NOT_A_COMMAND:
        check(f"{said!r} is not a command", bubble.parse(said) is None, repr(bubble.parse(said)))

    print("the lines it sends")
    sent: list[str] = []
    bubble.send = lambda line: sent.append(line)
    check("new with no name lets the display choose",
          bubble.perform("new") and sent == ["b"], str(sent))
    sent.clear()
    check("new with a name asks for that one",
          bubble.perform("new", "b2") and sent == ["b b2"], str(sent))
    sent.clear()
    answer = bubble.perform("clear")
    check("clear takes them all down", sent == ["b clear"], str(sent))
    check("and says so in one sentence", answer == "bubbles down.", answer)
    sent.clear()
    check("off names the one", bubble.perform("off", "b1") and sent == ["b b1 off"], str(sent))
    sent.clear()
    try:
        bubble.perform("off")
        check("off with no id is refused", False)
    except bubble.BubbleError as error:
        check("off with no id is refused", "which bubble" in str(error), str(error))

    print("reading the grant off the log")
    refused = "05:02 bubble.bind refused id=b1 reason=accessibility not granted"
    granted = "05:41 bubble.bind ok id=b1 app=Messages"
    check("a refusal on its own is a refusal", bubble.grant_from_log(refused) is False)
    check("a bind on its own is the grant", bubble.grant_from_log(granted) is True)
    check("the newest line wins, so switching it on is noticed",
          bubble.grant_from_log(f"{refused}\n{granted}") is True,
          repr(bubble.grant_from_log(f"{refused}\n{granted}")))
    check("and switching it off again is noticed too",
          bubble.grant_from_log(f"{granted}\n{refused}") is False)
    check("no bind attempt is not a denial", bubble.grant_from_log("05:00 bubble.spawn id=b1") is None)
    check("an empty window says nothing", bubble.grant_from_log("") is None)

    print("with no display")
    with tempfile.TemporaryDirectory() as home:
        module = load("hud_bubble_offline", TOOL)
        module.SOCKET = str(Path(home) / "hud.sock")
        try:
            module.perform("new")
            check("says the display is not running", False)
        except module.BubbleError as error:
            check("says the display is not running, and how to start it",
                  "not running" in str(error) and "hud open" in str(error), str(error))

    print("the command")
    env = dict(os.environ)
    run = lambda *args: subprocess.run(  # noqa: E731
        [sys.executable, str(TOOL), *args], capture_output=True, text=True, env=env)
    out = run("parse", "spawn a bubble", "--json")
    check("parse prints the verb as JSON",
          out.returncode == 0 and json.loads(out.stdout)["verb"] == "new",
          out.stdout + out.stderr)
    check("parse of anything else is exit 1", run("parse", "what time is it").returncode == 1)
    out = run("doctor")
    check("doctor names the display, the grant and the paste tier",
          "display" in out.stdout and "accessibility" in out.stdout
          and "paste tier" in out.stdout, out.stdout + out.stderr)

    print("\nall passed" if not failures else f"\n{failures} failed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())

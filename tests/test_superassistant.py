#!/usr/bin/env python3
"""bin/superassistant, against a temp brain and a temp log.

The digest is what the voice assistant knows about the person; the log is
what the person asked it. Both halves are checked here without a socket, a
model, or the real brain: PERSONAL_CONTEXT_DIR and SUPERASSISTANT_DIR point
into a temp directory for the whole run.
"""

from __future__ import annotations

import importlib.machinery
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TOOL = ROOT / "bin" / "superassistant"
# The dash MEMORY.md uses between a title and its hook, kept out of the source.
DASH = chr(0x2014)

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
    loader.exec_module(module)
    return module


def make_brain(root: Path) -> Path:
    brain = root / "brain"
    (brain / "memory").mkdir(parents=True)
    (brain / "YOU.md").write_text(
        "# You: Who You Are\n\n**Updated:** 2026-09-19.\n\n---\n\n## Identity\n\n"
        "- **Name:** Test Person\n- **Role:** Builder\n- YOUR_CITY\n- ...\n\n"
        "## Background\n\nA paragraph that is not identity.\n"
    )
    (brain / "NOW.md").write_text(
        "# NOW: What's Happening Right Now\n\n**Updated:** 2026-09-19. Auto-updated by Claude.\n"
        "**Update trigger:** whatever.\n\n---\n\n## Current Work\n\nShipping the widget this week.\n\n"
        "## Things Broken / Needs Attention\n\n- The deploy is red.\n"
    )
    (brain / "PEOPLE.md").write_text(
        "# People\n\n## Collaborators (Active)\n\n| Name | GitHub | Role | Notes |\n"
        "| ---- | ------ | ---- | ----- |\n| Caleb Newton | calebnewtonusc | Co-builder | Chewbacca |\n"
        "| ... | ... | ... | ... |\n\n## Family\n\n| Who | Notes |\n| --- | --- |\n| Mom | Calls Sundays |\n"
    )
    (brain / "memory" / "MEMORY.md").write_text(
        "- [Do not raise USC](feedback-no-usc.md) " + DASH + " the kit exists.\n"
        "- [HUD voice loop](project-hud.md) " + DASH + " push-to-talk over the socket.\n"
    )
    return brain


def main() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        brain = make_brain(root)
        store = root / "superassistant"
        os.environ["PERSONAL_CONTEXT_DIR"] = str(brain)
        os.environ["CONTEXT_OWNER"] = "Test"
        os.environ["SUPERASSISTANT_DIR"] = str(store)
        sa = load("superassistant_under_test", TOOL)

        print("the digest")
        text = sa.digest()
        check("it names the person and the brain", text.startswith("# Who you are talking to") and "Test." in text and str(brain) in text)
        check("the identity section is in, its scaffolding is not",
              "- **Name:** Test Person" in text and "YOUR_CITY" not in text and "- ..." not in text, text)
        check("NOW.md is in without its bookkeeping",
              "Shipping the widget this week." in text and "The deploy is red." in text
              and "Updated:" not in text and "Update trigger" not in text, text)
        check("people are one line each, headers and placeholders dropped",
              "- Caleb Newton, calebnewtonusc, Co-builder, Chewbacca" in text and "- Mom, Calls Sundays" in text
              and "Name, GitHub" not in text and "- ..., ..." not in text, text)
        check("the memory index is in, with its dash read as a colon",
              "- [HUD voice loop](project-hud.md): push-to-talk over the socket." in text and DASH not in text, text)
        check("it says where the questions are and how to read them",
              str(store / "questions.jsonl") in text and "superassistant search" in text)
        check("it says to run coursework for a deadline", "coursework due" in text)
        check("no professional index, no section for it", "Professional contacts" not in text, text)
        index = brain / "professional-contacts" / "contacts"
        index.parent.mkdir()
        index.write_text("#!/bin/sh\n")
        text = sa.digest()
        check("with one, the voice is told where it is and how to ask it",
              "## Professional contacts" in text and f"`{index} search " in text and f"`{index} who " in text
              and "mac contacts find" in text, text)

        print("the prompt file")
        base = root / "agent.md"
        base.write_text("You are the voice of this Mac.\n")
        out = root / "bob" / "agent-prompt.md"
        first = sa.agent_prompt(base, out)
        # The contract is an order, not an exact string. agent_prompt appends
        # the kit's doctrine and an index of the installed skills between the
        # base and the digest, so asserting what follows the base couples this
        # test to whichever section happens to come first in doctrine.md. On
        # 2026-09-21 it did exactly that and broke when a section was added.
        written = out.read_text()
        check("it is written next to nothing, with the base first",
              first == out and written.startswith("You are the voice of this Mac.\n"))
        stamp = out.stat().st_mtime_ns
        time.sleep(0.02)
        sa.agent_prompt(base, out)
        check("an unchanged prompt is not rewritten", out.stat().st_mtime_ns == stamp)
        (brain / "NOW.md").write_text("# NOW\n\n## Current Work\n\nShipping the gadget now.\n")
        sa.agent_prompt(base, out)
        check("a changed NOW.md reaches the prompt",
              "Shipping the gadget now." in out.read_text() and "widget" not in out.read_text())
        check("an unreadable base falls back to itself", sa.agent_prompt(root / "missing.md", out) == root / "missing.md")

        print("the log")
        check("nothing yet", sa.entries() == [] and sa.recent(5) == [])
        check("a question is kept", sa.record({"said": "what is due", "typed": False, "answer": "Two things.\n\nA and B."}))
        check("a second one too", sa.record({"said": "text caleb", "typed": True, "answer": "Sent."}))
        (store / "questions.jsonl").open("a").write("not json\n")
        rows = sa.entries()
        check("both come back in order, stamped, and the bad line is skipped",
              [r["said"] for r in rows] == ["what is due", "text caleb"] and all("at" in r for r in rows), f"got {rows}")
        check("recent is the tail", [r["said"] for r in sa.recent(1)] == ["text caleb"])
        check("search reads questions and answers, any case",
              [r["said"] for r in sa.search("CALEB")] == ["text caleb"] and [r["said"] for r in sa.search("a and b")] == ["what is due"])
        check("today is today", len(sa.today()) == 2)
        check("a line shows when, how, what, and the first line back",
              "spoken  what is due" in sa.line(rows[0]) and "Two things." in sa.line(rows[0]) and "typed" in sa.line(rows[1]))
        check("a brief line is when and what", sa.line(rows[1], brief=True).endswith(" text caleb"))
        check("a log that cannot be written is reported, not raised",
              sa.record({"said": "x"}, log=root / "nowhere" / "a" / "b" / "q.jsonl") in (True, False))

        print("the command")
        env = dict(os.environ)
        run = lambda *args: subprocess.run([sys.executable, str(TOOL), *args], capture_output=True, text=True, env=env)  # noqa: E731
        out = run("recent", "5", "--line")
        check("recent --line is one line a question",
              out.returncode == 0 and out.stdout.count("\n") == 2 and out.stdout.rstrip().endswith("text caleb"), out.stdout + out.stderr)
        out = run("search", "due", "--json")
        check("search --json is a JSON object a hit",
              out.returncode == 0 and json.loads(out.stdout.strip())["said"] == "what is due", out.stdout + out.stderr)
        check("a miss exits 1", run("search", "nothing like this").returncode == 1)
        check("path is the log", run("path").stdout.strip() == str(store / "questions.jsonl"))
        check("context is the digest", run("context").stdout.startswith("# Who you are talking to"))

    print("\nall passed" if not failures else f"\n{failures} failed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())

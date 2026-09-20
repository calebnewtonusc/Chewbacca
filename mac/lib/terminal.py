#!/usr/bin/env python3
"""Find the Terminal tab running Claude Code, and put a draft in it.

Layer 2, Terminal.app's scripting dictionary, plus one paste. Nothing here
presses Return except `submit`, and `submit` is only ever run because a person
said "send it" or "run it" (bin/hud-listen). A prompt that Chewbacca typed and
Chewbacca also submitted is a prompt nobody read.

    chewie terminal tabs                    every tab: tty, selected, front, processes
    chewie terminal ensure [--cwd DIR]      a tab running claude, opened if needed
    chewie terminal draft "<text>" [--tty]  paste into the claude tab, no Return
    chewie terminal submit [--tty]          press Return in that tab
    chewie terminal clear [--tty]           Control-U in that tab

Memory (`~/.bob/memory/`, or BOB_MEMORY_DIR): `draft.json` is the outstanding
draft, written by `draft`, removed by `submit` and `clear`. `project.json`
gets `tty`, `cwd`, `name`, `last_sent`, `updated` from here; `summary` is
written by hud-listen and left alone.
"""
import argparse
import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

MEMORY = Path(os.environ.get("BOB_MEMORY_DIR", str(Path.home() / ".bob" / "memory")))
DRAFT = MEMORY / "draft.json"
PROJECT = MEMORY / "project.json"
SECURE_INPUT = Path(__file__).resolve().parent / "secure-input.sh"

# One line per tab: tty, selected, in the front window, processes joined by
# commas. `if application "Terminal" is running` first, because a bare `tell`
# launches Terminal, and listing tabs must never open a window.
TABS_SCRIPT = '''
set AppleScript's text item delimiters to ","
set out to ""
if application "Terminal" is running then
  tell application "Terminal"
    set wi to 0
    repeat with w in windows
      set wi to wi + 1
      repeat with t in tabs of w
        set out to out & (tty of t) & tab & (selected of t) & tab & (wi = 1) & tab & ((processes of t) as text) & linefeed
      end repeat
    end repeat
  end tell
end if
return out
'''


def parse_tabs(raw: str) -> list[dict]:
    tabs = []
    for line in raw.splitlines():
        if not line.strip():
            continue
        parts = line.split("\t")
        if len(parts) < 4:
            continue
        tty, selected, front, procs = parts[0], parts[1], parts[2], parts[3]
        tabs.append({
            "tty": tty.strip(),
            "selected": selected.strip() == "true",
            "front": front.strip() == "true",
            "processes": [p for p in procs.split(",") if p],
        })
    return tabs


def is_candidate(tab: dict) -> bool:
    return "claude" in tab["processes"]


def choose(tabs: list[dict], remembered: str | None) -> dict | None:
    """The remembered tty, else the selected tab of the front window, else the
    first tab running claude. In that order because the remembered one is the
    project the person was talking about, and the front-selected one is the
    one they are looking at."""
    candidates = [t for t in tabs if is_candidate(t)]
    if not candidates:
        return None
    for t in candidates:
        if remembered and t["tty"] == remembered:
            return t
    for t in candidates:
        if t["front"] and t["selected"]:
            return t
    return candidates[0]


def collapse(text: str) -> str:
    """One paragraph. Claude Code's input treats a pasted newline as part of
    the text, but a draft the person has to read in a one-line box reads
    better as prose than as a stack."""
    return re.sub(r"\s+", " ", text).strip()

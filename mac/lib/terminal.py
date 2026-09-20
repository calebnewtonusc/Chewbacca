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


# Everything below talks to the machine. `osascript` and `run` are module
# level so tests replace them.

# Subprocess timeouts, seconds. Guessed, never measured: no hang or incident
# set these, they exist so a stuck osascript/ps/lsof call fails loudly instead
# of blocking chewie forever.
OSASCRIPT_TIMEOUT = 15
RUN_TIMEOUT = 15
# secure-input.sh only reads one ioreg property, so it can be much tighter
# than the general timeouts above. Also guessed, never measured.
SECURE_INPUT_TIMEOUT = 5
# ensure()'s poll cadence while it waits for the newly opened tab to start
# claude. Guessed, never measured: fine-grained enough that a 10s default
# deadline still gets ~20 checks, coarse enough not to hammer osascript.
ENSURE_POLL_INTERVAL = 0.5


def osascript(script: str, *args: str) -> str:
    result = subprocess.run(
        ["osascript", "-e", script, *args], capture_output=True, text=True, timeout=OSASCRIPT_TIMEOUT
    )
    if result.returncode != 0:
        print(f"terminal: osascript failed: {result.stderr.strip()}", file=sys.stderr)
        raise SystemExit(1)
    return result.stdout


def run(argv: list[str], timeout: float = RUN_TIMEOUT) -> subprocess.CompletedProcess:
    return subprocess.run(argv, capture_output=True, text=True, timeout=timeout)


def secure_input_holder() -> str | None:
    """The process name holding Secure Input, or None. Synthetic keystrokes
    and pastes are dropped with no error while it is on."""
    try:
        result = run([str(SECURE_INPUT)], timeout=SECURE_INPUT_TIMEOUT)
    except (OSError, subprocess.TimeoutExpired):
        return None
    if result.returncode == 0:
        return None
    for line in result.stdout.splitlines():
        if "held_by" in line:
            return line.split()[-1]
    return "unknown"


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def read_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def merge_json(path: Path, patch: dict) -> dict:
    data = read_json(path)
    data.update(patch)
    MEMORY.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2), encoding="utf-8")
    return data


def tabs() -> list[dict]:
    return parse_tabs(osascript(TABS_SCRIPT))


FOCUS_SCRIPT = '''
on run argv
  set want to item 1 of argv
  tell application "Terminal"
    repeat with w in windows
      repeat with t in tabs of w
        if (tty of t) is want then
          set selected of t to true
          set index of w to 1
          activate
          return "ok"
        end if
      end repeat
    end repeat
  end tell
  return "missing"
end run
'''

# `do script` with no target opens a new window and returns its tab. Return
# is wanted here: this is a shell command, not a prompt.
OPEN_SCRIPT = '''
on run argv
  tell application "Terminal"
    activate
    set t to do script ("cd " & quoted form of (item 1 of argv) & " && claude")
    return tty of t
  end tell
end run
'''

KEY_RETURN = 'tell application "System Events" to key code 36'
KEY_CONTROL_U = 'tell application "System Events" to key code 32 using control down'


def pick(tty: str | None) -> dict:
    remembered = tty or read_json(PROJECT).get("tty")
    tab = choose(tabs(), remembered)
    if tab is None:
        print("terminal: no Terminal tab is running claude (chewie terminal ensure)", file=sys.stderr)
        raise SystemExit(1)
    return tab


def focus(tty: str) -> None:
    if osascript(FOCUS_SCRIPT, tty).strip() != "ok":
        print(f"terminal: tab {tty} is gone", file=sys.stderr)
        raise SystemExit(1)


def cwd_of(tty: str) -> str:
    """The working directory of the shell on a tty, through lsof on its
    first process. Empty if it cannot be read."""
    ps = run(["ps", "-t", tty.replace("/dev/", ""), "-o", "pid=", "-o", "comm="])
    for line in ps.stdout.splitlines():
        parts = line.split(None, 1)
        if len(parts) == 2 and parts[1].strip().endswith("claude"):
            lsof = run(["lsof", "-a", "-p", parts[0], "-d", "cwd", "-Fn"])
            for entry in lsof.stdout.splitlines():
                if entry.startswith("n/"):
                    return entry[1:]
    return ""


def remember(tab: dict) -> dict:
    cwd = cwd_of(tab["tty"])
    patch = {"tty": tab["tty"], "updated": now_iso()}
    if cwd:
        patch["cwd"] = cwd
        patch["name"] = Path(cwd).name
    return merge_json(PROJECT, patch)


def ensure(cwd: str | None, timeout: float = 10.0) -> dict:
    """A tab running claude, opened if there is none.

    Ten seconds: claude on this machine shows its prompt in about two, and
    a cold start with a big project has been seen take five. Guessed above
    that.
    """
    tab = choose(tabs(), read_json(PROJECT).get("tty"))
    if tab is not None:
        project = remember(tab)
        return {"tty": tab["tty"], "cwd": project.get("cwd", ""), "opened": False}
    folder = cwd or read_json(PROJECT).get("cwd")
    if not folder:
        print("terminal: no claude tab and no known folder; pass --cwd", file=sys.stderr)
        raise SystemExit(1)
    folder = os.path.expanduser(folder)
    os.makedirs(folder, exist_ok=True)
    tty = osascript(OPEN_SCRIPT, folder).strip()
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        for t in tabs():
            if t["tty"] == tty and is_candidate(t):
                project = merge_json(PROJECT, {
                    "tty": tty, "cwd": folder, "name": Path(folder).name, "updated": now_iso(),
                })
                return {"tty": tty, "cwd": project["cwd"], "opened": True}
        time.sleep(ENSURE_POLL_INTERVAL)
    print(f"terminal: opened {tty} but claude did not start within {timeout:.0f}s", file=sys.stderr)
    raise SystemExit(1)


def draft(text: str, tty: str | None) -> dict:
    holder = secure_input_holder()
    if holder:
        print(f"terminal: Secure Input is on, held by {holder}; the paste would be dropped", file=sys.stderr)
        raise SystemExit(2)
    tab = pick(tty)
    body = collapse(text)
    focus(tab["tty"])
    result = run(["peekaboo", "paste", "--text", body])
    if result.returncode != 0:
        print(f"terminal: paste failed: {result.stderr.strip() or result.stdout.strip()}", file=sys.stderr)
        raise SystemExit(1)
    MEMORY.mkdir(parents=True, exist_ok=True)
    DRAFT.write_text(json.dumps({"tty": tab["tty"], "text": body, "t": now_iso()}), encoding="utf-8")
    # Only last_sent/updated here: `tty` is ensure's to remember, so a draft
    # sent to an explicit --tty (a one-off, not the working project) does not
    # silently reassign which tab chewie treats as "the" project.
    merge_json(PROJECT, {"last_sent": now_iso(), "updated": now_iso()})
    return {"tty": tab["tty"], "chars": len(body)}


def _forget_draft() -> None:
    try:
        DRAFT.unlink()
    except OSError:
        pass


def submit(tty: str | None) -> dict:
    tab = pick(tty)
    focus(tab["tty"])
    osascript(KEY_RETURN)
    _forget_draft()
    return {"tty": tab["tty"], "submitted": True}


def clear(tty: str | None) -> dict:
    holder = secure_input_holder()
    if holder:
        print(f"terminal: Secure Input is on, held by {holder}", file=sys.stderr)
        raise SystemExit(2)
    tab = pick(tty)
    focus(tab["tty"])
    osascript(KEY_CONTROL_U)
    _forget_draft()
    return {"tty": tab["tty"], "cleared": True}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="chewie terminal")
    parser.add_argument("--json", action="store_true")
    sub = parser.add_subparsers(dest="verb", required=True)
    sub.add_parser("tabs")
    p = sub.add_parser("ensure"); p.add_argument("--cwd")
    p = sub.add_parser("draft"); p.add_argument("text"); p.add_argument("--tty")
    p = sub.add_parser("submit"); p.add_argument("--tty")
    p = sub.add_parser("clear"); p.add_argument("--tty")
    args = parser.parse_args(argv)

    if args.verb == "tabs":
        out = tabs()
    elif args.verb == "ensure":
        out = ensure(args.cwd)
    elif args.verb == "draft":
        out = draft(args.text, args.tty)
    elif args.verb == "submit":
        out = submit(args.tty)
    else:
        out = clear(args.tty)

    if args.json or args.verb == "tabs":
        print(json.dumps(out, indent=2))
    elif args.verb == "draft":
        print(f"draft in {out['tty']}, {out['chars']} chars, not submitted")
    elif args.verb == "ensure":
        print(f"{out['tty']} {out['cwd']}{' (opened)' if out['opened'] else ''}")
    else:
        print(f"{args.verb} {out['tty']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

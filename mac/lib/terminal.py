#!/usr/bin/env python3
"""Find the Terminal tab running Claude Code, and put a draft in it.

Layer 2, Terminal.app's scripting dictionary, plus one paste. Nothing here
presses Return except `submit` and `answer yes`, and both are only ever run
because a person said so (bin/hud-listen): "send it" or "run it" for a draft,
"yes" while the tab is waiting on a permission. A prompt that Chewbacca typed
and Chewbacca also submitted is a prompt nobody read.

    chewie terminal tabs                    every tab: tty, selected, front, processes
    chewie terminal ensure [--cwd DIR] [--fresh]  a tab running claude, opened if needed (--fresh: always opened)
    chewie terminal draft "<text>" [--tty]  paste into the claude tab, no Return
    chewie terminal submit [--tty]          press Return in that tab
    chewie terminal clear [--tty]           Control-U in that tab
    chewie terminal answer yes|no [--tty]   Return or Escape on the permission dialog
    chewie terminal interrupt [--tty]       Escape: stop the run in that tab
    chewie terminal focus [--tty]           bring that tab to the front
    chewie terminal hook                    a Claude Code hook: event JSON on stdin (see terminal_events.py)

Memory (`~/.bob/memory/`, or BOB_MEMORY_DIR): `draft.json` is the outstanding
draft, written by `draft`, removed by `submit` and `clear`. `project.json`
gets `tty`, `cwd`, `name`, `last_sent`, `updated` from here; `summary` is
written by hud-listen and left alone.

`submit` refuses with exit 3 unless `CHEWIE_TERMINAL_SUBMIT=1` is in its
environment. That is the mechanism, not the doctrine in `bin/hud-agent.md`:
`bin/hud-listen`'s draft-word path is the only caller that sets it, only when
a person said "send it" (or similar) with a draft outstanding, so a model
that decides on its own to run `chewie terminal submit` presses nothing.
`answer yes` presses the same key and refuses the same way, on
`CHEWIE_TERMINAL_ANSWER=1`, which hud-listen's answer-word path sets. `answer
no` and `interrupt` press Escape and need no gate.
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
-- Inside `tell application "Terminal"` the word `tab` is Terminal's tab
-- class and coerces to the text "tab": the first live run on 2026-09-20
-- produced "/dev/ttys004tabtruetab..." and no tab ever parsed. The
-- separator is bound here, outside the tell block, by character code.
set sep to string id 9
if application "Terminal" is running then
  tell application "Terminal"
    set wi to 0
    repeat with w in windows
      set wi to wi + 1
      repeat with t in tabs of w
        set out to out & (tty of t) & sep & (selected of t) & sep & (wi = 1) & sep & ((processes of t) as text) & linefeed
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
    # On 2026-09-20 Terminal listed the same process as "claude" while
    # `ps -o ucomm` named it "claude.exe" (the homebrew npm link's target).
    # Both spellings are accepted rather than betting on which one a later
    # macOS or install path reports.
    return any(p == "claude" or p.startswith("claude.") for p in tab["processes"])


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
    and pastes are dropped with no error while it is on.

    Fails open on purpose: if the check script itself cannot run, a missing
    check must not block every draft on a machine where secure-input.sh
    happens to be absent. But a silent fail-open is indistinguishable from
    "Secure Input is off", so it says so on stderr instead of just returning
    None.
    """
    try:
        result = run([str(SECURE_INPUT)], timeout=SECURE_INPUT_TIMEOUT)
    except (OSError, subprocess.TimeoutExpired) as err:
        print(f"terminal: could not check Secure Input ({err}); assuming it is off", file=sys.stderr)
        return None
    if result.returncode == 0:
        return None
    for line in result.stdout.splitlines():
        if "held_by" in line:
            return line.split()[-1]
    return "unknown"


def refuse_under_secure_input() -> None:
    """Exit 2 if Secure Input is on. `draft`'s paste, `submit`'s Return and
    `clear`'s Control-U are all synthetic input to Terminal, and Secure Input
    drops all three with no error, so all three must check before running."""
    holder = secure_input_holder()
    if holder:
        print(f"terminal: Secure Input is on, held by {holder}; the input would be dropped", file=sys.stderr)
        raise SystemExit(2)


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
# Escape. Claude Code reads it as "interrupt" during a run and as "no" on a
# permission dialog; Return takes the dialog's highlighted first option,
# which is "Yes". Observed in Claude Code 2.1.278, and the live check
# tests/live/terminal-loop.sh is what proves it on a new version.
KEY_ESCAPE = 'tell application "System Events" to key code 53'


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


def ensure(cwd: str | None, timeout: float = 10.0, fresh: bool = False) -> dict:
    """A tab running claude, opened if there is none.

    Ten seconds: claude on this machine shows its prompt in about two, and
    a cold start with a big project has been seen take five. Guessed above
    that.

    `fresh` skips the existing tabs and always opens one. It exists for the
    live check: on 2026-09-20 the check let ensure choose, ensure preferred
    the front tab, which was a real Claude Code session, and the check
    drafted and submitted its test prompt into that session.
    """
    tab = None if fresh else choose(tabs(), read_json(PROJECT).get("tty"))
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
    seen = [t["processes"] for t in tabs() if t["tty"] == tty]
    print(
        f"terminal: opened {tty} but no claude process showed within {timeout:.0f}s"
        f" (saw {seen[0] if seen else 'no such tab'})",
        file=sys.stderr,
    )
    raise SystemExit(1)


def draft(text: str, tty: str | None) -> dict:
    refuse_under_secure_input()
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
    # The mechanism, not the doctrine: bin/hud-agent.md tells the model never
    # to run this on its own, and that instruction is the only thing that
    # used to stop it. hud-listen's draft-word path is the only caller that
    # sets this, and only after a person said "send it" with a draft
    # outstanding, so anything else that runs `chewie terminal submit`
    # presses nothing.
    if os.environ.get("CHEWIE_TERMINAL_SUBMIT") != "1":
        print(
            "terminal: submit refused; CHEWIE_TERMINAL_SUBMIT=1 is set only by "
            "hud-listen's draft-word path, in response to a person saying send it",
            file=sys.stderr,
        )
        raise SystemExit(3)
    refuse_under_secure_input()
    tab = pick(tty)
    focus(tab["tty"])
    osascript(KEY_RETURN)
    _forget_draft()
    return {"tty": tab["tty"], "submitted": True}


def clear(tty: str | None) -> dict:
    refuse_under_secure_input()
    tab = pick(tty)
    focus(tab["tty"])
    osascript(KEY_CONTROL_U)
    _forget_draft()
    return {"tty": tab["tty"], "cleared": True}


def answer(choice: str, tty: str | None) -> dict:
    """Yes or no to the permission dialog the tab is showing. Only ever run
    by hud-listen while its terminal state is waiting and the hook has
    already given the prompt back to the tab, so the Return never lands on
    an input holding a draft."""
    # `yes` presses the same Return `submit` does, and every way hud-listen's
    # state can be wrong turns that into a prompt nobody read. The docstring
    # above was the whole safety argument; this is the mechanism. `no` and
    # `interrupt` press Escape, which costs a tool call at worst.
    if choice == "yes" and os.environ.get("CHEWIE_TERMINAL_ANSWER") != "1":
        print(
            "terminal: answer yes refused; CHEWIE_TERMINAL_ANSWER=1 is set only by "
            "hud-listen's answer-word path, in response to a person saying yes while "
            "the tab waits on a permission",
            file=sys.stderr,
        )
        raise SystemExit(3)
    refuse_under_secure_input()
    tab = pick(tty)
    focus(tab["tty"])
    osascript(KEY_RETURN if choice == "yes" else KEY_ESCAPE)
    return {"tty": tab["tty"], "answer": choice}


def interrupt(tty: str | None) -> dict:
    """Escape in the tab: Claude Code stops what it is doing."""
    refuse_under_secure_input()
    tab = pick(tty)
    focus(tab["tty"])
    osascript(KEY_ESCAPE)
    return {"tty": tab["tty"], "interrupted": True}


def focus_tab(tty: str | None) -> dict:
    tab = pick(tty)
    focus(tab["tty"])
    return {"tty": tab["tty"], "focused": True}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="chewie terminal")
    parser.add_argument("--json", action="store_true")
    sub = parser.add_subparsers(dest="verb", required=True)
    sub.add_parser("tabs")
    p = sub.add_parser("ensure"); p.add_argument("--cwd"); p.add_argument("--fresh", action="store_true")
    p = sub.add_parser("draft"); p.add_argument("text"); p.add_argument("--tty")
    p = sub.add_parser("submit"); p.add_argument("--tty")
    p = sub.add_parser("clear"); p.add_argument("--tty")
    p = sub.add_parser("answer"); p.add_argument("choice", choices=["yes", "no"]); p.add_argument("--tty")
    p = sub.add_parser("interrupt"); p.add_argument("--tty")
    p = sub.add_parser("focus"); p.add_argument("--tty")
    sub.add_parser("hook")
    args = parser.parse_args(argv)

    if args.verb == "hook":
        # Lazy: the events module is a sibling file, and this script is also
        # loaded by tests through SourceFileLoader with no sys.path entry.
        sys.path.insert(0, str(Path(__file__).resolve().parent))
        try:
            import terminal_events
            sys.stdout.write(terminal_events.handle(sys.stdin.read()))
        except Exception as err:  # noqa: BLE001  a hook that crashes blocks the tab
            print(f"terminal hook: {err}", file=sys.stderr)
        return 0

    if args.verb == "tabs":
        out = tabs()
    elif args.verb == "ensure":
        out = ensure(args.cwd, fresh=args.fresh)
    elif args.verb == "draft":
        out = draft(args.text, args.tty)
    elif args.verb == "submit":
        out = submit(args.tty)
    elif args.verb == "answer":
        out = answer(args.choice, args.tty)
    elif args.verb == "interrupt":
        out = interrupt(args.tty)
    elif args.verb == "focus":
        out = focus_tab(args.tty)
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

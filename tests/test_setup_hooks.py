#!/usr/bin/env python3
"""setup.sh's hook registration, run twice.

`chewbacca update` re-runs the installer by design, so every registration in
it has to be idempotent. Three of the terminal loop's six events used
`setdefault(event, []).append(...)`, which appended another copy of the same
hook on every run. Two PermissionRequest hooks firing for one prompt is the
dangerous one: the one that loses the ask-file race records the prompt as
not held, and a voice "yes" then presses Return in a tab that is showing no
dialog.

Nothing here runs setup.sh. The settings block is extracted from it and run
on its own under a temp HOME, which is the only part of the installer that
touches ~/.claude/settings.json.

    python3 tests/test_setup_hooks.py
"""
import json
import os
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SETUP = ROOT / "setup.sh"
OPEN_MARK = "python3 << 'PYEOF'"
CLOSE_MARK = "PYEOF"

PASSED = FAILED = 0


def check(name, cond, detail=""):
    global PASSED, FAILED
    if cond:
        PASSED += 1
        print(f"  pass  {name}")
    else:
        FAILED += 1
        print(f"  FAIL  {name}  {detail}")


def settings_block() -> str:
    """The first `python3 << 'PYEOF'` heredoc in setup.sh, by its markers."""
    lines = SETUP.read_text().splitlines()
    start = lines.index(OPEN_MARK) + 1
    end = start + lines[start:].index(CLOSE_MARK)
    return "\n".join(lines[start:end]) + "\n"


def run(block: str, home: pathlib.Path, opener: str = "none") -> dict:
    env = {
        "HOME": str(home),
        "PATH": os.environ.get("PATH", ""),
        "D1_HOOKS": str(home / ".claude" / "hooks"),
        "D1_SESSION_OPENER": opener,
    }
    result = subprocess.run([sys.executable, "-c", block], env=env,
                            capture_output=True, text=True)
    if result.returncode != 0:
        raise AssertionError(result.stderr)
    return json.loads((home / ".claude" / "settings.json").read_text())


def commands(settings: dict, event: str) -> list[str]:
    out = []
    for entry in settings.get("hooks", {}).get(event, []):
        out.extend(os.path.basename(str(h.get("command", ""))) for h in entry.get("hooks", []))
    return out


def main() -> int:
    home = pathlib.Path(tempfile.mkdtemp())
    (home / ".claude").mkdir()
    block = settings_block()
    check("the settings block was found", "settings.setdefault(\"hooks\", {})" in block)
    first = run(block, home)
    second = run(block, home)

    six = ("PermissionRequest", "PreToolUse", "PostToolUse", "PermissionDenied", "Stop", "SessionEnd")
    for event in six:
        check(f"{event} is registered once on the first run",
              commands(first, event).count("terminal-loop.sh") == 1, str(commands(first, event)))
        check(f"{event} is still registered once on a re-run",
              commands(second, event).count("terminal-loop.sh") == 1, str(commands(second, event)))
    check("a re-run changes nothing at all", first == second)

    # With no session opener the block pops UserPromptSubmit before adding
    # to it, which hid the same bug on those two. With one configured the
    # list survives the run, so this is where they would duplicate.
    opened = pathlib.Path(tempfile.mkdtemp())
    (opened / ".claude").mkdir()
    run(block, opened, opener="prayer")
    twice = run(block, opened, opener="prayer")
    for name in ("coursework-context.sh", "kit-route.sh"):
        check(f"{name} is registered once on a re-run with a session opener",
              commands(twice, "UserPromptSubmit").count(name) == 1,
              str(commands(twice, "UserPromptSubmit")))

    print(f"\n{PASSED} passed, {FAILED} failed")
    return 1 if FAILED else 0


if __name__ == "__main__":
    sys.exit(main())

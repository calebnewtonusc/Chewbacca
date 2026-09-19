#!/usr/bin/env python3
"""Every `# ── Section ──` header in setup.sh must be followed by `if should_run`.

A header inserted mid-section closes the previous guard early, and everything
after it then runs on every invocation, including `--only`. That once rewrote a
live machine's global hooks during an `--only prereq` run, silently.

This check existed only in CI, so a header added in the wrong place passed the
whole local suite and failed after the push. A rule worth enforcing is worth
enforcing where the work happens.

  python3 tests/check_sections.py [path/to/setup.sh]
"""

import pathlib
import re
import sys

# Sections that deliberately run every time: they define things the guarded
# sections need, so gating them would break `--only`.
UNGUARDED = {"Colors", "Inputs", "Collect info", "What this run turns on", "Done"}
HEADER = re.compile("^# ── (.+?) ─")


def main() -> int:
    target = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "setup.sh")
    lines = target.read_text(encoding="utf-8").splitlines()
    bad = []
    for i, line in enumerate(lines):
        m = HEADER.match(line)
        if not m or m.group(1).strip() in UNGUARDED:
            continue
        nxt = lines[i + 1].strip() if i + 1 < len(lines) else ""
        if not nxt.startswith("if should_run"):
            bad.append(f"line {i + 1}: section {m.group(1).strip()!r} is not guarded")
    for b in bad:
        print(b)
    if not bad:
        print(f"ok  every section in {target.name} is guarded")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())

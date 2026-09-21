#!/bin/bash
# README and docs/REFERENCE.md are written by DIFFERENT generators, and on
# 2026-09-20 they disagreed by 12 skills without anything noticing: README
# said 87 (32 here), REFERENCE said 75 (20 here). The cause was two
# generators reading two directories, tools/counts.py the repo's skills/ and
# tools/inventory.py this machine's ~/.claude/skills.
#
# Both numbers must match each other AND the repo, because a reference that
# documents one laptop instead of the product sends strangers looking for
# skills they do not have.
set -uo pipefail
ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
python3 - "$ROOT" <<'PY'
import pathlib, re, sys
root = pathlib.Path(sys.argv[1])
truth = len(list((root / "skills").glob("*/SKILL.md")))
rd = re.search(r"(\d+) skills \((\d+) written here", (root / "README.md").read_text())
rf = re.search(r"(\d+) skills \((\d+) shipped here", (root / "docs/REFERENCE.md").read_text())
if not rd or not rf:
    print("  FAIL could not parse the skill counts out of README or REFERENCE"); sys.exit(1)
if rd.groups() != rf.groups():
    print(f"  FAIL README says {rd.groups()}, REFERENCE says {rf.groups()}"); sys.exit(1)
if int(rd.group(2)) != truth:
    print(f"  FAIL docs claim {rd.group(2)} vendored skills, repo ships {truth}"); sys.exit(1)
print(f"  ok   README and REFERENCE agree, and match the repo ({truth} vendored)")
PY

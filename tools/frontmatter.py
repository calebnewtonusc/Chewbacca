#!/usr/bin/env python3
"""Check that every SKILL.md frontmatter actually parses.

A skill whose YAML is malformed does not fail loudly. It fails by not being
registered, so the agent never sees it and the user concludes the skill is bad
at triggering. `life-ops` shipped that way: its description read

    description: The half of a week that is not code and not class: appointments, ...

and the unquoted colon makes YAML read `... not class` as a nested key. One
character, and a whole skill is invisible.

No pyyaml on a stock macOS python, so this checks the specific constructs that
break a frontmatter block rather than parsing the general language. That is a
narrower claim and an honest one.

  python3 tools/frontmatter.py                check the repo's skills
  python3 tools/frontmatter.py --installed    check ~/.claude/skills too
  python3 tools/frontmatter.py path/to/skills check any directory of skills
"""
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
REQUIRED = ("name", "description")


def problems(path):
    """Every reason this file's frontmatter would not load."""
    text = path.read_text(encoding="utf-8", errors="replace")
    m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    if not m:
        return ["no frontmatter block (must open on line 1 with ---)"]

    out = []
    seen = set()
    for raw in m.group(1).split("\n"):
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        if raw[0] in " \t":          # a continuation or nested value, not a key
            continue
        if ":" not in raw:
            out.append(f"line is not a key/value pair: {raw[:60]}")
            continue
        key, _, value = raw.partition(":")
        seen.add(key.strip())
        value = value.strip()
        if not value:
            continue
        # The one that bit us. An unquoted scalar containing ": " is read as a
        # nested mapping and the whole block fails.
        if value[0] not in "\"'[{" and ": " in value:
            out.append(f"{key.strip()}: unquoted value contains ': ' — wrap it in quotes")
        # An unbalanced quote swallows the rest of the block.
        if value[0] in "\"'" and not value.endswith(value[0]):
            out.append(f"{key.strip()}: opening quote is never closed")

    for r in REQUIRED:
        if r not in seen:
            out.append(f"missing required key '{r}'")
    return out


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("-")]
    # An explicit path wins, so this can check a directory it does not live in.
    # Defaulting to the repo made the tool untestable against a deliberately
    # broken fixture, which is the only way to know the check can fail at all.
    roots = [Path(a).resolve() for a in args] or [REPO / "skills"]
    if "--installed" in sys.argv:
        roots.append(Path.home() / ".claude" / "skills")

    bad = 0
    checked = 0
    for root in roots:
        for path in sorted(root.glob("*/SKILL.md")):
            checked += 1
            for p in problems(path):
                bad += 1
                rel = path if not str(path).startswith(str(REPO)) else path.relative_to(REPO)
                print(f"{rel}: {p}")

    if bad:
        print(f"\n{bad} problem(s) in {checked} skill(s). "
              f"A skill that does not parse is a skill that never fires.")
        return 1
    print(f"ok  {checked} skill frontmatter block(s) parse")
    return 0


if __name__ == "__main__":
    sys.exit(main())

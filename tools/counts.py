#!/usr/bin/env python3
"""One place that counts what the kit contains, so the README cannot drift.

The README said 42 skills, the tree held 21, and doctor reported 79. Three
numbers for one concept, all of them maintained by hand, none of them checked.
This reads the repo and rewrites the generated counts region in README.md.

  python3 tools/counts.py            rewrite the region
  python3 tools/counts.py --json     print the counts
  python3 tools/counts.py --check    exit 1 if the region is stale (CI)

Everything here is repo-only. Nothing reads the local machine, so CI produces
the same numbers a contributor's laptop does.
"""

import json
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
BEGIN = "<!-- BEGIN GENERATED: counts -->"
END = "<!-- END GENERATED: counts -->"


def counts():
    toolkit = json.loads((REPO / "settings/toolkit.json").read_text(encoding="utf-8"))
    vendored = len(list((REPO / "skills").glob("*/SKILL.md")))
    upstream = len(toolkit["skills"]["upstream"])
    packed = sum(p["count"] for p in toolkit["packs"])
    return {
        "commands": len(list((REPO / ".claude/commands").glob("*.md"))),
        "rules": len(list((REPO / ".claude/rules").glob("*.md"))),
        "hooks": len(list((REPO / ".claude/hooks").glob("*.sh"))),
        "subagents": len(list((REPO / ".claude/agents").glob("*.md"))),
        "skills_own": vendored,
        "skills_upstream": upstream,
        "skills_packed": packed,
        "skills_total": vendored + upstream + packed,
        "mcp": len(toolkit["mcp"]),
        "cli": len(toolkit["cli"]),
        "plugins": len(toolkit["plugins"]),
        "lines": lines(),
    }


def lines():
    """Tracked lines. A number nobody can reproduce is not a number."""
    try:
        files = subprocess.run(
            ["git", "ls-files"], cwd=REPO, capture_output=True, text=True, check=True
        ).stdout.split()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return 0
    total = 0
    for f in files:
        p = REPO / f
        try:
            total += p.read_text(encoding="utf-8", errors="ignore").count("\n")
        except OSError:
            pass
    return total


def sentence(c):
    return (
        f"One command installs **{c['commands']} slash commands, {c['skills_total']} skills "
        f"({c['skills_own']} written here, {c['skills_upstream']} cloned from upstream, "
        f"{c['skills_packed']} from a skill pack), {c['mcp']} MCP servers, {c['hooks']} hooks, "
        f"{c['subagents']} subagents, {c['cli']} command-line tools and {c['rules']} always-on "
        f"standards.** {c['lines']:,} lines, every one of them plain text you can read."
    )


def region(readme):
    text = readme.read_text(encoding="utf-8")
    m = re.search(re.escape(BEGIN) + r"\n(.*?)\n" + re.escape(END), text, re.S)
    return text, (m.group(1) if m else None), m


def main():
    arg = sys.argv[1] if len(sys.argv) > 1 else ""
    c = counts()
    if arg == "--json":
        print(json.dumps(c, indent=2))
        return 0

    readme = REPO / "README.md"
    text, current, m = region(readme)
    if m is None:
        print(f"no counts region in {readme.name}. Add:\n{BEGIN}\n...\n{END}", file=sys.stderr)
        return 2
    want = sentence(c)

    if arg == "--check":
        if current.strip() == want.strip():
            print(f"ok  README counts match the tree ({c['skills_total']} skills, "
                  f"{c['commands']} commands, {c['rules']} rules)")
            return 0
        print("README counts are stale. Run: python3 tools/counts.py", file=sys.stderr)
        print(f"  have: {current.strip()}", file=sys.stderr)
        print(f"  want: {want}", file=sys.stderr)
        return 1

    if current.strip() == want.strip():
        print("counts already current")
        return 0
    readme.write_text(text[: m.start(1)] + want + text[m.end(1) :], encoding="utf-8")
    print(f"README.md counts updated: {want[:70]}...")
    return 0


if __name__ == "__main__":
    sys.exit(main())

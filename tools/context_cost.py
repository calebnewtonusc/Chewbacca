#!/usr/bin/env python3
"""What the kit costs you before you type a single word.

CLAUDE.md is 957 lines and loads into every session. Nobody had ever measured
what that costs, so every argument about whether a rule earns its place was an
argument about taste.

  chewbacca context           per-file cost of everything always loaded
  chewbacca context --json    the same as data
  chewbacca context --budget  exit 1 if the always-on total is over budget

Token counts are characters/4, the standard rough estimate. It is an estimate
and it is labeled as one. Being approximately right beats having no number.
"""

import json
import os
import re
import sys
from pathlib import Path

HOME = Path.home()

CLAUDE = HOME / ".claude"
# What the kit may spend before the user's own work starts. Raise it in
# ~/.chewbacca/context-budget if you deliberately load a large personal
# context; a budget you cannot meet and will not change is just noise.
def _budget():
    f = Path.home() / ".chewbacca/context-budget"
    try:
        return int(f.read_text().strip())
    except (OSError, ValueError):
        return 15000


BUDGET_TOKENS = _budget()


def est_tokens(text):
    return len(text) // 4


def read(p):
    try:
        return p.read_text(encoding="utf-8", errors="ignore")
    except OSError:
        return ""


def imports_of(text, base):
    """@~/path imports in a CLAUDE.md, resolved."""
    out = []
    for m in re.finditer(r"^@(\S+)", text, re.M):
        p = Path(os.path.expanduser(m.group(1)))
        if not p.is_absolute():
            p = base / p
        out.append(p)
    return out


def conditional_rules(claude_md):
    """Rules the standards file itself says load on demand.

    Counting a rule that only loads for UI work as always-on made a backend
    session look like it was paying for the animation rules. It is not, and
    saying it is would send someone trimming the wrong file.
    """
    # Only rules named inside a table row. A rule mentioned in prose ("see
    # ~/.claude/rules/do-it-yourself.md") is still always-on, and treating a
    # prose mention as a deferral undercounted the real cost by 677 tokens.
    names = set()
    for line in claude_md.splitlines():
        if not line.strip().startswith("|"):
            continue
        for m in re.finditer(r"`~/\.claude/rules/([^`]+)`", line):
            names.add(m.group(1))
    return names


def collect():
    items = []
    root = CLAUDE / "CLAUDE.md"
    body = ""
    if root.is_file():
        body = read(root)
        items.append(("CLAUDE.md", root, est_tokens(body), "every session"))
        for imp in imports_of(body, CLAUDE):
            if imp.is_file():
                items.append((f"  import {imp.name}", imp, est_tokens(read(imp)), "every session"))
    on_demand = conditional_rules(body)
    for f in sorted((CLAUDE / "rules").glob("*.md")):
        when = "on demand" if f.name in on_demand else "every session"
        items.append((f"rule {f.name}", f, est_tokens(read(f)), when))
    mem = HOME / "second-brain/memory/MEMORY.md"
    if mem.is_file():
        items.append(("MEMORY.md", mem, est_tokens(read(mem)), "every session"))
    # Skill descriptions load for routing even when the skill body does not.
    desc = 0
    n = 0
    for f in (CLAUDE / "skills").glob("*/SKILL.md"):
        m = re.search(r"^description:\s*(.+)$", read(f), re.M)
        if m:
            desc += est_tokens(m.group(1))
            n += 1
    if n:
        items.append((f"{n} skill descriptions", CLAUDE / "skills", desc, "every session"))
    return items


def main():
    arg = sys.argv[1] if len(sys.argv) > 1 else ""
    items = collect()
    total = sum(i[2] for i in items if i[3] == "every session")
    deferred = sum(i[2] for i in items if i[3] != "every session")

    if arg == "--json":
        print(json.dumps({
            "budget_tokens": BUDGET_TOKENS,
            "total_tokens": total,
            "on_demand_tokens": deferred,
            "over_budget": total > BUDGET_TOKENS,
            "items": [{"name": a.strip(), "path": str(b), "tokens": c, "when": d}
                      for a, b, c, d in items],
        }, indent=2))
        return 0

    if arg == "--budget":
        if total > BUDGET_TOKENS:
            print(f"over budget: {total:,} tokens loaded before the user types "
                  f"(budget {BUDGET_TOKENS:,})", file=sys.stderr)
            return 1
        print(f"ok  {total:,} tokens always-on, budget {BUDGET_TOKENS:,}")
        return 0

    print("What loads before you type a word\n")
    for name, path, tokens, when in sorted(items, key=lambda i: -i[2]):
        if when != "every session":
            continue
        bar = "#" * min(40, tokens // 200)
        print(f"  {name:<32} {tokens:>7,} tok  {bar}")
    print(f"\n  {'ALWAYS ON':<32} {total:>7,} tok   budget {BUDGET_TOKENS:,}")
    later = [i for i in items if i[3] != "every session"]
    if later:
        print(f"\n  Loaded only when the task calls for it, not counted above:")
        for name, path, tokens, when in sorted(later, key=lambda i: -i[2]):
            print(f"  {name:<32} {tokens:>7,} tok")
        print(f"  {'':<32} {deferred:>7,} tok deferred")
    if total > BUDGET_TOKENS:
        over = total - BUDGET_TOKENS
        print(f"\n  Over by {over:,} tokens. Every session pays this before it starts.")
        print("  The largest file is the first place to look.")
    print("\n  Estimate: characters divided by four.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

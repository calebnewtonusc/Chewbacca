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
BUDGET_TOKENS = 15000  # what the kit may spend before the user's own work starts


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


def collect():
    items = []
    root = CLAUDE / "CLAUDE.md"
    if root.is_file():
        t = read(root)
        items.append(("CLAUDE.md", root, est_tokens(t), "every session"))
        for imp in imports_of(t, CLAUDE):
            if imp.is_file():
                items.append((f"  import {imp.name}", imp, est_tokens(read(imp)), "every session"))
    for f in sorted((CLAUDE / "rules").glob("*.md")):
        items.append((f"rule {f.name}", f, est_tokens(read(f)), "every session"))
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
    total = sum(i[2] for i in items if not i[0].startswith("  "))
    total += sum(i[2] for i in items if i[0].startswith("  "))

    if arg == "--json":
        print(json.dumps({
            "budget_tokens": BUDGET_TOKENS,
            "total_tokens": total,
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
        bar = "#" * min(40, tokens // 200)
        print(f"  {name:<32} {tokens:>7,} tok  {bar}")
    print(f"\n  {'TOTAL':<32} {total:>7,} tok   budget {BUDGET_TOKENS:,}")
    if total > BUDGET_TOKENS:
        over = total - BUDGET_TOKENS
        print(f"\n  Over by {over:,} tokens. Every session pays this before it starts.")
        print("  The largest file is the first place to look.")
    print("\n  Estimate: characters divided by four.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

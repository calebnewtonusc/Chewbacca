#!/usr/bin/env python3
"""Export the standards as a portable AGENTS.md.

Everything in this kit assumes Claude Code specifically: the frontmatter, the
hooks, the @import syntax. The standards themselves are not Claude-specific at
all, and there was no way to hand them to Codex, Cursor, or a plain API loop.

  python3 tools/agents_md.py            write AGENTS.md at the repo root
  python3 tools/agents_md.py <dir>      write it into another project

The output is one self-contained file with no imports, no frontmatter, and no
tool names that only exist here.
"""

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

# Sections of CLAUDE.md that only make sense inside this kit.
SKIP_SECTIONS = {
    "SESSION OPENER (CUSTOMIZABLE)",
    "MCP TOOLS: ALWAYS HAVE THESE ENABLED",
    "MAC TOOLS: USE THEM INSTEAD OF GUESSING",
    "CLASSES AND LIFE: READ THE LEDGER, NEVER GUESS A DATE",
    "MEMORY PROTOCOL: CLAUDE UPDATES CONTEXT AUTOMATICALLY",
    "README Footer (CUSTOMIZABLE)",
    "Always-on standards",
    "Task-specific rules (load automatically, not always in context)",
}


def sections(text):
    out, name, buf = [], None, []
    for line in text.splitlines():
        m = re.match(r"^## (.+)$", line)
        if m:
            if name is not None:
                out.append((name, "\n".join(buf).strip()))
            name, buf = m.group(1).strip(), []
        elif name is not None:
            buf.append(line)
    if name is not None:
        out.append((name, "\n".join(buf).strip()))
    return out


def main():
    dest = Path(sys.argv[1]) if len(sys.argv) > 1 else REPO
    parts = [
        "# AGENTS.md",
        "",
        "Coding and working standards, exported from Chewbacca so they can be used",
        "by any agent, not only Claude Code. Regenerate with",
        "`python3 tools/agents_md.py`; edit the sources, not this file.",
        "",
        "Sources: `CLAUDE.md` and `.claude/rules/*.md` in",
        "https://github.com/calebnewtonusc/Chewbacca",
        "",
        "---",
        "",
    ]
    kept = 0
    for name, body in sections((REPO / "CLAUDE.md").read_text(encoding="utf-8")):
        if name in SKIP_SECTIONS or not body:
            continue
        parts += [f"## {name}", "", body, ""]
        kept += 1

    for f in sorted((REPO / ".claude/rules").glob("*.md")):
        body = f.read_text(encoding="utf-8").strip()
        # Drop the file's own H1 so the export has one heading level scheme.
        body = re.sub(r"\A#\s+.*\n", "", body).strip()
        parts += [f"## {f.stem.replace('-', ' ').title()}", "", body, ""]
        kept += 1

    text = "\n".join(parts).rstrip() + "\n"
    # No @imports and no absolute home paths survive into a portable file.
    text = re.sub(r"^@~/.*$", "", text, flags=re.M)
    out = dest / "AGENTS.md"
    out.write_text(text, encoding="utf-8")
    print(f"wrote {out} from {kept} sections, {len(text.splitlines())} lines")
    return 0


if __name__ == "__main__":
    sys.exit(main())

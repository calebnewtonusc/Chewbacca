#!/usr/bin/env python3
"""Which CLI tools the installed skills say they need.

The mapping used to be hardcoded in doctor.sh, so a skill that started
depending on a new tool was only checked if somebody remembered to edit a list
in a different file. Each skill now declares `requires:` in its own frontmatter.

  python3 tools/skill_requires.py            tool:skill,skill  one per line
  python3 tools/skill_requires.py --json
"""

import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent


def collect():
    need = {}
    for f in sorted((REPO / "skills").glob("*/SKILL.md")):
        m = re.match(r"^---\n(.*?)\n---", f.read_text(encoding="utf-8", errors="ignore"), re.S)
        if not m:
            continue
        r = re.search(r"^requires:\s*\[(.*?)\]", m.group(1), re.M)
        if not r:
            continue
        for tool in [x.strip() for x in r.group(1).split(",") if x.strip()]:
            need.setdefault(tool, []).append(f.parent.name)
    return need


if __name__ == "__main__":
    need = collect()
    # chewbacca itself is promised by the README and every install path, and no
    # single skill owns that claim.
    need.setdefault("chewbacca", []).append("the README, every install path")
    if "--json" in sys.argv:
        print(json.dumps(need, indent=2))
    else:
        for tool, skills in sorted(need.items()):
            print(f"{tool}:{', '.join(skills)}")

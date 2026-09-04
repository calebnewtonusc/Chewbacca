#!/usr/bin/env python3
"""Write SHA256SUMS.txt for the files an install actually executes.

`curl | bash` with no checksum and no pinned release means every install is a
leap of faith, and the README invites exactly that. This does not make a
compromised repo safe. It catches a truncated download, a proxy that rewrote
something in flight, and a mirror that is not what it claims, and it gives
anyone a way to check that what landed on their machine is what is in git.

  python3 tools/checksums.py            write SHA256SUMS.txt
  python3 tools/checksums.py --check    exit 1 if it is stale (CI)
"""

import hashlib
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
OUT = REPO / "SHA256SUMS.txt"
# The files that run. Documentation changing does not need to invalidate this,
# and a checksum file that churns on every doc edit is one people stop reading.
PATTERNS = ("*.sh", "bin/*", "bin/lib/*", "tools/*.py", ".claude/hooks/*.sh")


def files():
    tracked = set(subprocess.run(["git", "-C", str(REPO), "ls-files"],
                                 capture_output=True, text=True).stdout.split())
    out = []
    for pat in PATTERNS:
        for p in sorted(REPO.glob(pat)):
            rel = str(p.relative_to(REPO))
            if p.is_file() and rel in tracked and rel != OUT.name:
                out.append(rel)
    return sorted(set(out))


def render():
    lines = []
    for rel in files():
        h = hashlib.sha256((REPO / rel).read_bytes()).hexdigest()
        lines.append(f"{h}  {rel}")
    return "\n".join(lines) + "\n"


def main():
    text = render()
    if "--check" in sys.argv:
        if OUT.is_file() and OUT.read_text() == text:
            print(f"ok  {len(text.splitlines())} checksums current")
            return 0
        print("SHA256SUMS.txt is stale. Run: python3 tools/checksums.py", file=sys.stderr)
        return 1
    OUT.write_text(text)
    print(f"wrote {OUT.name}: {len(text.splitlines())} files")
    return 0


if __name__ == "__main__":
    sys.exit(main())

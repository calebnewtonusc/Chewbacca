#!/usr/bin/env python3
"""Refuse a commit that changes a manifest-covered file without the manifest.

setup.sh verifies what it downloaded against SHA256SUMS.txt. When a file the
manifest covers is committed and the manifest is not regenerated, a fresh
install stops at verification.

This has happened twice. On 2026-09-19 a Stop hook pushed setup.sh without
checksums and install was dead on main until somebody tried it. On 2026-09-21
setup.sh was committed again without them, and `shasum -c` on the committed
manifest failed on setup.sh itself.

Both times the fix was one command. Neither time did anything ask for it.
"""
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
MANIFEST = "SHA256SUMS.txt"
PATTERNS = ("*.sh", "*.ps1", "bin/*", "bin/lib/*", "tools/*.py", ".claude/hooks/*.sh")


def staged():
    out = subprocess.run(["git", "-C", str(REPO), "diff", "--cached", "--name-only"],
                         capture_output=True, text=True).stdout.split()
    return set(out)


def covered(rel: str) -> bool:
    p = REPO / rel
    for pat in PATTERNS:
        if p in REPO.glob(pat):
            return True
    return False


def main() -> int:
    files = staged()
    if not files:
        return 0
    touched = sorted(f for f in files if f != MANIFEST and covered(f))
    if not touched:
        return 0
    if MANIFEST in files:
        return 0
    print("\nmanifest: refusing. These change files SHA256SUMS.txt covers, and", file=sys.stderr)
    print("the manifest is not in this commit. setup.sh verifies downloads", file=sys.stderr)
    print("against it, so a fresh install stops at verification.\n", file=sys.stderr)
    for f in touched:
        print(f"  {f}", file=sys.stderr)
    print("\n  python3 tools/checksums.py && git add SHA256SUMS.txt\n", file=sys.stderr)
    print("Override with SKIP_MANIFEST_GUARD=1 if you know the manifest is", file=sys.stderr)
    print("already correct for these.\n", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())

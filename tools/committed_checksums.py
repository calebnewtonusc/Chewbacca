#!/usr/bin/env python3
"""Verify SHA256SUMS.txt against COMMITTED file contents, not the working tree.

THE FAILURE THIS EXISTS FOR. tools/checksums.py hashes what is on disk. Run it
while a tracked file has uncommitted edits and it records the hash of a version
nobody has committed, `--check` then passes, and the commit ships a checksum for
content that exists on one laptop. That happened: main published a hash for
.claude/hooks/kit-autopush.sh that its own committed hook did not have, and
start.sh and start.ps1 both refused to install, because verifying the download
against SHA256SUMS.txt is the entire point of that file.

The working-tree check cannot see this by construction. It compares disk to
disk. This compares what git would hand a stranger to what the manifest claims,
which is the only comparison an installer actually performs.

  python3 tools/committed_checksums.py            check HEAD
  python3 tools/committed_checksums.py <rev>      check any revision
"""

import hashlib
import subprocess
import sys
from fnmatch import fnmatch
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
# Kept in step with tools/checksums.py. A pattern added there and not here
# means a file the installer verifies that this never looks at.
PATTERNS = ("*.sh", "*.ps1", "bin/*", "bin/lib/*", "tools/*.py", ".claude/hooks/*.sh",
            "runtimes/*.json")
MANIFEST = "SHA256SUMS.txt"


def git(*args):
    return subprocess.run(["git", "-C", str(REPO), *args],
                          capture_output=True, text=True)


def blob(rev, path):
    """The committed bytes of one path, or None if it is not in that tree."""
    r = subprocess.run(["git", "-C", str(REPO), "show", f"{rev}:{path}"],
                       capture_output=True)
    return r.stdout if r.returncode == 0 else None


def main():
    rev = sys.argv[1] if len(sys.argv) > 1 else "HEAD"

    raw = blob(rev, MANIFEST)
    if raw is None:
        print(f"{MANIFEST} is not committed at {rev}", file=sys.stderr)
        return 1

    claimed = {}
    for line in raw.decode().splitlines():
        if not line.strip():
            continue
        digest, _, path = line.partition("  ")
        claimed[path] = digest

    tracked = git("ls-tree", "-r", "--name-only", rev).stdout.split("\n")
    tracked = [t for t in tracked if t]

    # Which paths the manifest is supposed to cover at this revision.
    #
    # Segment-wise, because Path.match anchors from the RIGHT: it says
    # mac/bin/chewie matches "bin/*", which checksums.py's REPO.glob does not.
    # Getting that wrong makes this report a missing entry that should never
    # have been there, which is a false alarm on a gate that blocks pushes.
    def glob_match(path, pat):
        pp, tt = pat.split("/"), path.split("/")
        return len(pp) == len(tt) and all(fnmatch(a, b) for a, b in zip(tt, pp))

    expected = {t for pat in PATTERNS for t in tracked
                if t != MANIFEST and glob_match(t, pat)}

    problems = []

    for path in sorted(expected - set(claimed)):
        problems.append(f"not in {MANIFEST}: {path}")
    for path in sorted(set(claimed) - expected):
        problems.append(f"listed but not a tracked match at {rev}: {path}")

    for path in sorted(expected & set(claimed)):
        content = blob(rev, path)
        if content is None:
            problems.append(f"listed but missing from the tree: {path}")
            continue
        actual = hashlib.sha256(content).hexdigest()
        if actual != claimed[path]:
            problems.append(
                f"committed content does not match the committed hash: {path}\n"
                f"        manifest says {claimed[path]}\n"
                f"        tree hashes to {actual}")

    if problems:
        print(f"{MANIFEST} at {rev} does not describe {rev}:", file=sys.stderr)
        for p in problems:
            print(f"  {p}", file=sys.stderr)
        print("\n  An install verifies the download against this file, so it "
              "would refuse.\n  Run: python3 tools/checksums.py  (with a clean "
              "working tree) and amend.", file=sys.stderr)
        return 1

    print(f"ok  {len(expected)} committed checksums describe {rev}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

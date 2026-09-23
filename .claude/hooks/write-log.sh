#!/bin/bash
# Resolve both checkout hooks and copies installed in ~/.claude/hooks.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
exec python3 -c '
import os
from pathlib import Path
import runpy
import shutil
import sys
roots = [Path(sys.argv[1])]
if os.environ.get("CHEWBACCA_ROOT"):
    roots.insert(0, Path(os.environ["CHEWBACCA_ROOT"]).expanduser())
launchers = [Path.home() / ".local/bin/chewbacca"]
if shutil.which("chewbacca"):
    launchers.append(Path(shutil.which("chewbacca")))
roots.extend(path.resolve().parent.parent for path in launchers if path.is_file())
for root in roots:
    script = root / "tools/write_log.py"
    if script.is_file():
        runpy.run_path(str(script), run_name="__main__")
        break
else:
    print("write-log: shared checkout unavailable; durability evidence may be incomplete.", file=sys.stderr)
' "$ROOT"

#!/bin/bash
# tools/checksums.py and tools/committed_checksums.py must cover the same files.
#
# WHY. checksums.py writes SHA256SUMS.txt from disk; committed_checksums.py
# verifies that manifest against what git would hand a stranger. They each keep
# their own PATTERNS tuple, and committed_checksums.py already carried a comment
# saying they must be kept in step.
#
# On 2026-09-22 they were not. checksums.py had gained "runtimes/*.json" and the
# other had not, so the manifest listed runtimes/profiles.json and the verifier
# could not account for the entry. It reported HEAD as undescribed while the
# hash was byte-identical in the manifest, on disk and at HEAD. A false positive
# in the one gate whose whole job is telling you an install would refuse, which
# also blocked every auto-push.
#
# A comment asking two lists to stay equal is not a mechanism. This is.
set -uo pipefail
ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"

exec python3 - "$ROOT" <<'PY'
import ast, pathlib, sys

root = pathlib.Path(sys.argv[1])

def patterns(rel):
    tree = ast.parse((root / rel).read_text())
    for node in tree.body:
        if isinstance(node, ast.Assign):
            for t in node.targets:
                if isinstance(t, ast.Name) and t.id == "PATTERNS":
                    return set(ast.literal_eval(node.value))
    raise SystemExit(f"FAIL: no PATTERNS in {rel}")

a = patterns("tools/checksums.py")
b = patterns("tools/committed_checksums.py")

if a != b:
    print("FAIL: PATTERNS have drifted apart.")
    for p in sorted(a - b):
        print(f"  in checksums.py only:           {p}  (manifest lists it, verifier cannot account for it)")
    for p in sorted(b - a):
        print(f"  in committed_checksums.py only: {p}  (verifier expects it, manifest never records it)")
    raise SystemExit(1)

print(f"ok    both checksum tools cover the same {len(a)} patterns")
PY

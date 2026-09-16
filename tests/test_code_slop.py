"""Tests for bin/code-slop.

The property that decides whether this tool is worth having is the false
positive rate, not the catch rate. slop-check already learned where a noisy
checker ends: "a checker that is always red gets ignored." So the cases below
are split in two, and the second half is the important half.

    python3 tests/test_code_slop.py
"""

import json
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
TOOL = ROOT / "bin" / "code-slop"

PASSED = FAILED = 0


def scan(source, suffix=".js"):
    with tempfile.NamedTemporaryFile("w", suffix=suffix, delete=False) as fh:
        fh.write(source)
        path = fh.name
    out = subprocess.run(
        [sys.executable, str(TOOL), path, "--json"], capture_output=True, text=True
    )
    return json.loads(out.stdout)


def check(name, condition, detail=""):
    global PASSED, FAILED
    if condition:
        PASSED += 1
        print(f"  pass  {name}")
    else:
        FAILED += 1
        print(f"  FAIL  {name}  {detail}")


def rules(result):
    return sorted(f["rule"] for f in result["findings"])


# ── it catches the real tells ────────────────────────────────────────────────

r = scan("// loop over the entries\nfor (const e of es) {}\n")
check("narration: a loop comment above a loop", rules(r) == ["narration"], rules(r))

r = scan("// First, get the user\nu();\n")
check("narration: a sequencer with an imperative verb", rules(r) == ["narration"], rules(r))

r = scan("// this is safe because we checked above\nx();\n")
check("reviewer-talk", rules(r) == ["reviewer-talk"], rules(r))

r = scan("// as requested in the review\nx();\n")
check("review-reference", rules(r) == ["review-reference"], rules(r))

r = scan("// This function returns the user\nfunction u() {}\n")
check("self-reference", rules(r) == ["self-reference"], rules(r))

r = scan("// ---- helpers ----\nx();\n")
check("banner", rules(r) == ["banner"], rules(r))

r = scan("// TODO\nx();\n")
check("placeholder: a bare marker", rules(r) == ["placeholder"], rules(r))

r = scan("// TODO(caleb): parse the tail\nx();\n")
check("placeholder: an owned marker is tracked work, not slop", r["findings"] == [], rules(r))

# A placeholder must not hide behind a neighbouring finding. The first version
# reported the banner and silently dropped the TODO on the line below it.
r = scan("// ---- helpers ----\n// TODO\nx();\n")
check("a placeholder is never swallowed by its block", "placeholder" in rules(r), rules(r))


# ── it stays quiet on real code, which is the harder half ────────────────────

# Every one of these is a real comment from this repo, or a shape the scanner
# reported against itself and should not have.

r = scan(
    "// Nobody has eleven relatives called USC, so it is a label.\n"
    "const n = freq(corpus, raw);\n"
)
check("a constraint-stating comment is not a finding", r["findings"] == [], rules(r))

r = scan(
    "// First run takes a bounded window. A full history is 600k+ rows on a\n"
    "// real machine and the scan has to finish.\n"
    "run();\n"
)
check("'First run takes' is a constraint, not a sequencer", r["findings"] == [], rules(r))

r = scan("// FIRST, EVERY CONNECTION GETS A ROW.\nwrite();\n")
check("an emphatic invariant is not narration", r["findings"] == [], rules(r))

# The bug the scanner found in itself on its first real run: a wrapped
# paragraph whose continuation line happens to begin with a sequencer.
r = scan(
    "// AN ACRONYM SHARED BY THREE PEOPLE, anywhere in the field including\n"
    "// where a first name would go. This is the case the old SOFT list was\n"
    "// written for, and the guard is the whole of it.\n"
    "check();\n"
)
check("a wrapped paragraph is one comment, not three", r["findings"] == [], rules(r))

r = scan(
    "# TODO is a discrete piece of unfinished work, and collapsing it into a\n"
    "# neighbouring comment hides it entirely.\n"
    "run()\n",
    suffix=".py",
)
check("prose that opens with the word TODO is not a marker", r["findings"] == [], rules(r))

r = scan("// eslint-disable-next-line no-console\nx();\n// @ts-nocheck\ny();\n")
check("linter and type directives are not comments", r["findings"] == [], rules(r))

r = scan("#!/usr/bin/env python3\nimport os\n", suffix=".py")
check("a shebang is not a comment", r["findings"] == [], rules(r))

r = scan("const x = 1;  // why this is 1 and not 0\n")
check("a trailing comment is left alone", r["findings"] == [], rules(r))


# ── the repo itself has to come back clean ───────────────────────────────────

targets = [
    str(ROOT / "bin" / "people"),
    str(ROOT / "bin" / "code-slop"),
    str(ROOT / "bin" / "slop-check"),
] + [str(p) for p in (ROOT / "bin" / "lib").glob("*.js")]
out = subprocess.run(
    [sys.executable, str(TOOL)] + targets + ["--json"], capture_output=True, text=True
)
repo = json.loads(out.stdout)
check(
    "this codebase scores zero",
    repo["score"] == 0,
    f"score {repo['score']}: {[(f['file'].split('/')[-1], f['line'], f['rule']) for f in repo['findings']]}",
)
# Density is deliberately not scored, so the high-comment house style must not
# be able to fail the check no matter how far it goes.
check("density does not contribute to the score", repo["density"] > 0.10, repo["density"])

print(f"\n{PASSED} passed, {FAILED} failed.")
sys.exit(1 if FAILED else 0)

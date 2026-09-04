#!/usr/bin/env python3
"""Run the skill evals.

Nine skills had eval files and nothing ever executed them. Twelve had none at
all. This does two things:

  chewbacca evals            structure and coverage, no model, runs in CI
  chewbacca evals --run      behavioral, shells out to `claude -p` if present
  chewbacca evals --run <skill>   just one

The no-model pass is the one CI runs. It checks that every eval file parses,
that every case has a prompt and an expectation, that the skill it names
exists, and that the skill's own description plausibly covers the prompt.
That last check is a proxy for trigger accuracy and is labeled as one.
"""

import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SKILLS = REPO / "skills"
STOP = set("the a an is my what how do i to of on in for me and or it that this "
           "with at from what's whats can you your").split() if False else {
    "the", "a", "an", "is", "my", "what", "how", "do", "i", "to", "of", "on",
    "in", "for", "me", "and", "or", "it", "that", "this", "with", "at", "from",
    "can", "you", "your", "are", "be", "was", "were", "should", "would",
}


def words(text):
    return {w for w in re.findall(r"[a-z]{3,}", text.lower()) if w not in STOP}


def check():
    files = sorted(SKILLS.glob("*/evals/evals.json"))
    all_skills = sorted(p.parent.name for p in SKILLS.glob("*/SKILL.md"))
    missing = [s for s in all_skills if not (SKILLS / s / "evals/evals.json").is_file()]
    problems = []
    cases = 0
    weak = []

    for f in files:
        skill_dir = f.parent.parent
        try:
            data = json.loads(f.read_text(encoding="utf-8"))
        except json.JSONDecodeError as e:
            problems.append(f"{f.relative_to(REPO)}: not valid JSON: {e}")
            continue
        if data.get("skill") != skill_dir.name:
            problems.append(f"{f.relative_to(REPO)}: skill field says "
                            f"'{data.get('skill')}', directory says '{skill_dir.name}'")
        body = (skill_dir / "SKILL.md").read_text(encoding="utf-8", errors="ignore")
        m = re.search(r"^description:\s*(.+)$", body, re.M)
        desc = words(m.group(1)) if m else set()
        for i, c in enumerate(data.get("cases", [])):
            cases += 1
            where = f"{f.relative_to(REPO)} case {i + 1}"
            if not c.get("prompt"):
                problems.append(f"{where}: no prompt")
            # Any expect_* key counts. The first version of this check only
            # knew expect_tools and called thirteen good cases broken, which
            # is the exact failure mode it exists to catch.
            if not any(k.startswith("expect") or k == "reject" for k in c):
                problems.append(f"{where}: no expectation, so it can never fail")
            # Trigger proxy: does anything in the prompt appear in the routing
            # description? A prompt sharing no vocabulary with the description
            # is a skill that will not load when it should.
            # A prompt that shares no vocabulary with either the routing
            # description or the skill body will not load the skill when it
            # should. Checking the body too keeps this from firing on every
            # naturally worded prompt.
            p = words(c.get("prompt", ""))
            if desc and p and not (p & desc) and not (p & words(body)):
                weak.append(f"{where}: prompt shares no vocabulary with the "
                            f"skill at all, so routing to it is luck")

    print(f"{len(files)} eval file(s), {cases} case(s), {len(all_skills)} skills\n")
    for p in problems:
        print(f"  FAIL  {p}")
    for w in weak:
        print(f"  warn  {w}")
    if missing:
        print(f"\n  {len(missing)} skill(s) with no evals:")
        for s in missing:
            print(f"    {s}")
    if problems:
        print(f"\n{len(problems)} problem(s).")
        return 1
    print(f"\nok  every eval file is well formed"
          f"{f', {len(weak)} weak trigger(s)' if weak else ''}"
          f"{f', {len(missing)} skill(s) uncovered' if missing else ''}")
    return 0


def run(only=None):
    if not shutil.which("claude"):
        print("claude CLI not found, so behavioral evals cannot run here.", file=sys.stderr)
        print("The structure pass still works: chewbacca evals", file=sys.stderr)
        return 2
    files = sorted(SKILLS.glob("*/evals/evals.json"))
    if only:
        files = [f for f in files if f.parent.parent.name == only]
        if not files:
            print(f"no evals for '{only}'", file=sys.stderr)
            return 2
    passed = failed = 0
    for f in files:
        data = json.loads(f.read_text(encoding="utf-8"))
        skill = data["skill"]
        print(f"\n{skill}")
        for c in data.get("cases", []):
            prompt = c["prompt"]
            want = c.get("expect_tools", [])
            try:
                out = subprocess.run(
                    ["claude", "-p", f"{prompt}\n\n(Say which tools and skills you "
                                     f"would use. Do not actually run them.)"],
                    capture_output=True, text=True, timeout=120,
                ).stdout.lower()
            except subprocess.TimeoutExpired:
                print(f"  TIMEOUT  {prompt[:60]}")
                failed += 1
                continue
            hits = [w for w in want if w.lower() in out]
            rejects = [r for r in c.get("reject", []) if r.lower() in out]
            good = len(hits) == len(want) and not rejects
            print(f"  {'pass' if good else 'FAIL'}  {prompt[:58]}")
            if not good:
                miss = [w for w in want if w.lower() not in out]
                if miss:
                    print(f"        missing: {', '.join(miss)}")
                if rejects:
                    print(f"        did the rejected thing: {', '.join(rejects)}")
            passed += good
            failed += not good
    print(f"\n{passed} passed, {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    args = sys.argv[1:]
    if args and args[0] == "--run":
        sys.exit(run(args[1] if len(args) > 1 else None))
    sys.exit(check())

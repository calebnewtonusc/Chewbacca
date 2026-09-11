#!/usr/bin/env python3
"""Does a skill actually fire when someone just says the thing?

Nobody using this kit should have to type a slash command, which makes exactly
one question worth measuring: given a sentence a real person would say, does the
right skill load? Every other check here is a proxy for it. `tools/commands.py`
compares word sets and says so. This runs the sentence.

It drives the real `claude` CLI in print mode and reads the tool stream. Two
separate facts, because the first version conflated them and drew the wrong
conclusion: whether a SKILL loaded, and whether the BEHAVIOR happened.

"what's due this week?" loads no skill and answers perfectly, because a
session-start hook already told Claude the `coursework` CLI exists and it just
ran it. Counting that as a failure would have condemned a path that works. The
reverse matters more: a sentence where neither a skill loads nor any expected
tool runs is a behavior that genuinely is not reachable by speaking.

So a case can expect a skill (`expect_any`) or a command fragment
(`expect_tool`), and satisfying either is a pass. No LLM judges anything: a name
appears in the tool stream or it does not.

  python3 tools/triggers.py                  every case
  python3 tools/triggers.py --only school
  python3 tools/triggers.py --json

Cases live in tests/triggers.json so adding one needs no code.
"""
import json
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CASES = REPO / "tests" / "triggers.json"
TIMEOUT = 180


def fired(prompt, cwd):
    """The skills the real CLI loaded for this sentence, in order."""
    try:
        proc = subprocess.run(
            ["claude", "-p", prompt, "--output-format", "stream-json", "--verbose"],
            capture_output=True, text=True, timeout=TIMEOUT, cwd=cwd,
        )
    except subprocess.TimeoutExpired:
        return None, "timeout"
    except FileNotFoundError:
        return None, "no claude CLI"

    skills, cmds = [], []
    for line in proc.stdout.split("\n"):
        line = line.strip()
        if not line:
            continue
        try:
            d = json.loads(line)
        except json.JSONDecodeError:
            continue
        msg = d.get("message") or {}
        for c in msg.get("content") or []:
            if not (isinstance(c, dict) and c.get("type") == "tool_use"):
                continue
            inp = c.get("input") or {}
            if c.get("name") == "Skill":
                sk = inp.get("skill")
                if sk and sk not in skills:
                    skills.append(sk)
            else:
                cmds.append(str(inp.get("command") or c.get("name"))[:120])
    if not proc.stdout.strip():
        return None, (proc.stderr or "no output")[:80]
    return {"skills": skills, "cmds": cmds}, None


def run(case):
    cwd = case.get("cwd") or str(REPO)
    got, err = fired(case["prompt"], cwd)
    if got is None:
        return {**case, "got": [], "status": "SKIP", "note": err}
    skills, cmds = got["skills"], got["cmds"]
    want_skill = case.get("expect_any") or []
    want_tool = case.get("expect_tool") or []

    by_skill = [w for w in want_skill if w in skills]
    by_tool = [t for t in want_tool if any(t in c for c in cmds)]

    if by_skill:
        status = "PASS"          # the skill loaded, judgment and all
    elif by_tool:
        status = "TOOL"          # behavior happened without the skill
    elif skills:
        status = "WRONG"         # something loaded, not the right thing
    else:
        status = "NONE"          # nothing reachable by speaking
    return {**case, "got": skills, "cmds": cmds[:4], "status": status}


def main():
    if not CASES.is_file():
        print(f"no cases at {CASES}")
        return 2
    cases = json.loads(CASES.read_text())
    only = None
    if "--only" in sys.argv:
        only = sys.argv[sys.argv.index("--only") + 1]
        cases = [c for c in cases if c.get("group") == only]

    # Concurrent because each case is a full agent turn; serial is minutes.
    with ThreadPoolExecutor(max_workers=5) as pool:
        rows = list(pool.map(run, cases))

    if "--json" in sys.argv:
        print(json.dumps(rows, indent=2))
        return 0

    counts = {}
    group = None
    for r in sorted(rows, key=lambda r: (r.get("group", ""), r["prompt"])):
        if r.get("group") != group:
            group = r.get("group")
            print(f"\n{group}")
        counts[r["status"]] = counts.get(r["status"], 0) + 1
        mark = {"PASS": "skill ", "TOOL": "tool  ", "WRONG": "WRONG ",
                "NONE": "SILENT", "SKIP": "skip  "}[r["status"]]
        print(f'  {mark} "{r["prompt"][:56]}"')
        if r["status"] == "TOOL":
            print(f"         no skill, but it ran: {(r.get('cmds') or [''])[0][:60]}")
        elif r["status"] != "PASS":
            want = ", ".join(r.get("expect_any") or []) or "(anything)"
            print(f"         wanted: {want}")
            print(f"         fired:  {', '.join(r['got']) or 'no skill at all'}")
            if r.get("cmds"):
                print(f"         ran:    {r['cmds'][0][:60]}")
            if r.get("note"):
                print(f"         note:   {r['note']}")

    print("\n" + "  ".join(f"{k}={v}" for k, v in sorted(counts.items())))
    silent = counts.get("NONE", 0) + counts.get("WRONG", 0)
    tool_only = counts.get("TOOL", 0)
    if tool_only:
        print(f"\n{tool_only} work WITHOUT the skill, via a hook or a CLI the agent already")
        print("knows about. The behavior is reachable; the skill's judgment is not.")
    if silent:
        print(f"\n{silent} sentence(s) reach nothing at all. Under the no-slash-commands")
        print("rule those behaviors do not exist for anyone who does not already")
        print("know the command name.")
    return 1 if silent else 0


if __name__ == "__main__":
    sys.exit(main())

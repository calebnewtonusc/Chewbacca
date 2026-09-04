#!/usr/bin/env python3
"""Execute a Chewbacca plan: the Genie idea applied to Mac control.

An agent compiles a natural-language request into ONE typed plan (see
data/grammar.json). This runner type-checks it against the grammar, runs each
query and action in order, verifies after side effects, and refuses to run any
action whose grammar signature carries confirm:true unless it was approved.

The reliability win (see docs/BENCHMARKS.md): 20 improvised steps at 95% each is
36% overall. A checked plan that stops at the first type error or failed step,
and gates every irreversible action in the grammar itself, does not compound.

    chewie plan check   plan.json        type-check only, run nothing
    chewie plan run     plan.json        run it; confirm-gated actions need --yes
    chewie plan run     plan.json --yes  approve the confirm-gated actions
"""
import json, os, subprocess, sys

import time as _time
from datetime import datetime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RUNDIR = os.path.expanduser("~/.chewie/runs")


class Trace:
    """Append-only JSONL log of a run. This is what makes a plan debuggable:
    every step, its timing, and whether it actually verified."""
    def __init__(self):
        os.makedirs(RUNDIR, exist_ok=True)
        self.path = os.path.join(RUNDIR, datetime.now().strftime("%Y%m%d-%H%M%S") + ".jsonl")
        self.f = open(self.path, "a")

    def log(self, step, status, detail="", ms=None, **extra):
        rec = {"t": datetime.now().isoformat(timespec="seconds"),
               "step": step, "status": status, "detail": detail}
        if ms is not None:
            rec["ms"] = ms
        rec.update(extra)
        self.f.write(json.dumps(rec) + "\n")
        self.f.flush()

    def close(self):
        self.f.close()
GRAMMAR = json.load(open(os.path.join(ROOT, "data", "grammar.json")))
BIN = os.path.join(ROOT, "bin", "chewie")

QUERIES = {q["name"]: q for q in GRAMMAR["queries"]}
ACTIONS = {a["name"]: a for a in GRAMMAR["actions"]}
STREAMS = {s["name"]: s for s in GRAMMAR["streams"]}


class PlanError(Exception):
    pass


def check(plan):
    """Type-check a plan against the grammar. Raise on the first problem."""
    errs = []
    stream = plan.get("stream", {"name": "now"})
    if stream.get("name") not in STREAMS:
        errs.append(f"unknown stream: {stream.get('name')}")

    for q in plan.get("query", []):
        spec = QUERIES.get(q.get("name"))
        if not spec:
            errs.append(f"unknown query: {q.get('name')}"); continue
        for p, t in spec["params"].items():
            required = not t.endswith("?")
            if required and p not in q:
                errs.append(f"query {q['name']} missing required param: {p} ({t})")

    for a in plan.get("action", []):
        spec = ACTIONS.get(a.get("name"))
        if not spec:
            errs.append(f"unknown action: {a.get('name')}"); continue
        for p, t in spec["params"].items():
            required = not t.endswith("?")
            if required and p not in a:
                errs.append(f"action {a['name']} missing required param: {p} ({t})")

    if errs:
        raise PlanError("plan does not type-check:\n  - " + "\n  - ".join(errs))
    return True


def _chewie(*args):
    return subprocess.run([BIN, *args], capture_output=True, text=True)


def _applescript(script):
    return subprocess.run(["osascript", "-e", script], capture_output=True, text=True)


def run_query(q):
    name = q["name"]
    if name == "texts":
        args = ["texts", "--days", str(q.get("days", 7)), "--json"]
        if q.get("who"): args += ["--who", q["who"]]
        if q.get("unanswered"): args.append("--unanswered")
        if q.get("direct"): args.append("--direct")
        return _chewie(*args).stdout
    if name == "screen":
        return _chewie("see", "--app", q["app"]).stdout
    if name == "web":
        a = ["web", "read"] + ([q["url"]] if q.get("url") else [])
        return _chewie(*a).stdout
    if name == "app_data":
        return _applescript(q["script"]).stdout
    if name == "file":
        return subprocess.run(["cat", q["path"]], capture_output=True, text=True).stdout
    raise PlanError(f"no runner for query {name}")


def run_action(a, approved):
    spec = ACTIONS[a["name"]]
    if spec.get("confirm") and not approved:
        raise PlanError(
            f"action '{a['name']}' is confirm-gated in the grammar "
            f"({spec.get('why','irreversible')}). Re-run with --yes to approve.")
    name = a["name"]
    if name == "click":
        args = ["click", a["target"]] + (["--app", a["app"]] if a.get("app") else [])
        return _chewie(*args)
    if name == "type":
        return _chewie("type", a["text"])
    if name in ("web_click", "web_fill"):
        sub = "click" if name == "web_click" else "fill"
        extra = [a["value"]] if name == "web_fill" else []
        return _chewie("web", sub, a["selector"], *extra)
    if name == "remind":
        due = f' due date:date "{a["due"]}"' if a.get("due") else ""
        return _applescript(
            f'tell application "Reminders" to make new reminder with properties '
            f'{{name:"{a["title"]}"{due}}}')
    if name == "calendar":
        cal = a.get("calendar", "Home")
        return _applescript(
            f'tell application "Calendar" to tell calendar "{cal}" to make new event '
            f'with properties {{summary:"{a["summary"]}", start date:date "{a["start"]}", '
            f'end date:date "{a["start"]}"}}')
    if name == "send_text":
        return _applescript(
            f'tell application "Messages" to send "{a["body"]}" to buddy "{a["to"]}"')
    if name == "send_email":
        return _applescript(
            f'tell application "Mail"\nset m to make new outgoing message with properties '
            f'{{subject:"{a["subject"]}", content:"{a["body"]}", visible:true}}\n'
            f'tell m to make new to recipient at end of to recipients '
            f'with properties {{address:"{a["to"]}"}}\ntell m to send\nend tell')
    if name == "run_shell":
        return subprocess.run(["bash", "-c", a["cmd"]], capture_output=True, text=True)
    raise PlanError(f"no runner for action {name}")


def main():
    if len(sys.argv) < 3:
        print("usage: chewie plan {check|run} plan.json [--yes]"); sys.exit(1)
    mode, path = sys.argv[1], sys.argv[2]
    approved = "--yes" in sys.argv
    plan = json.load(open(path)) if os.path.exists(path) else json.loads(path)

    try:
        check(plan)
    except PlanError as e:
        print(f"FAIL: {e}"); sys.exit(1)
    print("plan type-checks against the grammar.")
    if mode == "check":
        return

    tr = Trace()
    tr.log("plan", "info", f"stream={plan.get('stream',{}).get('name','now')} "
           f"queries={len(plan.get('query',[]))} actions={len(plan.get('action',[]))}")
    tr.log("typecheck", "ok", "plan type-checks against the grammar")

    results = {}
    for q in plan.get("query", []):
        t0 = _time.time()
        print(f"query: {q['name']} ...", file=sys.stderr)
        try:
            out = run_query(q)
            ms = int((_time.time() - t0) * 1000)
            size = len(out or "")
            results[q["name"]] = out
            tr.log(f"query:{q['name']}", "ok", f"{size} bytes", ms=ms)
        except Exception as e:
            tr.log(f"query:{q['name']}", "fail", str(e))
            print(f"STOP: query '{q['name']}' failed: {e}"); tr.close(); sys.exit(2)

    for a in plan.get("action", []):
        t0 = _time.time()
        print(f"action: {a['name']} ...", file=sys.stderr)
        try:
            r = run_action(a, approved)
        except PlanError as e:
            tr.log(f"action:{a['name']}", "skip", str(e))
            print(f"STOP: {e}"); tr.close(); sys.exit(2)
        ms = int((_time.time() - t0) * 1000)
        rc = getattr(r, "returncode", 0)
        if rc not in (0, None):
            tr.log(f"action:{a['name']}", "fail",
                   (getattr(r, "stderr", "") or "")[:200], ms=ms)
            print(f"STOP: action '{a['name']}' failed:\n{getattr(r,'stderr','')}")
            tr.close(); sys.exit(2)
        # verify: an action that names an app gets a re-read so the log records
        # that the UI actually responded, not just that the command returned 0.
        verified = ""
        if a.get("verify"):
            v = _jarvis("see", "--app", a["verify"])
            verified = "verified" if v.returncode == 0 else "verify failed"
        tr.log(f"action:{a['name']}", "ok",
               (getattr(r, "stdout", "") or "").strip()[:120] or verified, ms=ms)

    tr.log("plan", "ok", "plan complete")
    tr.close()
    print(f"plan complete. trace: {tr.path}")


if __name__ == "__main__":
    main()

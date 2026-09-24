#!/usr/bin/env python3
"""Practice set for LinkedIn: can the assistant find the page and the control, fast?

Each row in cases.tsv is something a person says, the LinkedIn page(s) it belongs on, and
the control(s) that do it. Three things are scored, and nothing is ever clicked:

    PAGE     Jev picks the page from pages.tsv (the descriptions only), the first step
    POINTER  Jev picks the control from that page's saved snapshot, the second step
    FRESH    the accepted control is still on the page; a miss means LinkedIn changed it

Snapshots come from map.sh and live in the private folder, so run map.sh first when they
are older than a week. Each run appends one line to results.jsonl in that folder, so the
score has a history.

    python3 eval.py            # needs TYPESAFE_API_KEY or the Keychain entry
"""
import datetime as dt
import json
import os
import pathlib
import re
import statistics
import sys
import time
from concurrent.futures import ThreadPoolExecutor

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent.parent / "bin" / "lib"))
import jev  # noqa: E402

DATA = pathlib.Path(os.environ.get("LINKEDIN_UX_DIR", pathlib.Path.home() / "dev/gavin-context/research/linkedin-ux"))
MAX_OPTIONS = 255  # the API's ceiling on choices
# Act without asking only at or above this; set from tests/eval_ground_jev.py on 2026-09-23
# (results kept private under TypeSafe's agreement 2.3(f)). Re-set it from this file's own runs.
ACT_FLOOR = 0.7


def pages():
    out = {}
    for line in (HERE / "pages.tsv").read_text().splitlines():
        slug, url, what = line.split("\t")
        out[slug] = {"url": url, "what": what}
    return out


def cases():
    rows = []
    for line in (HERE / "cases.tsv").read_text().splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        where, said, accepted = line.split("\t")
        rows.append({"pages": where.split("|"), "said": said,
                     "accepted": [a.split(": ", 1) for a in accepted.split("|")]})
    return rows


def labels(slug):
    snap = json.loads((DATA / "pages" / f"{slug}.json").read_text())
    rest, links = [], []
    for c in snap["controls"]:
        (links if c["role"] == "link" else rest).append(f"{c['role']}: {c['name']}")
    return snap["title"], (rest + links)[:MAX_OPTIONS]


def ok(label, accepted):
    role, name = label.split(": ", 1)
    return any(role == r and re.search(rx, name) for r, rx in accepted)


def ask(state, question, keys):
    t = time.monotonic()
    a = ((jev.ask(state, {"q": {"type": "choice", "instructions": question, "criteria": keys}}, timeout=10) or {}).get("q")) or {}
    probs = sorted((a.get("probabilities") or {}).items(), key=lambda kv: -kv[1])
    return a.get("choice"), (probs[0][1] if probs else 0.0), time.monotonic() - t


def judge(row, page_keys):
    got, p_conf, p_secs = ask(
        f'Someone signed in to LinkedIn says: "{row["said"]}"',
        "Which LinkedIn page should be opened to do what they asked?",
        page_keys)
    slug = row["pages"][0]
    title, opts = labels(slug)
    fresh = any(ok(l, row["accepted"]) for l in opts)
    keys = {f"c{i}": l for i, l in enumerate(opts)}
    c, c_conf, c_secs = ask(
        f'On the LinkedIn page "{title}", the person says: "{row["said"]}"',
        "Which control on this page should be clicked or used to do what the person asked?",
        keys)
    pick = keys.get(c)
    return {"said": row["said"], "page_want": row["pages"], "page_got": got, "page_ok": got in row["pages"],
            "page_conf": round(p_conf, 2), "pick": pick, "pick_ok": bool(pick and ok(pick, row["accepted"])),
            "pick_conf": round(c_conf, 2), "fresh": fresh, "seconds": round(p_secs + c_secs, 2),
            "pick_seconds": round(c_secs, 2)}


def main():
    if not jev.api_key():
        print("No TYPESAFE_API_KEY in the environment or the Keychain.")
        return 2
    ps = pages()
    page_keys = {slug: f"{p['what']} ({p['url']})" for slug, p in ps.items()}
    rows = cases()
    with ThreadPoolExecutor(max_workers=6) as pool:
        res = list(pool.map(lambda r: judge(r, page_keys), rows))
    for r in res:
        mark = ("ok  " if r["page_ok"] and r["pick_ok"] else "MISS") + ("" if r["fresh"] else " STALE")
        print(f"{mark} page {r['page_got']!s:13} {r['page_conf']:.2f}  pick {r['pick_conf']:.2f} {r['pick']!s:48.48}  {r['said']}")
    n = len(res)
    acted = [r for r in res if r["pick_conf"] >= ACT_FLOOR]
    snaps = sorted((DATA / "pages").glob("*.json"))
    oldest = min(dt.date.fromtimestamp(p.stat().st_mtime) for p in snaps).isoformat() if snaps else None
    summary = {
        "run": dt.datetime.now().isoformat(timespec="seconds"), "cases": n, "snapshots_from": oldest,
        "page": sum(r["page_ok"] for r in res), "pointer": sum(r["pick_ok"] for r in res),
        "both": sum(r["page_ok"] and r["pick_ok"] for r in res), "stale": sum(not r["fresh"] for r in res),
        "acted_at_floor": len(acted), "acted_right": sum(r["pick_ok"] for r in acted),
        "p50_s": round(statistics.median(r["seconds"] for r in res), 2), "max_s": round(max(r["seconds"] for r in res), 2),
    }
    print(f"\npage {summary['page']}/{n}, pointer {summary['pointer']}/{n}, both {summary['both']}/{n}, "
          f"stale {summary['stale']}; at >= {ACT_FLOOR}: acted on {summary['acted_at_floor']}, right {summary['acted_right']}; "
          f"both questions p50 {summary['p50_s']} s, max {summary['max_s']} s")
    with open(DATA / "results.jsonl", "a") as f:
        f.write(json.dumps({**summary, "rows": res}) + "\n")
    return 0 if summary["both"] == n and not summary["stale"] else 1


if __name__ == "__main__":
    sys.exit(main())

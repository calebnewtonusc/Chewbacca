#!/usr/bin/env python3
"""Live eval of Jev tagging `people note` against the keyword fallback. Hits
the network, so it is not part of the suite. Needs TYPESAFE_API_KEY or the
Keychain entry.

    python3 tests/eval_people_jev.py

Each case runs `people note` end to end in a throwaway PEOPLE_DIR, once with
Jev and once with PEOPLE_JEV=off, and reads back what was stored. Names are
fictional; the sentences have the shape of notes the skill writes. Labelled by
hand on 2026-09-23. Dimensions count as right when the stored set equals the
label; modality and source must match exactly.

Result 2026-09-23: Jev dims 22/24, modality 24/24, source 22/24; keywords
9, 13, 20. Worst note 0.58 s end to end against 0.06 s. Misses: "a church in
Austin" also tagged social, "apparently engaged" also emotional and read as
told directly, "I think she is struggling" read as told directly.
"""
import json
import os
import pathlib
import sqlite3
import subprocess
import sys
import tempfile
import time

PEOPLE = str(pathlib.Path(__file__).resolve().parent.parent / "bin" / "people")

# (note, dimensions, modality, source)
CASES = [
    ("just got promoted to senior engineer", {"financial"}, "actual", "told_directly"),
    ("might move to Denver next year", {"social"}, "hypothetical", "told_directly"),
    ("wedding is booked for June", {"social"}, "planned", "told_directly"),
    ("heard from Priya that he got laid off", {"financial"}, "actual", "third_party"),
    ("really burnt out from the new job", {"emotional", "financial"}, "actual", "told_directly"),
    ("tore her ACL playing pickup", {"physical"}, "actual", "told_directly"),
    ("wants to start a company after graduating", {"financial"}, "desired", "told_directly"),
    ("is open to intros to seed investors", {"financial"}, "available", "told_directly"),
    ("turned down the Google offer", {"financial"}, "declined", "told_directly"),
    ("started going to a church in Austin", {"spiritual"}, "actual", "told_directly"),
    ("reading everything about protein folding for her thesis", {"intellectual"}, "actual", "told_directly"),
    ("I think she is struggling with money, she skipped dinner twice", {"financial"}, "actual", "inferred"),
    ("saw him at the gym every morning this week", {"physical"}, "actual", "observed"),
    ("apparently engaged now", {"social"}, "actual", "third_party"),
    ("thinking about applying to law school", {"intellectual"}, "hypothetical", "told_directly"),
    ("training for the Chicago marathon in October", {"physical"}, "planned", "told_directly"),
    ("grieving her grandmother, funeral was Saturday", {"emotional", "social"}, "actual", "told_directly"),
    ("raising a pre-seed round for his fintech app", {"financial"}, "actual", "told_directly"),
    ("hopes to get back into running after surgery", {"physical"}, "desired", "told_directly"),
    ("said no to being a groomsman", {"social"}, "declined", "told_directly"),
    ("new roommate situation is stressing her out", {"social", "emotional"}, "actual", "told_directly"),
    ("probably going to switch majors to econ", {"intellectual"}, "hypothetical", "told_directly"),
    ("offered to help me move on Sunday", {"social"}, "available", "told_directly"),
    ("loves Taylor Swift", set(), "actual", "told_directly"),
]


def run(env_extra: dict) -> list[tuple[set, str, str, float]]:
    out = []
    with tempfile.TemporaryDirectory() as tmp:
        env = {**os.environ, "PEOPLE_DIR": tmp, **env_extra}
        subprocess.run([PEOPLE, "add", "Sam Rivera"], env=env, check=True, capture_output=True)
        for note, *_ in CASES:
            t = time.perf_counter()
            subprocess.run([PEOPLE, "note", "sam", note, "--no-score", "--force"],
                           env=env, check=True, capture_output=True)
            out.append(time.perf_counter() - t)
        con = sqlite3.connect(os.path.join(tmp, "people.db"))
        rows = con.execute(
            "SELECT o.body, o.modality, o.source, group_concat(d.code) FROM observations o "
            "LEFT JOIN observation_dimensions od ON od.observation_id = o.id "
            "LEFT JOIN dimensions d ON d.id = od.dimension_id GROUP BY o.id").fetchall()
    stored = {b: (set(filter(None, (dims or "").split(","))), m, s) for b, m, s, dims in rows}
    return [(*stored[note], secs) for (note, *_), secs in zip(CASES, out)]


def score(results) -> tuple[int, int, int]:
    dims = sum(r[0] == c[1] for r, c in zip(results, CASES))
    mod = sum(r[1] == c[2] for r, c in zip(results, CASES))
    src = sum(r[2] == c[3] for r, c in zip(results, CASES))
    return dims, mod, src


def main() -> int:
    jev = run({})
    words = run({"PEOPLE_JEV": "off"})
    n = len(CASES)
    for (note, d, m, s), got in zip(CASES, jev):
        miss = [k for k, ok in (("dims", got[0] == d), ("modality", got[1] == m), ("source", got[2] == s)) if not ok]
        if miss:
            print(f"  miss {', '.join(miss):24} {note!r}: got {sorted(got[0])} {got[1]} {got[2]}")
    print(json.dumps({
        "cases": n,
        "jev": dict(zip(("dims", "modality", "source"), score(jev))),
        "keywords": dict(zip(("dims", "modality", "source"), score(words))),
        "jev_worst_note_s": round(max(r[3] for r in jev), 2),
        "keywords_worst_note_s": round(max(r[3] for r in words), 2),
    }, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())

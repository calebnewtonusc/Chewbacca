#!/usr/bin/env python3
"""Turn what he actually asked into candidate eval cases.

WHY THIS EXISTS. `~/.chewbacca/asks.jsonl` holds every prompt the person has
typed, and until now nothing read it. That is the largest unused signal in
the kit and the only on-policy data it will ever have: real requests, in
real words, including the ones that went wrong. Every eval case in `skills/`
was invented by someone imagining what a user might say, which is a worse
sample of the same distribution.

WHAT IT DOES NOT DO. It never writes an eval file. It proposes, a human
rules, and the reason is Goodhart: a loop that can both invent its own test
cases and score itself against them will optimise the pair and learn
nothing. Proposals go to stdout or a file you have to move yourself.

THE CORRECTION SIGNAL IS THE VALUABLE HALF. An ask that arrives soon after
another in the same session, and that carries a frustration marker, is
usually the person repairing a failure. Those are labelled examples: the
first ask is what was misread, the second says what was wanted. They are
worth more than ten invented cases and are surfaced separately.
"""

from __future__ import annotations

import argparse
import json
import re
from collections import Counter
from datetime import datetime
from pathlib import Path

ASKS = Path.home() / ".chewbacca" / "asks.jsonl"

# His words, measured rather than guessed. These mark a repair, not a mood.
FRUSTRATION = re.compile(
    r"\b(bruh|bro|dawg|wtf|retard\w*|stupid|nah|nvm|no+pe|wrong|"
    r"still|again|not what|isn'?t|doesn'?t|broken|lol)\b", re.I)

# Asks that cannot become an eval case, because they name no capability.
TOO_THIN = re.compile(r"^\W*(ok|k|yes|no|ya|sure|thanks|thx|ty|good night|gn|"
                      r"cool|nice|bet|alr|go|continue|keep going)\W*$", re.I)


def load(path=ASKS):
    if not path.exists():
        return []
    out = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            out.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return out


def parse_at(row):
    try:
        return datetime.strptime(row["at"], "%Y-%m-%dT%H:%M:%S%z")
    except (KeyError, ValueError):
        return None


def repairs(rows, within_seconds=600):
    """Pairs where the second ask looks like it is fixing the first.

    Same session, close in time, and the second carries a frustration
    marker. Deliberately loose: a false pair costs a human ten seconds of
    reading, and a missed one costs the only labelled example of that
    failure that will ever exist.
    """
    out = []
    for prev, cur in zip(rows, rows[1:]):
        if prev.get("session") != cur.get("session"):
            continue
        a, b = parse_at(prev), parse_at(cur)
        if not a or not b:
            continue
        gap = (b - a).total_seconds()
        if not (0 <= gap <= within_seconds):
            continue
        said = cur.get("said", "")
        if not FRUSTRATION.search(said):
            continue
        # A message that is mostly a pasted link is a new input, not a
        # repair of the previous ask, however exasperated the words around
        # it are. Same for a burst sent in the same second: that is one
        # thought split across two messages, which is how he types.
        stripped = re.sub(r"https?://\S+", "", said).strip()
        if len(stripped) < 12:
            continue
        if gap < 3 and len(stripped) < 40:
            continue
        out.append({"gap_s": int(gap), "asked": prev.get("said", ""),
                    "then_said": cur.get("said", ""), "at": cur.get("at")})
    return out


def candidates(rows):
    """Asks substantial enough to become an eval case."""
    seen = set()
    out = []
    for r in rows:
        said = (r.get("said") or "").strip()
        if len(said) < 15 or TOO_THIN.match(said):
            continue
        key = said.lower()[:80]
        if key in seen:
            continue
        seen.add(key)
        out.append({"prompt": said, "cwd": r.get("cwd", ""), "at": r.get("at", "")})
    return out


def vocabulary(rows, top=20):
    """What he actually asks about, so coverage can be aimed."""
    words = Counter()
    for r in rows:
        for w in re.findall(r"[a-z][a-z-]{3,}", (r.get("said") or "").lower()):
            words[w] += 1
    common = {"that", "this", "with", "from", "have", "what", "when", "your",
              "just", "make", "need", "want", "like", "they", "them", "should",
              "would", "could", "there", "where", "which", "about", "into"}
    return [(w, n) for w, n in words.most_common(top * 3) if w not in common][:top]


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--path", type=Path, default=ASKS)
    ap.add_argument("--json", action="store_true", help="machine readable")
    ap.add_argument("--repairs-only", action="store_true")
    a = ap.parse_args()

    rows = load(a.path)
    if not rows:
        print(f"no asks at {a.path}")
        return 0

    rep = repairs(rows)
    cand = candidates(rows)
    vocab = vocabulary(rows)

    if a.json:
        print(json.dumps({"total": len(rows), "repairs": rep,
                          "candidates": cand, "vocabulary": vocab},
                         indent=2, sort_keys=True))
        return 0

    print(f"{len(rows)} asks, {len(cand)} usable as eval cases, "
          f"{len(rep)} look like repairs\n")

    print("REPAIRS. The second ask says what the first should have produced.")
    print("These are the only labelled failures the kit will ever get.\n")
    for r in rep[-12:]:
        print(f"  +{r['gap_s']}s  asked: {r['asked'][:70]}")
        print(f"         then: {r['then_said'][:70]}\n")
    if a.repairs_only:
        return 0

    print("\nWHAT HE ASKS ABOUT, by frequency:")
    print("  " + ", ".join(f"{w} {n}" for w, n in vocab))

    print("\n\nCANDIDATE EVAL CASES, newest last. Nothing is written for you:")
    print("copy the ones worth keeping into the right skills/<name>/evals/.\n")
    for c in cand[-15:]:
        print(f"  {c['prompt'][:100]}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

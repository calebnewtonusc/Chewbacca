"""Can Jev point at the right control, fast, and know when it can't?

The idea under test (docs/SITE-LEARNING.md): "where do I click" answered as a
Jev choice over the page's controls, with the interface shaped by confidence.
One clear winner gets the bubble, two close ones both get a ring, and anything
lower gets a question. That only works if two things hold, so both are measured:

    ACCURACY     top-1 on 30 requests over 6 real pages, most of them worded
                 differently from the control ("I want to rent out my place"
                 for "Become a host")
    CALIBRATION  confidence is high when it is right and low when it is wrong,
                 so a threshold separates acting from asking

The falsifier, written before the run: top-1 under ~90%, or wrong answers as
confident as right ones. A word-overlap baseline runs on the same rows, so a
Jev win is a win over the cheapest thing, not over nothing.

The key was corrected once, after the first run on 2026-09-23, and only where
the page itself proved the pick right: Booking has two support links, Wikipedia
links Español directly, and Stripe's two "Contact sales" differed only by an
invisible U+2060 (now stripped by `site snap`). The one real miss (the Hacker
News comments link) stands. Scores stay private: TypeSafe's customer agreement
(2.3(f)) bars publishing Jev performance results.

Fixtures are `site snap --json` of public pages, read 2026-09-23. Booking and
Airbnb tailor their pages to where the reader is, so every control naming a
nearby place was removed before commit, along with the raw tree. None of them
was an answer. A page's
controls go in as up to 255 options (the API's ceiling): every non-link
first, then links in page order.

    python3 tests/eval_ground_jev.py            # needs TYPESAFE_API_KEY or the Keychain entry
"""

import json
import pathlib
import re
import statistics
import sys
import time
from concurrent.futures import ThreadPoolExecutor

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "bin" / "lib"))
import jev  # noqa: E402

FIX = ROOT / "tests" / "fixtures" / "ground"
MAX_OPTIONS = 255

# (page, what the person says, accepted controls as "role: name")
ROWS = [
    ("airbnb.com", "log in", ["button: Log in or sign up"]),
    ("airbnb.com", "I want to rent out my place", ["button: Become a host", "link: Airbnb your home"]),
    ("airbnb.com", "change the currency to euros", ["button: Choose a currency"]),
    ("airbnb.com", "pick my dates", ["button: When Add dates"]),
    ("airbnb.com", "how many people are coming", ["button: Who Add guests"]),
    ("airbnb.com", "show me beach places", ["tab: Beach"]),
    ("booking.com", "type where I'm going", ["combobox: Enter destination"]),
    ("booking.com", "I need a rental car", ["menuitem: Car rental"]),
    ("booking.com", "make an account", ["link: Register an account"]),
    ("booking.com", "this is a business trip", ["checkbox: I'm traveling for work"]),
    ("booking.com", "talk to someone about my booking", ["link: Customer support", "link: Contact Customer Service"]),
    ("booking.com", "find a flight", ["menuitem: Flights"]),
    ("en.wikipedia.org", "search for something", ["searchbox: Search Wikipedia", "button: Search"]),
    ("en.wikipedia.org", "dark mode", ["radio: Dark"]),
    ("en.wikipedia.org", "make the text bigger", ["radio: Large"]),
    ("en.wikipedia.org", "give them money", ["link: Donate"]),
    ("en.wikipedia.org", "see older versions of this page", ["link: View history"]),
    ("en.wikipedia.org", "read this in Spanish", ["button: 349 languages", "link: Español"]),
    ("github.com", "sign in", ["link: Sign in"]),
    ("github.com", "how much does it cost", ["link: Pricing"]),
    ("github.com", "put in my email to join", ["textbox: Enter your email"]),
    ("github.com", "stop the animation", ["button: Pause animation", "button: Pause", "button: Pause video"]),
    ("github.com", "cookie settings", ["button: Manage cookies"]),
    ("github.com", "open the docs", ["link: Docs"]),
    ("news.ycombinator.com", "post a link", ["link: submit"]),
    ("news.ycombinator.com", "log in", ["link: login"]),
    ("news.ycombinator.com", "the newest stories", ["link: new"]),
    ("news.ycombinator.com", "open the comments on the Claude post", ["link: 918 comments"]),
    ("stripe.com", "talk to sales", ["link: Contact sales"]),
    ("stripe.com", "switch country", ["combobox: United States. Choose your country"]),
]


def options(page):
    snap = json.loads((FIX / f"{page}.json").read_text())
    seen, rest, links = set(), [], []
    for c in snap["controls"]:
        label = f"{c['role']}: {c['name']}"
        if not c["name"] or label in seen:
            continue
        seen.add(label)
        (links if c["role"] == "link" else rest).append(label)
    return snap["title"], (rest + links)[:MAX_OPTIONS]


def words(text):
    return set(re.findall(r"[a-z0-9]+", text.lower())) - {"the", "a", "to", "my", "i", "for", "on", "of", "in"}


def baseline(request, labels):
    """Word overlap: the cheapest pointer there is."""
    q = words(request)
    return max(labels, key=lambda label: len(q & words(label.split(": ", 1)[1])))


def judge(row):
    page, request, accepted = row
    title, labels = options(page)
    missing = [a for a in accepted if a not in labels]
    keys = {f"c{i}": label for i, label in enumerate(labels)}
    t = time.monotonic()
    answers = jev.ask(
        f'On the web page "{title}", the person says: "{request}"',
        {"target": {
            "type": "choice",
            "instructions": "Which control on this page should be clicked or used to do what the person asked?",
            "criteria": keys,
        }},
        timeout=10,
    )
    took = time.monotonic() - t
    a = (answers or {}).get("target") or {}
    probs = sorted((a.get("probabilities") or {}).items(), key=lambda kv: -kv[1])
    pick = keys.get(a.get("choice"), None)
    return {
        "page": page, "request": request, "accepted": accepted, "missing": missing,
        "pick": pick, "right": pick in accepted,
        "top": probs[0][1] if probs else None,
        "second": probs[1][1] if len(probs) > 1 else 0.0,
        "runner_up": keys.get(probs[1][0]) if len(probs) > 1 else None,
        "confidence": a.get("confidence"), "seconds": round(took, 2),
        "baseline": baseline(request, labels), "options": len(labels),
    }


def main():
    if not jev.api_key():
        print("No TYPESAFE_API_KEY in the environment or the Keychain.")
        return 2
    with ThreadPoolExecutor(max_workers=6) as pool:
        results = list(pool.map(judge, ROWS))
    answered = [r for r in results if r["pick"] is not None]
    for r in results:
        mark = "ok " if r["right"] else "MISS"
        print(f"{mark} {r['top'] or 0:.2f}/{r['second']:.2f} {r['seconds']:>5}s  {r['page']:<22} "
              f"{r['request']!r} -> {r['pick']}" + ("" if r["right"] else f"   (wanted {r['accepted'][0]})"))
    n = len(results)
    right = [r for r in answered if r["right"]]
    wrong = [r for r in answered if not r["right"]]
    base = sum(r["baseline"] in r["accepted"] for r in results)
    secs = sorted(r["seconds"] for r in answered)
    print()
    print(f"answered       {len(answered)}/{n}")
    print(f"jev top-1      {len(right)}/{n} = {len(right) / n:.0%}")
    print(f"word overlap   {base}/{n} = {base / n:.0%}")
    if secs:
        print(f"latency        p50 {statistics.median(secs):.2f}s  max {secs[-1]:.2f}s  "
              f"(options per page {min(r['options'] for r in results)} to {max(r['options'] for r in results)})")
    if right:
        print(f"top prob       right {statistics.mean(r['top'] for r in right):.2f}"
              + (f", wrong {statistics.mean(r['top'] for r in wrong):.2f}" if wrong else ", wrong n/a"))
    for bar in (0.5, 0.7, 0.9):
        acted = [r for r in answered if r["top"] >= bar]
        if acted:
            ok = sum(r["right"] for r in acted)
            print(f"act at >= {bar}   covers {len(acted)}/{n}, right {ok}/{len(acted)}")
    missing = [r for r in results if r["missing"]]
    if missing:
        print(f"fixture gaps   {[(r['page'], r['missing']) for r in missing]}")
    out = ROOT / "tests" / "fixtures" / "ground" / "last-run.json"
    out.write_text(json.dumps(results, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())

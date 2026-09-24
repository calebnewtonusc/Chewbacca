#!/usr/bin/env python3
"""Live eval of route.route() end to end, with the app that is in front.

    python3 tests/eval_route_front.py            the router as it is
    ROUTE_EVAL_CLASSIFY=off python3 ...          rules only, no Jev

eval_route_jev.py asks the classifier alone, with Terminal in front. The
Google-search complaint lives before the classifier: with Chrome in front, any
sentence without one of SITE_TASK_WORDS went to the browser, and the browser
turns what it cannot open into a Google search of the whole sentence. These
cases are that shape, labelled by hand on 2026-09-24: `browser` only when the
person wants a page opened or a search run, `assistant` when they want
something answered or done.

Hits the network. Not part of the suite. Results stay on this machine:
TypeSafe's customer agreement (2.3(f)) bars publishing Jev performance results.
"""
import os
import pathlib
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent / "bin" / "lib"))
import route  # noqa: E402

T, B, A = "terminal", "browser", "assistant"
CHROME = {"app": "Google Chrome", "claude_tab": False}
TERM = {"app": "Terminal", "claude_tab": True}
FINDER = {"app": "Finder", "claude_tab": False}

CASES = [
    # Chrome in front: the Google-search shape.
    (CHROME, "what's the weather tomorrow", A),
    (CHROME, "make this sheet compare prices for Valencia", A),
    (CHROME, "summarize this page", A),
    (CHROME, "who is this guy", A),
    (CHROME, "sort these by price", A),
    (CHROME, "fill this out with my info", A),
    (CHROME, "close this tab", A),
    (CHROME, "scroll down", A),
    (CHROME, "what's on this page", A),
    (CHROME, "find me cheaper ones", A),
    (CHROME, "compare these two listings", A),
    (CHROME, "translate this page to English", A),
    (CHROME, "put this on my calendar", A),
    (CHROME, "write a reply to this email", A),
    (CHROME, "fix the typo in my headline", A),
    (CHROME, "rearrange my skills so Clay is first", A),
    (CHROME, "check my LinkedIn messages", A),
    (CHROME, "make it dark mode", A),
    (CHROME, "how much would this cost for four people", A),
    (CHROME, "is this a good deal", A),
    (CHROME, "play Fred again", A),
    (CHROME, "what time is it", A),
    (CHROME, "open YouTube", B),
    (CHROME, "search for Jordan 4 prices", B),
    (CHROME, "go to github.com", B),
    (CHROME, "google best tacos in Austin", B),
    (CHROME, "look up Clay pricing", B),
    (CHROME, "pull up the Clay pricing page", B),
    (CHROME, "open my Airbnb trips", B),
    (CHROME, "open a new tab with Google Sheets", B),
    # Nothing in particular in front.
    (FINDER, "what's the weather tomorrow", A),
    (FINDER, "make a Google sheet comparing Airbnb prices in Valencia", A),
    (FINDER, "open YouTube", B),
    (FINDER, "search for flights to Tokyo", B),
    (FINDER, "can you go to my linked in and edit my skills", A),
    (FINDER, "Let's brainstorm cool ways we can make my site look awesome", A),
    (FINDER, "Text Elias and tell him he's a salty bowl", A),
    (FINDER, "Add call with Otis at 7 PM on Saturday", A),
    (FINDER, "What do I have today?", A),
    # A Claude tab in front.
    (TERM, "write the readme", T),
    (TERM, "why does the HUD crash when I press control", T),
    (TERM, "rename that function to classify", T),
    (TERM, "what's the weather tomorrow", A),
    (TERM, "Text James and tell him I'm running late", A),
    (TERM, "open YouTube", B),
]


def main() -> int:
    classify = (lambda s, m: None) if os.environ.get("ROUTE_EVAL_CLASSIFY") == "off" else None
    wrong, searched = [], 0
    for ctx, said, want in CASES:
        d = route.route(said, ctx, {}, names=["Elias", "Otis", "James", "Caleb"], now=0.0, classify=classify)
        mark = "ok" if d.dest == want else "XX"
        searched += d.dest == B and want != B
        if d.dest != want:
            wrong.append(CASES.index((ctx, said, want)))
        print(f"{mark}  {ctx['app'][:8]:8} want={want:9} got={d.dest:9} {d.reason[:34]:34} {said[:60]}")
    print(f"\n{len(CASES) - len(wrong)}/{len(CASES)} right")
    print(f"sent to the browser when not wanted (a Google search of the sentence): {searched}")
    return 0 if not wrong else 1


if __name__ == "__main__":
    sys.exit(main())

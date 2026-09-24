#!/usr/bin/env python3
"""Live eval of router tier 3 against TypeSafe's Jev. Hits the network, so it
is not part of the suite. Needs TYPESAFE_API_KEY or the Keychain entry.

    python3 tests/eval_route_jev.py

Twenty sentences have the shape of real routed ones from the voice
transcript (fragments, a bare "No", "Create a bubble", a trip plan), with any
personal detail swapped out; the rest are cases the word lists are known to
miss. Labelled by hand on 2026-09-23.
Scores stay private: TypeSafe's customer agreement (2.3(f)) bars publishing
Jev performance results.
"""
import pathlib
import sys
import time

sys.dont_write_bytecode = True
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent / "bin" / "lib"))
import route  # noqa: E402

T, B, A = "terminal", "browser", "assistant"
CASES = [
    ("can you go to my linked in and edit my skills", A), ("Update my headline on LinkedIn", A),
    ("Post this on Twitter", A), ("Book the cheapest flight to Denver", A),
    ("Open YouTube", B), ("Search for flights to Tokyo", B), ("Pull up the Clay pricing page", B),
    ("This is", A), ("Make a spreadsheet comparing rental prices for Lisbon", A),
    ("How the check-in date be March 3 have the check out day March 20 and make it for two people with a budget of $3000", A),
    ("I was just thinking out loud there you know", A), ("Open up terminal start, Claude", A),
    ("Chewbacca", A), ("No", A), ("Open a bubble", A), ("Terminal", A),
    ("No, let's talk to text feature. We just built the bubble.", T),
    ("Create a bubble", A), ("My Claude window", A), ("The text box", A), ("Shut up", A),
    ("Yo, can you hear me?", A), ("Test complete", A), ("Give me an entire summary on the French Revolution", A),
    ("Bubble", A), ("How are you?", A),
    ("OK, I have two questions for my biology class can I paste them", A),
    ("write the readme", T), ("make the parser handle the format", T),
    ("the hyper bar should fade out faster", T), ("why does the HUD crash when I press control", T),
    ("rename that function to classify", T), ("add a flag so dictation can be turned off", T),
    ("what do you think of the design", A), ("search for flights to Lisbon", B),
    ("look up Clay pricing", B), ("what's the weather tomorrow", A),
]
IN_TERMINAL = {"context": {"app": "Terminal", "claude_tab": True}}


def main() -> int:
    ok, worst = 0, 0.0
    for said, want in CASES:
        started = time.time()
        got = route.classify_with_jev(said, IN_TERMINAL)
        worst = max(worst, time.time() - started)
        ok += got == want
        print(f"{'ok' if got == want else 'XX'}  want={want:9} got={got!s:9}  {said[:70]}")
    print(f"{ok}/{len(CASES)}  worst latency {worst:.2f}s")
    return 0 if ok == len(CASES) else 1


if __name__ == "__main__":
    sys.exit(main())

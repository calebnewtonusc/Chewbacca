#!/usr/bin/env python3
"""Live eval of agent_board.pick against TypeSafe's Jev. Hits the network, so
it is not part of the suite. Needs TYPESAFE_API_KEY or the Keychain entry.

    python3 tests/eval_agent_board_jev.py

A made-up board of four sessions, the way they would sit on a real afternoon,
and sentences labelled by hand with the session they are for, or None when a
person would have to say which. Prints every probability so PICK_FLOOR can be
set from what separates the right answers from the wrong ones.
Results stay on the machine that ran them: TypeSafe's customer agreement
(2.3(f)) bars publishing Jev performance results. What the first run taught
is design, not a score: "The heads up display one" could not be placed until
the menu carried each session's topic, so topics are on the menu now (each
session's transcript `ai-title`), and the board below carries the titles
Claude Code would have written.
"""
import pathlib
import sys
import time

sys.dont_write_bytecode = True
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent / "bin" / "lib"))
import agent_board as ab  # noqa: E402

BOARD = {}
for entry in [
    {"event": "PreToolUse", "session": "hud", "cwd": "/code/Chewbacca", "t": 1, "summary": "swift build"},
    {"event": "PermissionRequest", "session": "clay", "cwd": "/code/clay-automation", "t": 2, "summary": "git push origin main"},
    {"event": "Stop", "session": "site", "cwd": "/code/landing-page", "t": 3, "summary": "The hero section is rebuilt."},
    {"event": "PreToolUse", "session": "quant", "cwd": "/code/jev-trading-bot", "t": 4, "summary": "python3 backtest.py"},
]:
    BOARD = ab.fold(BOARD, entry)
TOPICS = {
    "hud": "Kyber HUD presence field",
    "clay": "Clay enrichment table for investors",
    "site": "Landing page hero redesign",
    "quant": "Jev 8-K dilution backtest",
}
BOARD = {k: {**v, "topic": TOPICS[k]} for k, v in BOARD.items()}

CASES = [
    ("Tell the Clay one it can push", "clay"),
    ("Approve the push", "clay"),
    ("The trading bot, stop the backtest", "quant"),
    ("How's the backtest looking", "quant"),
    ("Tell the landing page one to make the hero darker", "site"),
    ("On the website, change the headline", "site"),
    ("In Chewbacca, fix the HUD build", "hud"),
    ("Is the swift build done yet", "hud"),
    ("The heads up display one, rerun the tests", "hud"),
    ("Clay automation, add a column for LinkedIn URL", "clay"),
    ("Quant bot, lower the position size", "quant"),
    ("Landing page, ship it", "site"),
    ("Tell the one doing the back test to use last month's data", "quant"),
    ("Tell all of them to stop", None),
    ("What are my agents doing", None),
    ("Run the tests", None),
    ("Yes", None),
    ("Hey how are you", None),
    ("Commit everything", None),
    ("Play some music", None),
]


def main() -> int:
    right = 0
    worst = 0.0
    rows = []
    for said, want in CASES:
        start = time.monotonic()
        got = ab.pick(said, BOARD)
        worst = max(worst, time.monotonic() - start)
        ok = got["session"] == want
        right += ok
        rows.append((ok, said, want, got))
        print(f"{'ok  ' if ok else 'MISS'} {got['confidence']:.2f}  want={want!s:6} got={got['session']!s:6} {said!r}  ({got['why']})")
    print(f"\n{right}/{len(CASES)} right, worst latency {worst:.2f} s, floor {ab.PICK_FLOOR}")
    return 0 if right == len(CASES) else 1


if __name__ == "__main__":
    sys.exit(main())

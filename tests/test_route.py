#!/usr/bin/env python3
"""The routing table. Every rule in the spec is a row here.

    python3 tests/test_route.py
"""
import importlib.util
import pathlib
import sys
import time
from datetime import datetime, timedelta, timezone
from importlib.machinery import SourceFileLoader

sys.dont_write_bytecode = True
ROOT = pathlib.Path(__file__).resolve().parent.parent
_src = ROOT / "bin" / "lib" / "route.py"
spec = importlib.util.spec_from_loader("route", SourceFileLoader("route", str(_src)))
r = importlib.util.module_from_spec(spec)
spec.loader.exec_module(r)

PASSED = FAILED = 0


def check(name, cond, detail=""):
    global PASSED, FAILED
    if cond:
        PASSED += 1
        print(f"  pass  {name}")
    else:
        FAILED += 1
        print(f"  FAIL  {name}  {detail}")


NOW = time.time()


def iso(ago):
    return (datetime.fromtimestamp(NOW, timezone.utc) - timedelta(seconds=ago)).isoformat(timespec="seconds")


NOBODY = {"app": "", "claude_tab": False}
TERMINAL = {"app": "Terminal", "claude_tab": True}
SHELL_ONLY = {"app": "Terminal", "claude_tab": False}
CHROME = {"app": "Google Chrome", "claude_tab": False}
COLD = {"last": None, "warm": None, "project": {}, "recent": []}


def mem(dest, ago, text="earlier"):
    return {"last": {"dest": dest, "t": iso(ago), "text": text}, "warm": dest if ago < 600 else None,
            "project": {"name": "signaler", "summary": "a price signaler"}, "recent": []}


calls = []


def classifier(answer):
    def fn(said, memory):
        calls.append(said)
        return answer
    return fn


def dest(said, ctx=NOBODY, memory=COLD, names=(), classify=classifier(None)):
    return r.route(said, ctx, memory, names=names, now=NOW, classify=classify)


# ── explicit ──────────────────────────────────────────────────────────────────
d = dest("in terminal, begin building a signaler for when my stock hits a price", CHROME)
check("'in terminal' goes to the terminal whatever is in front", d.dest == "terminal" and d.confidence == 1.0, str(d))
check("'in chrome' goes to the browser", dest("in chrome look up rust traits", TERMINAL).dest == "browser")

# ── tier 1, correction ────────────────────────────────────────────────────────
d = dest("no, the terminal", NOBODY, mem("assistant", 5, "add a retry"))
check("a correction re-routes the previous sentence", d.dest == "terminal" and d.reroute == "add a retry", str(d))
check("'no, to you' re-routes to the assistant", dest("no, to you", NOBODY, mem("terminal", 5, "x")).dest == "assistant")
check("'no, chrome' re-routes to the browser", dest("no, chrome", NOBODY, mem("assistant", 5, "x")).dest == "browser")
d = dest("other one", NOBODY, mem("terminal", 5, "x"))
check("'other one' after terminal means the assistant", d.dest == "assistant" and d.reroute == "x")
d = dest("no, the terminal", NOBODY, mem("assistant", 20, "add a retry"))
check("a correction 20 s later is a normal sentence", d.reroute is None)

# ── tier 2.1, person-shaped ───────────────────────────────────────────────────
for said in ("text caleb i'm running late", "remind me to call mom", "what time is it",
             "what's on tomorrow", "email sarah the deck", "note that the demo is friday",
             "book a dentist tuesday", "cancel my three o'clock"):
    d = dest(said, TERMINAL, mem("terminal", 5))
    check(f"person-shaped in front of the terminal: {said!r}", d.dest == "assistant" and d.confidence == 0.95, str(d))
d = dest("tell Caleb the build is green", TERMINAL, mem("terminal", 5), names=["Caleb", "Sarah"])
check("a known name in the first six words is a person", d.dest == "assistant")
d = dest("make the parser handle caleb's format", TERMINAL, mem("terminal", 5), names=["Caleb"])
check("a name is only checked in the first six words", d.dest == "terminal", str(d))

# ── tier 2.2, continuation while warm ─────────────────────────────────────────
for said in ("and add tests", "also handle the empty case", "then push it", "now run it again",
             "make it faster", "fix that", "undo that", "add one for errors"):
    d = dest(said, CHROME, mem("terminal", 30))
    check(f"continuation goes to the warm terminal: {said!r}", d.dest == "terminal" and d.confidence == 0.85, str(d))
d = dest("and search for the docs", NOBODY, mem("browser", 30))
check("a continuation follows a warm browser too", d.dest == "browser")
d = dest("fix that", NOBODY, mem("terminal", 700), classify=classifier("assistant"))
check("a continuation with nothing warm falls through", d.dest == "assistant")

# ── tier 2.3, frontmost workspace ─────────────────────────────────────────────
d = dest("write the readme", TERMINAL)
check("in front of a claude tab, the terminal", d.dest == "terminal" and d.confidence == 0.8, str(d))
d = dest("write the readme", SHELL_ONLY, classify=classifier("assistant"))
check("Terminal with no claude tab is not a workspace", d.dest == "assistant" and calls[-1] == "write the readme")
d = dest("how do i center a div", CHROME)
check("in front of Chrome, the browser", d.dest == "browser" and d.confidence == 0.8, str(d))
calls.clear()
d = dest("write the readme", CHROME, mem("terminal", 30), classify=classifier("terminal"))
check("Chrome in front but terminal warm and not browser-shaped: the classifier decides",
      d.dest == "terminal" and calls == ["write the readme"], str((d, calls)))
d = dest("look up flexbox", CHROME, mem("terminal", 30))
check("Chrome in front, terminal warm, browser-shaped: the browser", d.dest == "browser")

# ── tier 2.4, browser-shaped ──────────────────────────────────────────────────
for said in ("look up the weather in dallas", "search for rust traits", "google flexbox gap",
             "go to github.com", "open hacker news dot com"):
    d = dest(said)
    check(f"browser-shaped with nothing in front: {said!r}", d.dest == "browser" and d.confidence == 0.8, str(d))
d = dest("open calculator", NOBODY, classify=classifier("assistant"))
check("'open <app>' is not browser-shaped", d.dest == "assistant")

# ── tier 3 ────────────────────────────────────────────────────────────────────
calls.clear()
d = dest("what do you think of the design", NOBODY, COLD, classify=classifier("assistant"))
check("the classifier is asked when nothing rules", d.dest == "assistant" and d.reason == "classifier" and calls)
d = dest("what do you think of the design", NOBODY, mem("terminal", 30), classify=classifier(None))
check("classifier timeout: the warm destination", d.dest == "terminal" and d.reason == "classifier timeout")
d = dest("what do you think of the design", NOBODY, COLD, classify=classifier(None))
check("classifier timeout with nothing warm: the assistant", d.dest == "assistant")
d = dest("what do you think", NOBODY, COLD, classify=classifier("nonsense"))
check("a classifier answer that is not a destination is ignored", d.dest == "assistant" and d.reason == "classifier timeout")

# ── draft words ───────────────────────────────────────────────────────────────
for said in ("send it", "Send.", "run it", "run", "confirm", "go", "do it", "send that"):
    check(f"submit word: {said!r}", r.draft_word(said) == "submit")
for said in ("scrap that", "clear it", "never mind", "nevermind", "cancel that"):
    check(f"clear word: {said!r}", r.draft_word(said) == "clear")
for said in ("no, to you", "not the terminal", "no not the terminal"):
    check(f"reroute word: {said!r}", r.draft_word(said) == "reroute")
check("a sentence containing 'run' is not a draft word", r.draft_word("run the tests and tell me") is None)

# ── browser urls ──────────────────────────────────────────────────────────────
url, label = r.browser_url("look up rust traits")
check("a lookup is a google search", url == "https://www.google.com/search?q=rust+traits" and label == "chrome: rust traits", str((url, label)))
url, label = r.browser_url("go to github.com")
check("go to a domain opens it", url == "https://github.com")
url, label = r.browser_url("open hacker news dot com")
check("'dot com' is spoken punctuation", url == "https://hackernews.com", url)
url, label = r.browser_url("how do i center a div")
check("a plain question is a search", url.startswith("https://www.google.com/search?q=how+do+i+center"))
url, label = r.browser_url("in chrome look up flexbox")
check("the explicit prefix is stripped", url.endswith("q=flexbox"))

# ── seen_app ──────────────────────────────────────────────────────────────────
check("seen_app takes the first receipt field", r.seen_app("Terminal · ~/dev/signaler · 12 chars selected") == "Terminal")
check("seen_app on nothing is empty", r.seen_app("") == "")
check("seen_app on a cannot-see line is empty", r.seen_app("cannot see the screen (x)") == "")

print(f"\n{PASSED} passed, {FAILED} failed")
sys.exit(1 if FAILED else 0)

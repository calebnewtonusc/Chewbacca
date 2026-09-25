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


def main() -> int:
    # ── explicit ──────────────────────────────────────────────────────────
    d = dest("in terminal, begin building a signaler for when my stock hits a price", CHROME)
    check("'in terminal' goes to the terminal whatever is in front", d.dest == "terminal" and d.confidence == 1.0, str(d))
    check("'in chrome' goes to the browser", dest("in chrome look up rust traits", TERMINAL).dest == "browser")

    # ── tier 1, correction ───────────────────────────────────────────────
    d = dest("no, the terminal", NOBODY, mem("assistant", 5, "add a retry"))
    check("a correction re-routes the previous sentence", d.dest == "terminal" and d.reroute == "add a retry", str(d))
    check("'no, to you' re-routes to the assistant", dest("no, to you", NOBODY, mem("terminal", 5, "x")).dest == "assistant")
    check("'no, chrome' re-routes to the browser", dest("no, chrome", NOBODY, mem("assistant", 5, "x")).dest == "browser")
    d = dest("other one", NOBODY, mem("terminal", 5, "x"))
    check("'other one' after terminal means the assistant", d.dest == "assistant" and d.reroute == "x")
    d = dest("no, the terminal", NOBODY, mem("assistant", 20, "add a retry"))
    check("a correction 20 s later is a normal sentence", d.reroute is None)

    # ── tier 2.1, person-shaped ──────────────────────────────────────────
    for said in ("text caleb i'm running late", "remind me to call mom", "what time is it",
                 "what's on tomorrow", "email sarah the deck", "note that the demo is friday",
                 "book a dentist tuesday", "cancel my three o'clock"):
        d = dest(said, TERMINAL, mem("terminal", 5))
        check(f"person-shaped in front of the terminal: {said!r}", d.dest == "assistant" and d.confidence == 0.95, str(d))
    d = dest("tell Caleb the build is green", TERMINAL, mem("terminal", 5), names=["Caleb", "Sarah"])
    check("a known name in the first six words is a person", d.dest == "assistant")
    # The subject here is the name window, not the destination. It used to
    # assert "terminal", which the frontmost-app rule handed over without
    # reading the sentence; now the rest of the rules decide, so the window
    # itself is what gets checked.
    late = "make the parser handle the format for caleb"
    check("a name is only checked in the first six words",
          not r._person_shaped(late, ["Caleb"]), late)
    d = dest("make the test handle the format for caleb", TERMINAL, mem("terminal", 5), names=["Caleb"])
    check("and a late name leaves a work-shaped sentence in the terminal",
          d.dest == "terminal", str(d))

    # ── tier 2.2, continuation while warm ────────────────────────────────
    for said in ("and add tests", "also handle the empty case", "then push it", "now run it again",
                 "make it faster", "fix that", "undo that", "add one for errors"):
        d = dest(said, CHROME, mem("terminal", 30))
        check(f"continuation goes to the warm terminal: {said!r}", d.dest == "terminal" and d.confidence == 0.85, str(d))
    d = dest("and search for the docs", NOBODY, mem("browser", 30))
    check("a continuation follows a warm browser too", d.dest == "browser")
    d = dest("fix that", NOBODY, mem("terminal", 700), classify=classifier("assistant"))
    check("a continuation with nothing warm falls through", d.dest == "assistant")

    # ── tier 2.3, frontmost workspace ────────────────────────────────────
    d = dest("write the readme", TERMINAL)
    check("in front of a claude tab, the terminal", d.dest == "terminal" and d.confidence == 0.8, str(d))
    for said in ("run the tests", "fix the type error", "commit that",
                 "check the build logs", "open bin/lib/route.py", "push it",
                 "rebase onto main", "add a test for the empty case",
                 "the suite is red", "why is the build failing",
                 "refactor that function", "clean up the imports", "deploy it",
                 "what does that error mean", "regenerate the checksums"):
        d = dest(said, TERMINAL)
        check(f"a claude tab in front claims the work: {said!r}", d.dest == "terminal", str(d))

    # The other half of the gate, and the reason the noun list is shorter than
    # a code vocabulary would be. Every sentence here says something ordinary
    # in his life and used to say something else to a word list: a lecture, the
    # drive to Valencia, a delivery, a reminder, a payment method, a journal
    # entry. A false positive is the bug being fixed, so the collisions were
    # dropped and the losses absorbed elsewhere.
    for said in ("what time is my class", "move my class to tuesday",
                 "what's the route to valencia", "where is my package",
                 "file a reminder for tomorrow", "what type of car is it",
                 "change my payment method", "log that i went to the gym"):
        d = dest(said, TERMINAL, names=["Caleb"])
        check(f"an ordinary sentence is not work: {said!r}", d.dest != "terminal", str(d))

    # Every sentence below is real, from ~/.bob/memory/transcript.jsonl on
    # 2026-09-21, and every one was taken to the terminal by the frontmost-app
    # rule alone. Eight of the nine decisions that rule made were wrong, which
    # is what a claim with no content test buys: the person looks at a coding
    # tab most of the day and their calendar question becomes a drafted prompt.
    for said in ("Make a Google sheet comparing prices for Valencia",
                 "How the check-in date be January 15 have the check out day February 15",
                 "No",
                 "Open a bubble",
                 "Terminal",
                 "No, let's talk to text feature. We just built the bubble.",
                 "Open up a bubble",
                 "Create a bubble"):
        d = dest(said, TERMINAL)
        check(f"a claude tab in front does not claim: {said[:40]!r}",
              d.dest == "assistant", str(d))
    d = dest("write the readme", SHELL_ONLY, classify=classifier("assistant"))
    check("Terminal with no claude tab is not a workspace", d.dest == "assistant" and calls[-1] == "write the readme")
    # 2026-09-24: Chrome in front no longer decides. It sent "summarize this
    # page" and fourteen more to a Google search of themselves.
    calls.clear()
    d = dest("how do i center a div", CHROME, classify=classifier(None))
    check("in front of Chrome, a plain sentence is judged, not searched",
          d.dest == "assistant" and calls == ["how do i center a div"], str((d, calls)))
    d = dest("search for how to center a div", CHROME)
    check("in front of Chrome, a search by its own words goes to the browser", d.dest == "browser", str(d))
    d = dest("summarize this page", CHROME, classify=classifier("browser"))
    check("in front of Chrome, the classifier may still pick the browser", d.dest == "browser", str(d))
    calls.clear()
    d = dest("write the readme", CHROME, mem("terminal", 30), classify=classifier("terminal"))
    check("Chrome in front but terminal warm and not browser-shaped: the classifier decides",
          d.dest == "terminal" and calls == ["write the readme"], str((d, calls)))
    # 2026-09-23: "can you go to my linked in and edit my skills" opened a
    # Google search of itself. A task on a site never goes to the browser,
    # by any of the three paths that used to send it there.
    d = dest("can you go to my linked in and edit my skills", NOBODY, classify=classifier("browser"))
    check("classifier says browser for a task on a site: the assistant", d.dest == "assistant", str(d))
    d = dest("go to my linkedin and edit my skills", NOBODY)
    check("'go to <site> and <task>' is not browser-shaped", d.dest == "assistant", str(d))
    d = dest("add python to my skills", CHROME, classify=classifier("browser"))
    check("Chrome in front and a task: the assistant, even when the classifier says browser",
          d.dest == "assistant", str(d))
    d = dest("search for how to delete my account", NOBODY)
    check("a search that mentions a task verb is still a search", d.dest == "browser", str(d))
    d = dest("go to github.com", NOBODY)
    check("'go to <domain>' alone is still the browser", d.dest == "browser", str(d))
    d = dest("look up flexbox", CHROME, mem("terminal", 30))
    check("Chrome in front, terminal warm, browser-shaped: the browser", d.dest == "browser")

    # ── tier 2.4, browser-shaped ─────────────────────────────────────────
    for said in ("look up the weather in dallas", "search for rust traits", "google flexbox gap",
                 "go to github.com", "open hacker news dot com"):
        d = dest(said)
        check(f"browser-shaped with nothing in front: {said!r}", d.dest == "browser" and d.confidence == 0.8, str(d))
    d = dest("open calculator", NOBODY, classify=classifier("assistant"))
    check("'open <app>' is not browser-shaped", d.dest == "assistant")
    # A trailing full stop is not a domain dot: transcribed speech routinely
    # ends a sentence with one, and "open calculator." previously built the
    # hostname "https://calculator." Probed against the real module before
    # the fix landed.
    d = dest("open calculator.", NOBODY, classify=classifier("assistant"))
    check("'open <app>.' with a trailing full stop is not browser-shaped", d.dest == "assistant", str(d))
    d = dest("open the settings file.", NOBODY, classify=classifier("assistant"))
    check("'open the settings file.' is not browser-shaped", d.dest == "assistant", str(d))

    # ── tier 3 ────────────────────────────────────────────────────────────
    calls.clear()
    d = dest("what do you think of the design", NOBODY, COLD, classify=classifier("assistant"))
    check("the classifier is asked when nothing rules", d.dest == "assistant" and d.reason == "classifier" and calls)
    # No answer means the assistant, even with the terminal warm. This used to
    # return the warm destination and that was a ratchet: once a sentence
    # landed in the terminal, every sentence the rules could not settle landed
    # there behind it. Four of the eight unsettled decisions on 2026-09-21 went
    # that way, a bare "No" among them.
    d = dest("what do you think of the design", NOBODY, mem("terminal", 30), classify=classifier(None))
    check("unsettled with the terminal warm: still the assistant",
          d.dest == "assistant" and d.reason == "unsettled", str(d))
    d = dest("what do you think of the design", NOBODY, COLD, classify=classifier(None))
    check("unsettled with nothing warm: the assistant", d.dest == "assistant")
    d = dest("what do you think", NOBODY, COLD, classify=classifier("nonsense"))
    check("a classifier answer that is not a destination is ignored", d.dest == "assistant" and d.reason == "unsettled")

    # The default is no classifier at all. `claude -p --model haiku` billed
    # 35,335 cache-creation tokens and $0.074 per three-word decision and took
    # 9 to 17 s against a 3 s timeout, so it never answered once: the
    # transcript has 8 timeouts and 0 classifier decisions.
    import os as _os
    _old = _os.environ.pop("HUD_CLASSIFY_CMD", None)
    _oldm = _os.environ.pop("HUD_MODEL_CMD", None)
    check("no classifier is configured by default", r._classify_cmd() is None)
    # The two commands are separate so that switching the classifier off does
    # not switch off the project summary. They shared one function, and the
    # first version of this change killed `summarize` silently: same CLI, but
    # a 20 second background budget it can actually meet.
    check("the background command is still the CLI", r._model_cmd()[:2] == ["claude", "-p"],
          str(r._model_cmd()))
    _os.environ["HUD_CLASSIFY_CMD"] = "echo hi"
    check("and a classifier can be put back", r._classify_cmd() == ["echo", "hi"])
    _os.environ.pop("HUD_CLASSIFY_CMD", None)
    if _old is not None:
        _os.environ["HUD_CLASSIFY_CMD"] = _old
    if _oldm is not None:
        _os.environ["HUD_MODEL_CMD"] = _oldm

    # ── tier 3: Jev ──────────────────────────────────────────────────────
    # Stubbed: the suite never touches the network. The live numbers are in
    # tests/eval_route_jev.py.
    import types
    stub = types.ModuleType("jev")
    seen_state = []

    def answering(choice, probs):
        def ask(state, questions, timeout=0, decision=None):
            seen_state.append(state)
            return None if choice is None else {"dest": {"type": "choice", "choice": choice, "probabilities": probs}}
        return ask
    sys.modules["jev"] = stub
    _off = _os.environ.pop("HUD_CLASSIFY_JEV", None)
    stub.ask = answering("terminal", {"terminal": 0.95, "assistant": 0.05})
    check("jev: a sure terminal answer goes to the terminal",
          r.classify_with_jev("rename that function", {"context": TERMINAL}) == "terminal")
    check("jev: the frontmost Claude tab is named in the state",
          seen_state[-1] == {"spoken": "rename that function", "frontmost_app": "Terminal (Claude Code)"}, str(seen_state[-1]))
    # "Create a bubble" came back terminal at 0.56 on 2026-09-23.
    stub.ask = answering("terminal", {"terminal": 0.56, "assistant": 0.43})
    check("jev: an unsure terminal answer falls to the assistant",
          r.classify_with_jev("Create a bubble", {}) == "assistant")
    stub.ask = answering("browser", {"browser": 0.72})
    check("jev: a browser answer stands", r.classify_with_jev("look up Clay pricing", {}) == "browser")
    stub.ask = answering(None, {})
    check("jev: no answer is no decision", r.classify_with_jev("hm", {}) is None)
    d = dest("what do you think of the design", NOBODY, COLD, classify=r.classify_with_jev)
    check("jev: no answer ends at the assistant, unsettled", d.dest == "assistant" and d.reason == "unsettled", str(d))
    stub.ask = answering("terminal", {"terminal": 0.99})
    _os.environ["HUD_CLASSIFY_JEV"] = "off"
    check("jev: HUD_CLASSIFY_JEV=off switches the tier off", r.classify_with_jev("fix it", {}) is None)
    _os.environ.pop("HUD_CLASSIFY_JEV", None)
    if _off is not None:
        _os.environ["HUD_CLASSIFY_JEV"] = _off
    d = dest("make the parser handle the format", TERMINAL, COLD, classify=r.classify_default)
    check("jev: the default classifier reaches the sentence the word list misses",
          d.dest == "terminal" and d.reason == "classifier", str(d))
    del sys.modules["jev"]

    # ── draft words ──────────────────────────────────────────────────────
    for said in ("send it", "Send.", "run it", "run", "confirm", "go", "do it", "send that"):
        check(f"submit word: {said!r}", r.draft_word(said) == "submit")
    for said in ("scrap that", "clear it", "never mind", "nevermind", "cancel that"):
        check(f"clear word: {said!r}", r.draft_word(said) == "clear")
    for said in ("no, to you", "not the terminal", "no not the terminal"):
        check(f"reroute word: {said!r}", r.draft_word(said) == "reroute")
    check("a sentence containing 'run' is not a draft word", r.draft_word("run the tests and tell me") is None)

    # ── browser urls ─────────────────────────────────────────────────────
    url, label = r.browser_url("look up rust traits")
    check("a lookup is a google search", url == "https://www.google.com/search?q=rust+traits" and label == "chrome: rust traits", str((url, label)))
    url, label = r.browser_url("go to github.com")
    check("go to a domain opens it", url == "https://github.com")
    url, label = r.browser_url("open hacker news dot com")
    check("'dot com' is spoken punctuation", url == "https://hackernews.com", url)
    url, label = r.browser_url("open calculator.")
    check("a trailing full stop falls back to a search", url.startswith("https://www.google.com/search?q="), url)
    url, label = r.browser_url("how do i center a div")
    check("a plain question is a search", url.startswith("https://www.google.com/search?q=how+do+i+center"))
    url, label = r.browser_url("in chrome look up flexbox")
    check("the explicit prefix is stripped", url.endswith("q=flexbox"))

    # ── seen_app ─────────────────────────────────────────────────────────
    check("seen_app takes the first receipt field", r.seen_app("Terminal · ~/dev/signaler · 12 chars selected") == "Terminal")
    check("seen_app on nothing is empty", r.seen_app("") == "")
    check("seen_app on a cannot-see line is empty", r.seen_app("cannot see the screen (x)") == "")

    # ── answer words ─────────────────────────────────────────────────────
    print("answer words")
    for said, want in [("yes", "allow"), ("Yeah.", "allow"), ("go ahead", "allow"), ("allow it", "allow"),
                       ("no", "deny"), ("Nope", "deny"), ("deny it", "deny"), ("don't", "deny"),
                       ("yes but only this once", None), ("open chrome", None),
                       ("do it", None)]:
        check(f"answer_word({said!r}) is {want}", r.answer_word(said) == want, str(r.answer_word(said)))
    # ask() runs the draft words before the terminal words, so a word in both
    # sets never reaches the permission dialog: "do it" was in ALLOW_WORDS
    # and SUBMIT_WORDS, and with a draft outstanding it submitted the draft.
    drafts = r.SUBMIT_WORDS | r.CLEAR_WORDS | r.REROUTE_WORDS
    answers = r.ALLOW_WORDS | r.DENY_WORDS | r.TERMINAL_STOP_WORDS
    check("no word is both a draft word and a terminal word",
          not (drafts & answers), str(sorted(drafts & answers)))
    for said, want in [("stop the terminal", True), ("Stop in the terminal.", True), ("terminal stop", True),
                       ("cancel the terminal", True), ("stop", False), ("stop the music", False)]:
        check(f"terminal_stop_word({said!r}) is {want}", r.terminal_stop_word(said) is want)

    for said, want in [("What are my agents doing?", True), ("how are the sessions going", True),
                       ("are my agents done", True), ("Who is waiting on me?", True), ("agent status", True),
                       ("what's the status of my terminals", True), ("what is running", True),
                       ("tell the agents to commit", False), ("what are you doing", False),
                       ("are the tests done", False), ("run the agents", False)]:
        check(f"agent_status_word({said!r}) is {want}", r.agent_status_word(said) is want)

    print(f"\n{PASSED} passed, {FAILED} failed")
    return 1 if FAILED else 0


if __name__ == "__main__":
    sys.exit(main())

"""Where a spoken sentence goes: terminal, browser, or the assistant.

Pure. Takes the sentence, what is in front of the person, and a memory dict,
and answers with a destination and why. Three tiers, cheapest first:
a correction of the last decision, then rules, then whatever HUD_CLASSIFY_CMD
names for what the rules cannot settle, and the assistant when nothing does.
The design and the evidence for each rule are in
the voice-routing design notes.

Tier 3 is TypeSafe's Jev (`classify_with_jev`), because it answers in a
quarter of a second where the Haiku CLI took 9 to 17. The frontmost
application is a prior here and not a destination: `_work_shaped` is the gate
that made it one, and `_classify_cmd` carries the measurement that switched
the CLI call off. `summarize` still runs the CLI, under a budget that can
afford it.
"""
import json
import os
import re
import shlex
import subprocess
from dataclasses import dataclass
from datetime import datetime
from typing import Callable, Sequence
from urllib.parse import quote_plus

DESTS = ("terminal", "browser", "assistant")

# A correction lands inside this many seconds of the decision it corrects.
# Guessed, never measured: long enough to finish a sentence and change your
# mind, short enough that "no" twenty seconds later means something else.
CORRECTION_S = 15.0
# The classifier answers in this or the sentence goes to the assistant. The
# lean voice session's measured time to first text is 1.1 to 6.0 s; a routing
# decision slower than the answer would be is not worth waiting for.
#
# Nothing is configured to answer that fast, so `_classify_cmd` is off by
# default and this bound only applies to an HUD_CLASSIFY_CMD somebody sets.
# The reason the default went away is in that function: it took 9 to 17 s.
CLASSIFY_TIMEOUT_S = 3.0

PERSON_VERBS = frozenset({
    "text", "message", "call", "facetime", "remind", "email", "mail",
    "schedule", "book", "cancel", "tell", "ask",
})
TIME_QUESTIONS = ("what time", "when is", "when's", "whens", "what's on", "whats on",
                  "what is on", "my calendar", "my schedule", "am i free", "note that")
CONTINUATION_OPENERS = frozenset({"and", "also", "then", "now", "next"})
IMPERATIVES = frozenset({
    "make", "fix", "add", "undo", "redo", "change", "remove", "delete", "rename",
    "move", "try", "run", "update", "put", "use", "revert", "rewrite", "refactor",
})
PRONOUNS = frozenset({"it", "that", "this", "one", "them", "those", "these"})
# What the coding session owns. A sentence has to name one of these for the
# frontmost Claude tab to claim it.
#
# Measured against the twenty routed sentences in ~/.bob/memory/transcript.jsonl
# on 2026-09-21. Nine of them were decided by the frontmost application alone,
# and eight of those nine went somewhere they did not belong: "Make a Google
# sheet comparing prices for Valencia", "Create a bubble" three times in
# different words, a bare "No" twice, a sentence about check-in dates, and the
# single word "Terminal". Not one of the eight names anything in this set.
# "write the readme" does, which is the true positive the gate has to keep.
#
# Words that mean something else in HIS life are left out even though they are
# ordinary code words, because a false positive here is the bug being fixed.
# "class" is a lecture, "route" is the drive to Valencia, "package" is a
# delivery, "file" is "file a reminder", "type" is "what type of", "method" is
# a payment method, "log" on its own is a journal entry. Dropping them costs
# little: "fix the type error" is caught by "error", "open the file" by the
# path pattern below, "check the logs" by the plural.
WORK_NOUNS = frozenset({
    "readme", "commit", "commits", "branch", "repo", "repository", "pr",
    "merge", "rebase", "diff", "build", "deploy", "lint", "typecheck",
    "test", "tests", "suite", "function", "script", "module", "import",
    "imports", "error", "errors", "exception", "traceback", "stacktrace",
    "bug", "endpoint", "schema", "migration", "dependency", "dependencies",
    "config", "hook", "hooks", "spec", "logs", "constant", "variable",
    "component", "docstring", "changelog", "checksum", "checksums",
})
WORK_VERBS = frozenset({"commit", "push", "pull", "rebase", "checkout", "stash", "clone"})
BROWSER_APPS = frozenset({"Google Chrome", "Chromium", "Arc", "Safari"})
BROWSER_OPENERS = ("look up ", "lookup ", "search for ", "search ", "google ", "go to ", "goto ")
DOMAIN_OPENERS = ("go to ", "goto ", "open ")
# A sentence asking for something to be done on a site, not just opened.
# The browser destination can only open a URL, so anything it cannot open
# becomes a Google search of the whole sentence. On 2026-09-23 "can you go to my
# linked in and edit my skills" went there through the classifier and opened
# exactly that search. The same sentence without "can you" was caught earlier by
# the "go to" opener, and with Chrome in front by the browser-in-front rule, so
# the rule applies at all three. A search keeps its own intent: "search for how
# to delete my account" is still a search.
SITE_TASK_WORDS = frozenset({
    "edit", "update", "change", "add", "remove", "delete", "fill", "post", "publish",
    "send", "message", "reply", "comment", "apply", "book", "buy", "order", "upload",
    "download", "reorder", "rearrange", "rename", "schedule", "cancel", "unsubscribe",
    "follow", "unfollow", "connect", "accept", "endorse", "submit", "save", "fix",
    "write", "set", "move", "invite", "share", "like", "pay", "checkout", "subscribe",
})
SITE_TASK_PHRASES = ("sign up", "sign in", "log in", "login to", "turn on", "turn off")
SEARCH_OPENERS = ("look up ", "lookup ", "search for ", "search ", "google ")
EXPLICIT_TERMINAL = ("in terminal", "in the terminal", "terminal,", "to the terminal")
EXPLICIT_BROWSER = ("in chrome", "in the browser", "in browser", "in safari")

SUBMIT_WORDS = frozenset({"send it", "send", "run it", "run", "confirm", "go", "do it",
                          "send that", "run that", "submit", "submit it", "enter"})
CLEAR_WORDS = frozenset({"scrap that", "scrap it", "clear it", "clear that", "never mind",
                         "nevermind", "cancel that", "cancel it", "forget it"})
REROUTE_WORDS = frozenset({"no to you", "not the terminal", "no not the terminal",
                           "not in the terminal", "to you"})

# Answers to the terminal's permission dialog, only while hud-listen's
# terminal state is waiting. "Always" is deliberately absent: a misheard
# word costs one tool call, never a standing rule.
#
# No word here, in DENY_WORDS, or in TERMINAL_STOP_WORDS may also be a draft
# word above. `ask()` checks the draft words first, so a word in both sets
# never reaches the terminal answer at all: "do it" was in ALLOW_WORDS and
# SUBMIT_WORDS, and with a draft outstanding it submitted the draft, which
# presses Return in the tab, while the person meant the permission dialog.
# "yes", "yeah", "yep", "go ahead", "allow" and "allow it" cover the intent.
ALLOW_WORDS = frozenset({"yes", "yeah", "yep", "go ahead", "allow", "allow it", "yes go ahead"})
DENY_WORDS = frozenset({"no", "nope", "deny", "deny it", "don't", "dont", "do not"})
TERMINAL_STOP_WORDS = frozenset({
    "stop the terminal", "stop in the terminal", "terminal stop", "stop terminal",
    "cancel the terminal", "stop it in the terminal",
})

# "What are my agents doing": answered from the agent board, no model. Exact
# phrasings plus one shape (a question word, an agent noun, a doing word), so
# an order that merely mentions agents ("tell the agents to commit") is not
# taken for a question.
AGENT_STATUS_WORDS = frozenset({
    "agent status", "agents status", "status of my agents", "status of the agents",
    "what's running", "whats running", "what is running",
    "who's waiting on me", "whos waiting on me", "who is waiting on me",
    "is anything waiting on me", "is anyone waiting on me", "anything waiting on me",
})
AGENT_STATUS_SHAPE = re.compile(
    r"^(what|how|what's|whats|are|is)\b.*\b(agents?|sessions?|terminals?|claudes?)\b"
    r".*\b(doing|up to|going|status|working on|done|finished)$"
    r"|^(what's|whats|what is) the status of (my|the) (agents?|sessions?|terminals?|claudes?)$"
)


@dataclass
class Decision:
    dest: str
    confidence: float
    reason: str
    reroute: str | None = None


def _words(said: str) -> list[str]:
    return re.sub(r"[^a-z0-9' ]+", " ", said.lower()).split()


def _norm(said: str) -> str:
    return " ".join(_words(said))


def _epoch(iso: str) -> float:
    try:
        return datetime.fromisoformat(iso).timestamp()
    except (TypeError, ValueError):
        return 0.0


def draft_word(said: str) -> str | None:
    words = _norm(said)
    if words in SUBMIT_WORDS:
        return "submit"
    if words in CLEAR_WORDS:
        return "clear"
    if words in REROUTE_WORDS:
        return "reroute"
    return None


def answer_word(said: str) -> str | None:
    words = _norm(said)
    if words in ALLOW_WORDS:
        return "allow"
    if words in DENY_WORDS:
        return "deny"
    return None


def terminal_stop_word(said: str) -> bool:
    return _norm(said) in TERMINAL_STOP_WORDS


def agent_status_word(said: str) -> bool:
    words = _norm(said)
    return words in AGENT_STATUS_WORDS or bool(AGENT_STATUS_SHAPE.match(words))


def seen_app(seen: str) -> str:
    if not seen or seen.startswith("cannot see") or seen == "nothing in front":
        return ""
    return seen.split(" · ")[0].strip()


def _explicit(said: str) -> str | None:
    low = said.lower().strip()
    if low.startswith(EXPLICIT_TERMINAL):
        return "terminal"
    if low.startswith(EXPLICIT_BROWSER):
        return "browser"
    return None


def _correction(said: str, memory: dict, now: float) -> Decision | None:
    last = memory.get("last")
    if not last or now - _epoch(last.get("t", "")) > CORRECTION_S:
        return None
    words = _norm(said)
    m = re.match(r"^(no|nope|not that|no not that)\s*(the |to )?(terminal|you|chrome|browser|safari)$", words)
    other = words == "other one" or words == "the other one"
    if not m and not other:
        return None
    if other:
        dest = "assistant" if last.get("dest") in ("terminal", "browser") else "terminal"
    else:
        dest = {"terminal": "terminal", "you": "assistant", "chrome": "browser",
                "browser": "browser", "safari": "browser"}[m.group(3)]
    return Decision(dest, 1.0, "correction", reroute=last.get("text", ""))


def _person_shaped(said: str, names: Sequence[str]) -> bool:
    words = _words(said)
    low = " ".join(words)
    if words and words[0] in PERSON_VERBS:
        return True
    if any(low.startswith(q) or f" {q}" in low for q in TIME_QUESTIONS):
        return True
    head = set(words[:6])
    return any(n.lower() in head for n in names if len(n) >= 3)


def _continuation(said: str) -> bool:
    words = _words(said)
    if not words:
        return False
    if words[0] in CONTINUATION_OPENERS:
        return True
    return words[0] in IMPERATIVES and any(w in PRONOUNS for w in words[1:4])


def _work_shaped(said: str) -> bool:
    """Whether the sentence names something the coding session owns.

    This is what stops the frontmost application being a destination. Having a
    Claude tab in front says where the person is looking, which is a weak prior
    and was being spent as a decision: see WORK_NOUNS for the nine rows it lost
    on.
    """
    words = _words(said)
    if not words:
        return False
    if any(w in WORK_NOUNS for w in words):
        return True
    if words[0] in WORK_VERBS:
        return True
    # A path or a filename. The dot has to sit between a word character and a
    # short lower-case extension, so "route.py" and "bin/lib" count while a
    # sentence that merely ends in a full stop does not: transcribed speech
    # ends in one constantly, and matching it would hand the terminal every
    # sentence that came out of the recogniser cleanly.
    return bool(re.search(r"[a-z0-9_-]+/[a-z0-9_.-]+|[a-z0-9_-]\.[a-z]{1,4}\b", said.lower()))


def _site_task(said: str) -> bool:
    """Something to do once the page is open, which only the assistant can do."""
    low = _norm(said) + " "
    if low.startswith(SEARCH_OPENERS):
        return False
    if any(w in SITE_TASK_WORDS for w in low.split()):
        return True
    return any(f" {p} " in f" {low}" for p in SITE_TASK_PHRASES)


def _browser_shaped(said: str) -> bool:
    low = _norm(said) + " "
    if low.startswith(BROWSER_OPENERS):
        return True
    if low.startswith("open "):
        rest = low[5:]
        # "open <x>" is browser-shaped only when the rest carries a domain:
        # a spoken " dot " or an intra-word dot in the raw sentence, like
        # "github.com". A trailing full stop is not a domain: transcribed
        # speech routinely ends in one ("open calculator." was probed
        # against the real module and built the hostname
        # "https://calculator."), so the dot must sit between two word
        # characters, never at the end of the sentence. Ruling: the brief's
        # extra "first word is 'hacker'" special case is dropped, the
        # " dot " check alone covers "open hacker news dot com".
        return " dot " in rest or bool(re.search(r"[a-z0-9]\.[a-z]", said.lower()))
    return False


def route(
    said: str,
    context: dict,
    memory: dict,
    names: Sequence[str] = (),
    now: float | None = None,
    classify: Callable[[str, dict], str | None] | None = None,
) -> Decision:
    import time as _time
    now = _time.time() if now is None else now
    classify = classify_default if classify is None else classify
    warm = memory.get("warm")
    app = context.get("app", "")

    explicit = _explicit(said)
    if explicit:
        return Decision(explicit, 1.0, "explicit")

    corrected = _correction(said, memory, now)
    if corrected:
        return corrected

    if _person_shaped(said, names):
        return Decision("assistant", 0.95, "person-shaped")

    if warm and _continuation(said):
        return Decision(warm, 0.85, f"continuation, {warm} warm")

    site_task = _site_task(said)
    browser_shaped = _browser_shaped(said) and not site_task
    if app == "Terminal" and context.get("claude_tab") and _work_shaped(said):
        return Decision("terminal", 0.8, "terminal in front, about the work")
    if app in BROWSER_APPS:
        if warm == "terminal" and not browser_shaped:
            return _classified(said, {**memory, "context": context}, classify)
        if site_task:
            return Decision("assistant", 0.8, "a task on a site")
        return Decision("browser", 0.8, "browser in front")

    if browser_shaped:
        return Decision("browser", 0.8, "browser-shaped")

    return _classified(said, {**memory, "context": context}, classify)


def _classified(said: str, memory: dict, classify) -> Decision:
    answer = classify(said, memory)
    if answer == "browser" and _site_task(said):
        return Decision("assistant", 0.6, "classifier said browser, but it is a task on a site")
    if answer in DESTS:
        return Decision(answer, 0.6, "classifier")
    # The assistant, never the warm destination, which is why this no longer
    # takes one. Falling back to warm is a ratchet: one sentence lands in the
    # terminal, the terminal is warm, and every sentence the rules cannot
    # settle lands there too until something wins outright. The transcript for
    # 2026-09-21 has 8 decisions reached this way and 4 of them were taken to
    # the terminal by that rule, a bare "No" among them.
    #
    # The asymmetry is what decides it. A sentence sent to the assistant by
    # mistake comes back as an answer or a question. A sentence sent to the
    # coding session by mistake comes back as a drafted prompt aimed at
    # somebody who asked about their calendar, which is the complaint that
    # started this.
    return Decision("assistant", 0.5, "unsettled")


def _browser_norm(said: str) -> str:
    """Lowercase, strip punctuation except '.' and '/', collapse whitespace,
    then turn spoken " dot " into ".". Kept separate from `_norm`, which
    strips '.' entirely and exists for the router's word matching, not for
    building a URL. See ruling 1 in the task-4 brief."""
    low = said.lower()
    low = re.sub(r"[^a-z0-9./ ]+", " ", low)
    low = re.sub(r"\s+", " ", low).strip()
    low = low.replace(" dot ", ".")
    return low


def browser_url(said: str) -> tuple[str, str]:
    low = said.strip()
    for prefix in EXPLICIT_BROWSER:
        if low.lower().startswith(prefix):
            low = low[len(prefix):].lstrip(" ,")
            break

    norm = _browser_norm(low)
    query = norm
    is_domain = False
    for opener in DOMAIN_OPENERS:
        if norm.startswith(opener):
            query = norm[len(opener):]
            is_domain = True
            break
    else:
        for opener in BROWSER_OPENERS:
            if norm.startswith(opener):
                query = norm[len(opener):]
                break

    host = query.replace(" ", "")
    # A domain needs a real TLD at the end, not just any dot: "open
    # calculator." normalises to a query ending in "." and must fall
    # through to a search, not build "https://calculator.".
    if is_domain and re.search(r"\.[a-z]{2,}$", host):
        return f"https://{host}", f"chrome: {host}"

    return f"https://www.google.com/search?q={quote_plus(query)}", f"chrome: {query}"


def _model_cmd() -> list[str] | None:
    """The background command, for work with a budget measured in seconds.

    `summarize` is the only caller and it runs after a turn with a 20 second
    bound, so the Claude Code CLI is fine here: slow and expensive is what a
    background call can afford.
    """
    cmd = os.environ.get("HUD_MODEL_CMD", "claude -p --model haiku --output-format json")
    if cmd == "off":
        return None
    return shlex.split(cmd)


def _classify_cmd() -> list[str] | None:
    """The classification command, off unless one is configured.

    It used to be `_model_cmd`, and the reason the classifier no longer shares
    it is a measurement rather than a preference. `claude -p --model haiku`
    loads the user's CLAUDE.md and its eleven imported rules before it answers
    anything, so on 2026-09-21 one three-word classification billed 35,335
    cache-creation tokens and $0.074, and took 9.0 to 17.0 seconds of wall
    clock across four runs, measured from an empty directory with MCP stripped
    out.

    CLASSIFY_TIMEOUT_S is 3.0. The call could therefore never once beat its
    own timeout, and the transcript agrees: 8 decisions carrying the reason
    "classifier timeout", 0 carrying "classifier". Every answer it produced
    was paid for and thrown away.

    Kept separate from `_model_cmd` so that switching it off does not switch
    off the project summary, which is the same command under a budget it can
    actually meet. Set HUD_CLASSIFY_CMD to something that answers inside three
    seconds and the tier comes back with no other change. An API call with a
    200 token prompt is that. A coding agent's CLI is not.
    """
    cmd = os.environ.get("HUD_CLASSIFY_CMD", "off")
    if cmd == "off":
        return None
    return shlex.split(cmd)


def _ask_model(prompt: str, timeout: float, argv: list[str] | None = None) -> str | None:
    argv = _model_cmd() if argv is None else argv
    if not argv:
        return None
    try:
        result = subprocess.run(argv, input=prompt, capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired):
        return None
    if result.returncode != 0:
        return None
    text = result.stdout.strip()
    try:
        outer = json.loads(text)
        if isinstance(outer, dict) and "result" in outer:
            text = str(outer["result"]).strip()
    except ValueError:
        pass
    return text


# Jev may send a sentence to the terminal only when it is at least this sure.
# Measured 2026-09-23 on the 30 hand-labelled sentences in
# tests/eval_route_jev.py: three bubble and window fragments came back
# terminal at 0.55, 0.56 and 0.62, and every real terminal request scored 0.80
# or higher. The asymmetry in `_classified` is why the floor sits on the
# terminal side only.
JEV_TERMINAL_FLOOR = 0.7

JEV_QUESTION = {"dest": {
    "type": "choice",
    "instructions": {
        "question": "The user said `spoken` out loud to their Mac. Which of the three should handle it?",
        "note": "Speech-to-text is noisy: fragments, filler and misheard words are common. "
                "A fragment or one-word utterance with no clear request belongs to the assistant.",
    },
    "criteria": {
        "terminal": "The coding session in the terminal: a request to change, build, fix, explain or "
                    "discuss the software they are building (the HUD, the voice assistant, Chewbacca, a "
                    "repo, a feature, a bug).",
        "browser": "Chrome, only to open a website or run a web search and stop there: 'open YouTube', "
                   "'search for flights to Tokyo'. If anything is to be done once the page is open (edit, "
                   "change, add, post, send, fill in, book, buy, check their account), it is not this one.",
        "assistant": "The voice assistant: questions, conversation, calendar, reminders, messages, "
                     "music, school, personal plans, making a spreadsheet or document, doing a task on a "
                     "website or in an app for them (editing their LinkedIn, posting, filling a form, "
                     "booking), fragments, and anything unclear.",
    },
}}


def classify_default(said: str, memory: dict) -> str | None:
    """HUD_CLASSIFY_CMD when somebody set one, otherwise Jev."""
    if _classify_cmd():
        return classify_with_haiku(said, memory)
    return classify_with_jev(said, memory)


def classify_with_jev(said: str, memory: dict) -> str | None:
    """One Choice question to TypeSafe's Jev, None when it cannot answer.

    The frontmost application is in the state because it moved one sentence
    of the thirty: "No, let's talk to text feature. We just built the bubble."
    scored terminal 0.80 with it and 0.59 without. HUD_CLASSIFY_JEV=off
    switches the tier off again.
    """
    if os.environ.get("HUD_CLASSIFY_JEV") == "off":
        return None
    import jev
    context = memory.get("context") or {}
    app = context.get("app") or "nothing"
    if app == "Terminal" and context.get("claude_tab"):
        app = "Terminal (Claude Code)"
    answers = jev.ask({"spoken": said, "frontmost_app": app}, JEV_QUESTION, timeout=CLASSIFY_TIMEOUT_S)
    answer = (answers or {}).get("dest") or {}
    choice = answer.get("choice")
    if choice not in DESTS:
        return None
    if choice == "terminal" and (answer.get("probabilities") or {}).get("terminal", 0.0) < JEV_TERMINAL_FLOOR:
        return "assistant"
    return choice


def classify_with_haiku(said: str, memory: dict) -> str | None:
    argv = _classify_cmd()
    if not argv:
        return None
    project = memory.get("project") or {}
    recent = memory.get("recent") or []
    lines = "\n".join(f"- {e.get('dest')}: {e.get('text')}" for e in recent[-5:]) or "- none"
    prompt = (
        "Where should this spoken sentence go? Reply with JSON only, {\"dest\": \"...\"}.\n"
        "Destinations: terminal (the Claude Code coding session"
        + (f"; they are building {project.get('summary')} in {project.get('name')}" if project.get("summary") else "")
        + "), browser (open or search the web), assistant (talk to the voice assistant: "
        "personal tasks, questions, anything else).\n"
        f"Recent sentences and where they went:\n{lines}\n"
        f"Sentence: {said!r}\n"
    )
    text = _ask_model(prompt, CLASSIFY_TIMEOUT_S, argv)
    if not text:
        return None
    m = re.search(r'"dest"\s*:\s*"(terminal|browser|assistant)"', text)
    return m.group(1) if m else None


def summarize(sentences: list[str]) -> str | None:
    """One line saying what is being built, from the last terminal-bound
    sentences. Never blocks a send: callers run it in a thread."""
    if not sentences:
        return None
    prompt = (
        "These are the last things a person said to their coding session, oldest first. "
        "In one line under fifteen words, what are they building? Reply with the line only.\n"
        + "\n".join(f"- {s}" for s in sentences[-20:])
    )
    # Twenty seconds: this runs in the background after a turn, so it can
    # take the time a haiku call actually takes on a cold start. Guessed.
    text = _ask_model(prompt, 20.0)
    return text.splitlines()[0].strip() if text else None

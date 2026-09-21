"""Where a spoken sentence goes: terminal, browser, or the assistant.

Pure. Takes the sentence, what is in front of the person, and a memory dict,
and answers with a destination and why. Three tiers, cheapest first:
a correction of the last decision, then rules, then one small model call for
what the rules cannot settle. The design and the evidence for each rule are
in docs/superpowers/specs/2026-09-20-voice-routing-design.md.
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
# The classifier answers in this or the warm destination wins. The lean voice
# session's measured time to first text is 1.1 to 6.0 s; a routing decision
# slower than the answer would be is not worth waiting for.
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
BROWSER_APPS = frozenset({"Google Chrome", "Chromium", "Arc", "Safari"})
BROWSER_OPENERS = ("look up ", "lookup ", "search for ", "search ", "google ", "go to ", "goto ")
DOMAIN_OPENERS = ("go to ", "goto ", "open ")
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
    classify = classify_with_haiku if classify is None else classify
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

    browser_shaped = _browser_shaped(said)
    if app == "Terminal" and context.get("claude_tab"):
        return Decision("terminal", 0.8, "terminal in front")
    if app in BROWSER_APPS:
        if warm == "terminal" and not browser_shaped:
            return _classified(said, memory, warm, classify)
        return Decision("browser", 0.8, "browser in front")

    if browser_shaped:
        return Decision("browser", 0.8, "browser-shaped")

    return _classified(said, memory, warm, classify)


def _classified(said: str, memory: dict, warm: str | None, classify) -> Decision:
    answer = classify(said, memory)
    if answer in DESTS:
        return Decision(answer, 0.6, "classifier")
    return Decision(warm or "assistant", 0.5, "classifier timeout")


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
    cmd = os.environ.get("HUD_CLASSIFY_CMD", "claude -p --model haiku --output-format json")
    if cmd == "off":
        return None
    return shlex.split(cmd)


def _ask_model(prompt: str, timeout: float) -> str | None:
    argv = _model_cmd()
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


def classify_with_haiku(said: str, memory: dict) -> str | None:
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
    text = _ask_model(prompt, CLASSIFY_TIMEOUT_S)
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

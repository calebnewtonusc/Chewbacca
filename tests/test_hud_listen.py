"""The loop, tested without a display, a microphone, or a model.

`hud listen` sits between the display and a model and had never been exercised
end to end: everything about it was verified by reading it. This stands up a
Unix socket that pretends to be the display, points the listener at it with a
fake model command, and checks what comes back.

The translator is tested against a real recording instead: fixtures/
hud-listen-stream.jsonl is one `claude -p --output-format stream-json` run
captured on CLI 2.1.278 (hook output blanked, because SessionStart hooks print
the owner's context into the stream and this repo is public). Re-record it with
the command in bin/hud-listen's design notes if the CLI changes shape.

Run: python3 tests/test_hud_listen.py
Under pytest: uv run --with pytest python -m pytest tests/ -q
(no system python3 on the dev Macs has pytest installed, and a bare
`python3 -m pytest` fails before collecting anything.)
"""

from __future__ import annotations

import importlib.util
import json
import os
import socket
import subprocess
import sys
import tempfile
import threading
import time
from importlib.machinery import SourceFileLoader
from pathlib import Path

# Optional. tests/run.sh executes this file as a plain script, and the CI runner
# has no pytest installed, so a hard import turned the whole suite red for a
# fixture that only pytest ever uses.
try:
    import pytest
except ModuleNotFoundError:
    pytest = None

BIN = Path(__file__).resolve().parent.parent / "bin" / "hud-listen"
FIXTURE = Path(__file__).resolve().parent / "fixtures" / "hud-listen-stream.jsonl"

failures: list[str] = []


if pytest is not None:

    @pytest.fixture
    def m():
        """Load the hud-listen script as a module for unit tests."""
        return load()

    @pytest.fixture(autouse=True)
    def no_failures():
        """`check` records rather than raises, so script mode can print every
        result before exiting 1. Under pytest that made every test pass no
        matter what it printed; this turns the recorded failures into one."""
        before = len(failures)
        yield
        assert failures[before:] == [], failures[before:]


def check(name: str, condition: bool, detail: str = "") -> None:
    if condition:
        print(f"  ok   {name}")
    else:
        print(f"  FAIL {name} {detail}")
        failures.append(name)


def load():
    # The script has no .py extension, so the loader has to be named: without
    # one, spec_from_file_location returns None and the failure points at
    # module_from_spec rather than at the missing suffix.
    # The bridge keeps every request in the superassistant log, and the
    # tests run whole requests: they must not land in the real one. Set
    # here, not in main(), because pytest loads through the fixture.
    import tempfile
    os.environ.setdefault("SUPERASSISTANT_DIR", tempfile.mkdtemp(prefix="superassistant-test-"))
    spec = importlib.util.spec_from_file_location(
        "hud_listen", BIN, loader=SourceFileLoader("hud_listen", str(BIN))
    )
    module = importlib.util.module_from_spec(spec)
    sys.modules["hud_listen"] = module
    spec.loader.exec_module(module)
    # No unit test may reach the real player. On 2026-09-20 the music
    # fast-path test's fake was dropped by the reloader, whose stamp it
    # had not set, and the real hud-music played a track on the
    # person's Spotify. With no file here, music() returns None unless
    # a test installs a fake by rebinding `music` itself.
    module.MUSIC = Path('/nonexistent/hud-music')
    module._music, module._music_stamp = None, 0.0
    return module


def test_draw_lines(m) -> None:
    """Only ops survive, and fences never do."""
    text = (
        "Here is your dashboard:\n"
        "```\n"
        "@ week at=topRight\n"
        "c s Screen title=\"WEEK\"\n"
        "r s\n"
        "```\n"
        "Let me know if you want changes.\n"
    )
    lines = m.draw_lines(text)
    check("prose is dropped", "Here is your dashboard:" not in lines)
    check("fences are dropped", not any(line.startswith("```") for line in lines))
    check("ops survive in order", lines == ["@ week at=topRight", 'c s Screen title="WEEK"', "r s"])
    check("an empty answer yields nothing", m.draw_lines("") == [])
    check(
        "a word that is not a verb is not an op",
        m.draw_lines("hello there\nz nope") == [],
    )
    check(
        "the pill's verbs pass the filter",
        m.draw_lines('s "on it"\nq 2') == ['s "on it"', "q 2"],
    )
    check(
        "prose is the complement of the ops",
        m.prose("Here you go:\n@ week at=topRight\n\nr s\nDone.") == "Here you go:\n\nDone.",
    )


def test_subtitle(m) -> None:
    """The reply cap lives here and nowhere else."""
    recorded = "Paris is the capital.\n\nIt has been since the tenth century. Before that, Laon."
    check(
        "the first paragraph is the lead and is kept",
        m.subtitle(recorded) == "Paris is the capital. It has been since the tenth century.",
        f"got {m.subtitle(recorded)!r}",
    )
    check("one paragraph is kept whole", m.subtitle("Sent.") == "Sent.")
    check(
        "only the first two sentences survive",
        m.subtitle("Sent. Sagar has it as of 6:14. Lunch is on the calendar too.")
        == "Sent. Sagar has it as of 6:14.",
    )
    check("newlines inside a paragraph become spaces",
          m.subtitle("one\ntwo") == "one two")
    long = " ".join(["word"] * 60)
    cut = m.subtitle(long)
    check("a long line is cut at a word boundary under the limit",
          len(cut) <= m.SUBTITLE_LIMIT + 1 and cut.endswith("…") and "word…" in cut,
          f"got {len(cut)} chars")
    check("a single token longer than the limit is still cut",
          len(m.subtitle("x" * 300)) == m.SUBTITLE_LIMIT + 1)
    check("nothing in, nothing out", m.subtitle("  \n\n ") == "")


def test_breadcrumb(m) -> None:
    """A tool call becomes the phrase the model already wrote for it."""
    check(
        "a Bash description is the breadcrumb",
        m.breadcrumb({"name": "Bash", "input": {"command": "date", "description": "Display current date and time"}})
        == "Display current date and time",
    )
    check("Read names the file", m.breadcrumb({"name": "Read", "input": {"file_path": "/a/b/ledger.yml"}}) == "Reading ledger.yml")
    check("Edit names the file", m.breadcrumb({"name": "Edit", "input": {"file_path": "/a/b/c.swift"}}) == "Editing c.swift")
    check("Grep names the pattern", m.breadcrumb({"name": "Grep", "input": {"pattern": "busy"}}) == "Searching for busy")
    check("an MCP tool is its last segment", m.breadcrumb({"name": "mcp__peekaboo__see", "input": {}}) == "see")
    check("a Skill names the skill", m.breadcrumb({"name": "Skill", "input": {"skill": "hud"}}) == "Using the hud skill")
    check("an unknown tool is its lowercased name", m.breadcrumb({"name": "Task", "input": {"prompt": "x"}}) == "task")
    check("no name at all is still a word", m.breadcrumb({}) == "working")


def test_translate_recorded_stream(m) -> None:
    """The recorded run, event by event, becomes exactly these lines.

    `now` steps by 3 s per event so every `thinking_tokens` event is past the
    pulse throttle and the pulses are deterministic; the throttle itself is
    checked separately below with two events 1 s apart.
    """
    run = m.Run()
    lines: list[str] = []
    events = [json.loads(raw) for raw in FIXTURE.read_text(encoding="utf-8").splitlines() if raw.strip()]
    check("the fixture is the 41-event recording", len(events) == 41, f"got {len(events)}")
    for i, event in enumerate(events):
        lines += run.translate(event, now=3.0 * i)

    def index(line: str) -> int:
        return lines.index(line) if line in lines else -1

    first_crumb = index('s "Display current date and time" step=true')
    acting = index("p acting")
    second_crumb = index('s "Display OS type" step=true')
    reply = index('s "Building ship-ready work today. It\'s Saturday, September 19, 2026."')
    check("the first tool call is its description", first_crumb >= 0, f"got {lines}")
    check("acting follows the first breadcrumb", 0 <= first_crumb < acting, f"got {lines}")
    check("the second tool call follows", acting < second_crumb, f"got {lines}")
    check("the final text block is the reply", second_crumb < reply, f"got {lines}")
    check("thinking is pulsed before any tool runs",
          "p thinking" in lines[:first_crumb], f"got {lines[:first_crumb]}")
    check("nothing after the reply",
          lines[-1] == 's "Building ship-ready work today. It\'s Saturday, September 19, 2026."', f"got {lines[-1:]}")
    check("no line is bare words",
          all(line.startswith(("p ", 's "', 'w "')) for line in lines), f"got {lines}")
    check("the answer is written for the panel before it is said on the pill",
          lines[-2] == 'w "Building ship-ready work today.\\n\\nIt\'s Saturday, September 19, 2026."',
          f"got {lines[-2:]}")
    check("the result is kept", run.ok and run.text.endswith("September 19, 2026."), f"got {run.text!r}")
    check("the API's clock is kept from the result", run.api_ms == 10947, f"got {run.api_ms}")
    check("the token counts are kept from the result",
          run.usage.get("cache_read_input_tokens") == 65612
          and run.usage.get("cache_creation_input_tokens") == 38801, f"got {run.usage}")
    check("both tool calls were counted", run.tools == 2, f"got {run.tools}")
    check("the first words were timed", run.first_text_at is not None)
    check("subtitle(run.text) is its first two sentences",
          m.subtitle(run.text) == "Building ship-ready work today. It's Saturday, September 19, 2026.",
          f"got {m.subtitle(run.text)!r}")
    check("the last phrase said is remembered",
          run.said == "Building ship-ready work today. It's Saturday, September 19, 2026.")

    # The throttle, the dedupe, and the subagent filter, each in one event.
    run = m.Run()
    tokens = {"type": "system", "subtype": "thinking_tokens"}
    burst = run.translate(tokens, now=10.0) + run.translate(tokens, now=11.0) + run.translate(tokens, now=12.5)
    check("two thinking_tokens inside PULSE_EVERY pulse once", burst == ["p thinking", "p thinking"], f"got {burst}")
    call = {"type": "assistant", "message": {"content": [{"type": "tool_use", "name": "Bash", "input": {"command": "mac calendar list", "description": "List today's events"}}]}}
    twice = run.translate(call, now=20.0) + run.translate(call, now=23.0)
    check("the same phrase twice is said once, pulsed twice",
          twice == ['s "List today\'s events" step=true', "p acting", "p acting"], f"got {twice}")
    child = dict(call, parent_tool_use_id="toolu_01")
    check("a subagent's calls are ignored", run.translate(child, now=30.0) == [])
    check("a thinking block says nothing",
          run.translate({"type": "assistant", "message": {"content": [{"type": "thinking", "thinking": ""}]}}, now=40.0) == [])


def test_stop(m) -> None:
    """`e stop <anything>` ends the run in flight and never reaches the model."""

    class FakeProc:
        def __init__(self) -> None:
            self.terminated = False
            self.killed = False

        def poll(self):
            return None if not self.terminated else 0

        def terminate(self) -> None:
            self.terminated = True

        def kill(self) -> None:
            self.killed = True

    listener = m.Listener("claude -p", False, False)
    asked: list[str] = []
    listener.ask = lambda said, **kw: asked.append(said)  # type: ignore[method-assign]
    sent: list[str] = []
    listener.send = sent.append
    listener.handle("e stop run")
    check("a stop with nothing running is harmless", asked == [])
    check("and still lands the pill, which the display put in working",
          sent == ['s "Nothing to stop."', "p failed"], f"got {sent}")
    req = m.Request(said="wait", spoken_at=0.0, pointed=None)
    proc = FakeProc()
    listener.running, listener.proc, listener.drawn = req, proc, ["week"]
    listener.handle("e stop run")
    check("the running process is signalled", proc.terminated)
    check("the stopped request is remembered with what it had drawn",
          listener.cancelled is req and listener.cancelled_drawn == ["week"])
    check("the stop was not sent to the model as a request", asked == [])
    listener.handle("e stop run x=1")
    check("a stop with a payload is still a stop", asked == [])
    listener.handle("e stop pill")
    check("a stop from any component is a stop", asked == [])
    listener.handle("e press send")
    check("any other control still becomes a request",
          asked == ["The user pressed press on send. Respond by updating the display."], f"got {asked}")


def test_speak(m) -> None:
    """A finished reply is read aloud; the next request or a stop cuts it off."""

    launched: list[list[str]] = []

    class FakeSay:
        def __init__(self, argv, **_kw) -> None:
            launched.append(argv)
            self.alive = True

        def poll(self):
            return None if self.alive else 0

        def terminate(self) -> None:
            self.alive = False

    real = m.subprocess.Popen
    m.subprocess.Popen = FakeSay
    try:
        listener = m.Listener("claude -p", False, False, voice="Samantha")
        listener.speak("Booked. Call with Caleb tomorrow at three.")
        check("the reply goes to say with the chosen voice",
              launched == [["say", "-v", "Samantha", "Booked. Call with Caleb tomorrow at three."]],
              f"got {launched}")
        first = listener.saying
        listener.speak("Second answer")
        check("a new reply cuts the old one off", not first.alive and listener.saying is not first)
        listener.hush()
        check("hush stops it and forgets it", listener.saying is None and not launched[-1] is None)
        quiet = m.Listener("claude -p", False, False)
        quiet.speak("nothing")
        check("no voice means no say", len(launched) == 2)
    finally:
        m.subprocess.Popen = real


def test_speak_kokoro(m) -> None:
    """A Kokoro voice goes to hud-speak as JSON lines; a broken pipe falls back to say."""

    class FakePipe:
        def __init__(self) -> None:
            self.lines: list[str] = []
            self.broken = False

        def write(self, line: str) -> None:
            if self.broken:
                raise BrokenPipeError
            self.lines.append(line)

        def flush(self) -> None:
            pass

    class FakeSpeaker:
        def __init__(self) -> None:
            self.stdin = FakePipe()
            self.stdout = None

        def poll(self):
            return None

    listener = m.Listener("claude -p", False, False)
    listener.voice = "af_heart"
    listener.speaker = speaker = FakeSpeaker()
    listener.speak("Booked.")
    listener.hush()
    check("say and hush are one JSON object per line",
          speaker.stdin.lines == ['{"say": "Booked."}\n', '{"hush": true}\n'],
          f"got {speaker.stdin.lines}")
    speaker.stdin.lines.clear()
    listener.handle('e say turn text="Two things.\\n\\n- **Origin Story** is due Tuesday"')
    check("the read-aloud button speaks the answer as prose, Markdown stripped",
          speaker.stdin.lines == ['{"say": "Two things. Origin Story is due Tuesday"}\n'],
          f"got {speaker.stdin.lines}")
    listener.handle("e say turn")
    listener.handle('e say turn text=""')
    check("a say with nothing to say is nothing", len(speaker.stdin.lines) == 1, f"got {speaker.stdin.lines}")
    speaker.stdin.lines.clear()
    listener.shown = "p done"
    listener.talking = True
    listener.handle("x")
    check("the display's dismiss hushes the voice", speaker.stdin.lines == ['{"hush": true}\n'], f"got {speaker.stdin.lines}")
    listener.heard_speaker({"quiet": True})
    check("and the quiet after it puts nothing back", listener.shown == "p dormant" and not listener.talking)
    speaker.stdin.broken = True
    listener.speak("Again.")
    check("a dead speaker means say, not silence",
          listener.speaker is None and listener.voice == m.FALLBACK_VOICE)
    check("hud-speak is a Kokoro name, say is a Mac name",
          m.KOKORO_VOICE.fullmatch("af_heart") and m.KOKORO_VOICE.fullmatch("am_michael")
          and not m.KOKORO_VOICE.fullmatch("Samantha"))


def test_voice_moves_the_ring(m) -> None:
    """hud-speak's level lines drive the ring as the microphone does, and
    quiet puts the bridge's own state back."""

    class FakeSock:
        def __init__(self) -> None:
            self.lines: list[str] = []

        def sendall(self, data: bytes) -> None:
            self.lines.append(data.decode().rstrip("\n"))

    listener = m.Listener("claude -p", False, False)
    listener.sock = sock = FakeSock()
    listener.send("p thinking")
    listener.heard_speaker({"level": 0.4})
    listener.send("p thinking")
    listener.heard_speaker({"level": 1.7})
    listener.heard_speaker({"quiet": True})
    check("a level is the same line the mic makes, a pulse mid-sentence is swallowed, "
          "and quiet restores the state",
          sock.lines == ["p thinking", "p speaking amp=0.40", "p speaking amp=1.00", "p thinking"],
          f"got {sock.lines}")
    listener.heard_speaker({"quiet": True})
    check("quiet with nothing playing sends nothing", sock.lines[-1] == "p thinking" and len(sock.lines) == 4)
    sock.lines.clear()
    listener.send("p done")
    listener.heard_speaker({"level": 0.5})
    listener.hush()
    listener.heard_speaker({"quiet": True})
    check("a cut-off restores nothing: the caller of hush sets what comes next",
          sock.lines == ["p done", "p speaking amp=0.50"], f"got {sock.lines}")
    listener.heard_speaker({"level": "loud"})
    check("a bad level is ignored", sock.lines[-1] == "p speaking amp=0.50")


def test_leaves_after_the_reply(m) -> None:
    """The hold is counted from the end of the voice; a new request ends it."""

    class FakeSock:
        def __init__(self) -> None:
            self.lines: list[str] = []

        def sendall(self, data: bytes) -> None:
            self.lines.append(data.decode().rstrip("\n"))

    listener = m.Listener("claude -p", False, False)
    listener.sock = sock = FakeSock()
    listener.voiced = True
    threading.Timer(0.4, lambda: setattr(listener, "voiced", False)).start()
    started = time.monotonic()
    listener.settle("done", 0.3)
    elapsed = time.monotonic() - started
    check("done, then the voice, then the hold, then it leaves",
          sock.lines == ["p done", "p dormant"] and 0.6 <= elapsed < 3.0,
          f"got {sock.lines} after {elapsed:.2f}s")
    sock.lines.clear()
    listener.queue.append(m.Request(said="and then", spoken_at=0.0, pointed=None))
    listener.settle("done", 0.3)
    check("a request spoken during the hold ends it with nothing sent",
          sock.lines == ["p done"], f"got {sock.lines}")


def test_stop_words(m) -> None:
    """The whole utterance is the gesture; a sentence that starts with it is not."""
    check("case and punctuation are ignored", m.normalise("Stop!") == "stop")
    check("a stop word with a full stop is a stop word", m.normalise("Never mind.") in m.STOP_WORDS)
    check("a request that begins with stop is a request", m.normalise("stop the music") not in m.STOP_WORDS)
    check("nothing said is not a stop", m.normalise("...") not in m.STOP_WORDS)
    check("no is only a stop while something is running",
          "no" in m.BARGE_WORDS and "no" not in m.STOP_WORDS)

    listener = m.Listener("claude -p", False, False)
    stops: list[str] = []
    listener.stop = lambda: stops.append("stop")
    sent: list[str] = []
    listener.send = sent.append
    drained: list[str] = []
    listener._drain = lambda: drained.append("drain")
    listener.ask("No.")
    check("with nothing running, no is a request", stops == [] and listener.current is not None
          and listener.current.said == "No.", f"got {stops} {listener.current}")
    listener.ask("Wait!")
    check("with a request in flight, wait stops it rather than queueing",
          stops == ["stop"] and len(listener.queue) == 0, f"got {stops} {list(listener.queue)}")
    listener.ask("Cancel")
    check("a plain stop word still stops", stops == ["stop", "stop"])


def test_drawn(m) -> None:
    """What reached the glass is read from results, never from intent."""

    def call(tool_id: str, command: str) -> dict:
        return {"type": "assistant", "message": {"content": [
            {"type": "tool_use", "id": tool_id, "name": "Bash", "input": {"command": command, "description": "Draw"}}]}}

    def result(tool_id: str, is_error: bool = False) -> dict:
        return {"type": "user", "message": {"content": [
            {"type": "tool_result", "tool_use_id": tool_id, "content": "", "is_error": is_error}]}}

    run = m.Run()
    run.translate(call("t1", "hud draw <<'EOF'\n@ week at=topRight\nc s Screen\nr s\n@ list at=top\nEOF"), now=0.0)
    check("a draw counts for nothing until its result is in", run.drawn == [])
    run.translate(result("t1"), now=1.0)
    check("every surface in a draw that succeeded", run.drawn == ["week", "list"], f"got {run.drawn}")
    run.translate(call("t2", "hud draw <<'EOF'\n@ extra at=top\nEOF"), now=2.0)
    run.translate(result("t2", is_error=True), now=3.0)
    check("a draw that failed drew nothing", run.drawn == ["week", "list"], f"got {run.drawn}")
    run.translate(call("t3", "hud close week"), now=4.0)
    check("hud close takes a surface off", run.drawn == ["list"], f"got {run.drawn}")
    run.translate(call("t4", "hud draw <<'EOF'\n- list\nEOF"), now=5.0)
    check("a `- name` line takes it off too", run.drawn == [], f"got {run.drawn}")
    run.translate(call("t5", "hud draw <<'EOF'\n@ week at=topRight\nEOF"), now=6.0)
    run.translate(result("t5"), now=7.0)
    run.translate(call("t6", "hud draw <<'EOF'\n@ week at=topRight\nEOF"), now=8.0)
    run.translate(result("t6"), now=9.0)
    check("a redraw is the same surface once", run.drawn == ["week"], f"got {run.drawn}")
    run.translate(call("t7", "date"), now=10.0)
    run.translate(result("t7"), now=11.0)
    run.translate({"type": "user", "message": {"content": "a plain turn"}}, now=12.0)
    check("other tools and plain turns change nothing", run.drawn == ["week"], f"got {run.drawn}")


def test_prompt_prefix(m) -> None:
    """After a stop, the next prompt says what the person actually saw."""
    listener = m.Listener("claude -p", False, False)
    stopped = m.Request(said="show my week", spoken_at=0.0, pointed=None)
    listener.cancelled, listener.cancelled_drawn = stopped, ["week", "list"]
    req = m.Request(said="just the overdue ones", spoken_at=1.0, pointed=(1, 2, 3, 4))
    prompt = listener.prompt_for(req, "Safari")
    check("it names the stopped request", "for 'show my week', was stopped" in prompt, f"got {prompt!r}")
    check("and which panels reached the screen",
          "Only these panels reached their screen: week, list." in prompt, f"got {prompt!r}")
    check("no correction framing", "correction" not in prompt)
    check("the request itself follows", prompt.index("was stopped") < prompt.index("'just the overdue ones'"))
    check("what they see and point at still ride along",
          "looking at: Safari" in prompt and "region (1, 2, 3, 4)" in prompt)
    check("the stop is told once", listener.cancelled is None)
    check("the next prompt carries no prefix", "was stopped" not in listener.prompt_for(req, ""))
    # The standing rules: in the system prompt under the lean profile, in
    # every request under the full one.
    standing = m.AGENT_PROMPT.read_text(encoding="utf-8")
    check("a full answer is asked for, and nothing drawn",
          "Never stop short" in standing and "read aloud to them one sentence at a time" in standing
          and "Do not draw on the display" in standing)
    plain = m.Listener("claude -p", False, False, profile="full").prompt_for(req, "")
    check("and the full profile still asks in the prompt",
          "Never stop short" in plain and "read aloud to them a sentence at a time" in plain
          and "Do not draw anything" in plain, f"got {plain!r}")
    typed = listener.prompt_for(m.Request(said="why", spoken_at=0.0, pointed=None, typed=True), "")
    check("a typed request is answered in writing",
          "typed this into the conversation panel" in typed and "Reply in writing" in typed
          and "read aloud to them a sentence" not in typed, f"got {typed!r}")
    check("and nothing asks for a panel", "hud skill" not in plain and "drawing on their display" not in plain)
    listener.cancelled, listener.cancelled_drawn = stopped, []
    check("nothing drawn says none", "reached their screen: none." in listener.prompt_for(req, ""))
    listener.cancelled = req
    own = listener.prompt_for(req, "")
    check("a request never reports its own stop, and leaves it for _run",
          "was stopped" not in own and listener.cancelled is req)


def test_session_flags(m) -> None:
    listener = m.Listener("claude -p", False, False)
    first = listener.command()
    check("first call opens a session", "--session-id" in first)
    listener.started = True
    second = listener.command()
    check("later calls resume it", "--resume" in second)
    check(
        "the session id is stable across calls",
        first[first.index("--session-id") + 1] == second[second.index("--resume") + 1],
    )
    other = m.Listener("llm -m gpt-5", False, False)
    other.started = True
    check("a non-claude command is left alone", other.command() == ["llm", "-m", "gpt-5"])


def test_turn_line(m) -> None:
    """One line, fixed order, `-` for what never arrived."""
    usage = {"input_tokens": 4, "cache_read_input_tokens": 11799,
             "cache_creation_input_tokens": 0, "output_tokens": 31}
    line = m.turn_line(0.02, 1.34, 1.61, 1970, usage, 1, 7)
    check("every field in its place",
          line == "turn: wait=0.0s text=1.3s audio=1.6s api=1970ms tools=1 "
                  "input=4 cache_read=11799 cache_create=0 output=31 session_turns=7",
          f"got {line!r}")
    bare = m.turn_line(None, None, None, None, {}, 0, 1)
    check("a value that never arrived is a dash",
          bare == "turn: wait=- text=- audio=- api=- tools=0 "
                  "input=- cache_read=- cache_create=- output=- session_turns=1",
          f"got {bare!r}")


def test_agent_flags(m) -> None:
    """The lean profile carries the person's permission posture across."""
    settings = {"permissions": {"defaultMode": "auto", "deny": ["Bash(rm -rf /)", 7, "Bash(curl* | sh)"]}}
    flags = m.agent_flags("lean", settings)
    check("the person's settings are dropped", flags[:2] == ["--setting-sources", "local"], f"got {flags}")
    check("one tool", "--tools=Bash" in flags)
    check("its own system prompt", "--system-prompt-file" in flags
          and flags[flags.index("--system-prompt-file") + 1].endswith("hud-agent.md"), f"got {flags}")
    check("their permission mode is passed back",
          flags[flags.index("--permission-mode") + 1] == "auto", f"got {flags}")
    passed = json.loads(flags[flags.index("--settings") + 1])
    check("their deny list is passed back, strings only",
          passed == {"permissions": {"deny": ["Bash(rm -rf /)", "Bash(curl* | sh)"]}}, f"got {passed}")
    odd = m.agent_flags("lean", {"permissions": {"defaultMode": "yolo"}})
    check("a mode this build does not know is left off",
          "--permission-mode" not in odd and "--settings" not in odd, f"got {odd}")
    check("no settings at all still leans", "--tools=Bash" in m.agent_flags("lean", {}))
    check("the full profile adds nothing", m.agent_flags("full", settings) == [])


def test_talk_key(m) -> None:
    """The talk key going down cuts the voice at once and mutes the run."""
    listener = m.Listener("claude -p", False, False)
    hushed: list[str] = []
    listener.hush = lambda: hushed.append("hush")
    listener.handle("k down")
    check("with nothing in flight the voice is still cut", hushed == ["hush"] and listener.muted is None)
    req = m.Request(said="what is on tomorrow", spoken_at=0.0, pointed=None, typed=False)
    listener.current = req
    listener.handle("k down")
    check("with a run in flight it is muted", hushed == ["hush", "hush"] and listener.muted is req)
    listener.handle("k up")
    check("the key coming up changes nothing on its own", listener.muted is req and listener.current is req)
    listener.current = None


def test_pick_filler(m) -> None:
    """A question gets a looking filler, a task an okay, never twice running."""
    check("a task", m.pick_filler("text caleb I am late") in m.TASK_FILLERS)
    check("a question by its first word", m.pick_filler("what's on tomorrow") in m.QUESTION_FILLERS)
    check("a question by its mark", m.pick_filler("Caleb around today?") in m.QUESTION_FILLERS)
    first = m.pick_filler("book a dentist")
    second = m.pick_filler("book a dentist", last=first)
    third = m.pick_filler("book a dentist", last=second)
    check("never the same one twice running", first != second and second != third, f"got {first}, {second}, {third}")
    check("a last filler from the other set still gives a fresh one",
          m.pick_filler("what time is it", last=m.TASK_FILLERS[0]) in m.QUESTION_FILLERS)
    check("nothing said still gets a filler", m.pick_filler("") in m.TASK_FILLERS)
    check("a task filler is an acknowledgement, never a yes or an okay",
          all(m.ACKNOWLEDGEMENT.fullmatch(f) for f in m.TASK_FILLERS) and not any(f.lower().rstrip(".") in ("okay", "ok", "yes", "sure", "yep") for f in m.TASK_FILLERS))
    check("the model's bare acknowledgements are known, so they are not said twice after a filler",
          all(m.ACKNOWLEDGEMENT.fullmatch(s) for s in ("On it.", "Right away.", "Doing that.", "Working on it.", "Handling it.", "Getting to it.", "on it"))
          and not any(m.ACKNOWLEDGEMENT.fullmatch(s) for s in ("Okay.", "On it. Texting Caleb you're running ten late.", "Chrome's up.", "")))


def test_lean_prompt(m) -> None:
    """The lean per-request prompt repeats only what changed."""
    listener = m.Listener("claude -p", False, False)
    req = m.Request(said="what is on tomorrow", spoken_at=0.0, pointed=None, typed=False)
    prompt = listener.prompt_for(req, "")
    check("the request is in it", "what is on tomorrow" in prompt)
    check("the standing rules are not", "Answer the way a good assistant" not in prompt, f"got {prompt!r}")
    typed = listener.prompt_for(m.Request(said="hi", spoken_at=0.0, pointed=None, typed=True), "")
    check("a typed request says so", "nothing is read aloud" in typed, f"got {typed!r}")
    full = m.Listener("claude -p", False, False, profile="full")
    check("the full profile keeps the rules in the prompt",
          "Answer the way a good assistant" in full.prompt_for(req, ""))
    check("the system prompt file exists", m.AGENT_PROMPT.is_file(), str(m.AGENT_PROMPT))
    standing = m.AGENT_PROMPT.read_text(encoding="utf-8")
    check("the prompt carries the acknowledge-first lines",
          "On it." in standing and "Texting Caleb" in standing and "Delete it?" in standing and "Simple gets simple" in standing
          and 'Never "Yes", "OK", "Okay", "Sure", "Yep"' in standing)
    check("and the banned openers", "Great question" in standing and "Certainly" in standing)
    check("the prompt names Chrome and the screen, with the hard lines",
          "chrome-js --list" in standing and "chewie see --app" in standing and "summarize" in standing
          and "Never type a password" in standing and "stays theirs" in standing)


def test_pick_names(m) -> None:
    chats = [
        {"name": "Caleb Newton", "isGroup": False},
        {"name": "+1 555 010 0000", "isGroup": False},
        {"name": "someone@example.com", "isGroup": False},
        {"name": "The Group", "isGroup": True},
        "not a row",
    ]
    contacts = [{"name": "caleb newton"}, {"name": " Sarah Chen "}, {"name": ""}, {"organization": "Acme"}]
    names = m.pick_names(chats, contacts)
    check("chats first, then contacts, once each, handles and groups left out",
          names == ["Caleb Newton", "Sarah Chen"], f"got {names}")
    check("nothing in, nothing out", m.pick_names([], []) == [])


def test_pointing(m) -> None:
    listener = m.Listener("claude -p", False, False)
    check("no region to start", listener.pointing() is None)
    listener.handle("g 100 200 320 90")
    check("a region is remembered", listener.pointing() == (100, 200, 320, 90))
    listener.region_at -= listener.POINT_TTL + 1
    check("a stale region is forgotten", listener.pointing() is None)
    listener.handle("g not numbers here")
    check("a malformed region is ignored", listener.pointing() is None)


def test_translate_deltas(m) -> None:
    """Text arrives as deltas: sentences go to the voice as they complete,
    the answer goes to the panel at each one, and the block event closes it."""

    def delta(text: str) -> dict:
        return {"type": "stream_event", "event": {"type": "content_block_delta", "index": 0,
                "delta": {"type": "text_delta", "text": text}}}

    start = {"type": "stream_event", "event": {"type": "content_block_start", "index": 0,
             "content_block": {"type": "text", "text": ""}}}
    stop = {"type": "stream_event", "event": {"type": "content_block_stop", "index": 0}}
    full = "Paris is the capital. It has been since **987**, more or less.\n\n- one thing\n- and another one"
    run = m.Run()
    run.subtitles = False
    lines = run.translate(start, 0.0)
    lines += run.translate(delta("Paris is the "), 0.1)
    check("half a sentence says nothing", lines == [] and run.take_voice() == [], f"got {lines}")
    lines += run.translate(delta("capital. It has been since **987**, "), 0.2)
    check("a finished sentence goes to the voice", run.take_voice() == ["Paris is the capital."])
    check("and the answer so far goes to the panel",
          lines == ['w "Paris is the capital. It has been since **987**,"'], f"got {lines}")
    lines = run.translate(delta("more or less.\n\n- one thing\n- and another one"), 0.3)
    voice = run.take_voice()
    check("markdown is not read aloud, and a short line waits for the next",
          voice == ["It has been since 987, more or less."], f"got {voice}")
    lines += run.translate({"type": "assistant", "message": {"content": [{"type": "text", "text": full}]}}, 0.4)
    lines += run.translate(stop, 0.5)
    check("the block event closes the answer without a subtitle",
          lines[-1] == "w " + json.dumps(full) and not any(l.startswith("s ") for l in lines), f"got {lines}")
    check("the held lines are said once, together, at the close",
          run.take_voice() == ["one thing and another one"])
    check("the answer is the block", run.answer() == full)

    # No deltas at all: a model command that does not stream partial messages.
    run = m.Run()
    lines = run.translate({"type": "assistant", "message": {"content": [{"type": "text", "text": "Sent. Sagar has it."}]}}, 1.0)
    check("a whole block is spoken and written and subtitled",
          run.take_voice() == ["Sent. Sagar has it."] and lines == ['w "Sent. Sagar has it."', 's "Sent. Sagar has it."'],
          f"got {lines}")
    # Two blocks around a tool call are two paragraphs of one answer.
    run.translate({"type": "assistant", "message": {"content": [{"type": "text", "text": "Also booked."}]}}, 2.0)
    check("blocks join as paragraphs", run.answer() == "Sent. Sagar has it.\n\nAlso booked.")


def test_long_answer_switch(m) -> None:
    """The panel's switch off: a long answer is read out in full with no
    pointer, the bridge remembers the setting, and the model is told per
    spoken request."""
    listener = m.Listener("claude -p", False, False)
    check("written is the default", listener.long_written)
    listener.handle("e prefer voice long=spoken")
    check("spoken is remembered", not listener.long_written)
    listener.handle("e prefer voice long=written")
    check("and written again", listener.long_written)
    listener.handle('e prefer voice long="spoken"')
    check("a quoted value is the same value", not listener.long_written)
    listener.handle("e prefer voice long=loud")
    listener.handle("e prefer sound long=written")
    check("an unknown value or component changes nothing", not listener.long_written)

    req = m.Request(said="summarise the war", spoken_at=0.0, pointed=None)
    prompt = listener.prompt_for(req, "")
    check("the model is told to read it all out",
          "read this answer out in full" in prompt and "do not point at the hyper bar" in prompt,
          prompt[-240:])
    typed = m.Request(said="summarise the war", spoken_at=0.0, pointed=None, typed=True)
    check("a typed request is read by nobody, so it carries no note",
          "read this answer out" not in listener.prompt_for(typed, ""))
    listener.long_written = True
    check("written: the standing rule stands, no note",
          "read this answer out" not in listener.prompt_for(req, ""))

    def delta(text: str) -> dict:
        return {"type": "stream_event", "event": {"type": "content_block_delta", "index": 0,
                "delta": {"type": "text_delta", "text": text}}}

    start = {"type": "stream_event", "event": {"type": "content_block_start", "index": 0,
             "content_block": {"type": "text", "text": ""}}}
    long = " ".join(f"Sentence number {i} of the recap is here." for i in range(1, 13))
    run = m.Run()
    run.subtitles = False
    run.long_written = False
    lines = run.translate(start, 0.0)
    lines += run.translate(delta(long), 0.1)
    lines += run.translate({"type": "assistant", "message": {"content": [{"type": "text", "text": long}]}}, 0.2)
    said = " ".join(run.take_voice())
    check("twelve sentences are all spoken, past the cap",
          "Sentence number 1 " in said and "Sentence number 12" in said, said[-80:])
    check("no pointer is added", m.HYPER_BAR_POINTER not in said and not run.written_aside)
    check("the whole answer still reaches the panel", lines[-1] == "w " + json.dumps(long))

    recap = ("All the info on the Civil War is ready for you in the hyper bar.\n\n"
             "It ran from 1861 to 1865. Roughly 750,000 people died.")
    run = m.Run()
    run.subtitles = False
    run.long_written = False
    run.translate(start, 0.0)
    run.translate(delta(recap), 0.1)
    run.translate({"type": "assistant", "message": {"content": [{"type": "text", "text": recap}]}}, 0.2)
    said = " ".join(run.take_voice())
    check("a pointer sentence no longer ends the spoken part", "1861" in said and "750,000" in said, said)


def test_guide_hit(m) -> None:
    """A click on a guide bubble asks the model for the next step, marked
    as relayed from the screen rather than said by the person."""
    listener = m.Listener("claude -p", False, False)
    asked: list[tuple[str, dict]] = []
    listener.ask = lambda said, **kw: asked.append((said, kw))  # type: ignore[method-assign]
    listener.handle('e hit guide label="Sign in"')
    check("one ask", len(asked) == 1)
    said, kw = asked[0] if asked else ("", {})
    check("it names what they clicked", "'Sign in'" in said, said)
    check("it says to look again and show the next step", "hud-guide" in said and "next step" in said)
    check("it is relayed, not said", kw.get("relayed") is True)
    listener.handle("e hit guide label=Next")
    check("a bare label is read too", len(asked) == 2 and "'Next'" in asked[1][0])
    listener.handle("e hit guide")
    check("no label still asks", len(asked) == 3 and "the highlighted control, and" in asked[2][0], asked[2][0] if len(asked) > 2 else "")
    listener.handle("e hit other label=Next")
    check("only a guide is a guide", len(asked) == 3)

    req = m.Request(said="They just clicked it.", spoken_at=0.0, pointed=None, relayed=True)
    prompt = listener.prompt_for(req, "")
    check("the prompt says it came from the screen",
          prompt.startswith("From their screen, not from them: They just clicked it.") and "said this out loud" not in prompt,
          prompt[:120])


def test_music_fast_path(m) -> None:
    """"Play X" never reaches the model: the bridge reads the words, drives the
    player, and says how it went. A bare stop word pauses the music when it is
    the only thing running."""
    import types
    played: list[str] = []
    state = {"player": None}

    class Command:
        def __init__(self, verb: str, what: str = "") -> None:
            self.verb, self.what = verb, what
            self.quiet_miss = False

    class Outcome:
        def __init__(self, ok: bool, line: str, unsure: bool = False) -> None:
            self.ok, self.line, self.unsure = ok, line, unsure

    def parse(said: str):
        words = said.lower().rstrip(".!")
        if words.startswith("play "):
            return Command("play", words[5:])
        if words == "pause":
            return Command("pause")
        return None

    def perform(command):
        played.append(command.verb + (":" + command.what if command.what else ""))
        if command.verb == "play" and command.what == "freddie again":
            return Outcome(False, "Not sure what freddie again is.", unsure=True)
        if command.verb == "play":
            state["player"] = "spotify"
            return Outcome(True, f"Playing {command.what.title()}.")
        if command.verb == "pause":
            state["player"] = None
            return Outcome(True, "Paused.")
        return Outcome(False, "Nothing's playing.")

    fake = types.SimpleNamespace(parse=parse, perform=perform, Command=Command, Outcome=Outcome,
                                 active_player=lambda: state["player"])
    kept = m.music
    m.music = lambda: fake
    try:
        listener = m.Listener("claude -p", False, False)
        sent: list[str] = []
        listener.send = sent.append
        spoken: list[str] = []
        listener.speak = spoken.append
        remembered: list[tuple[str, str, str]] = []
        listener.remember = lambda req, answer, ok, outcome: remembered.append((req.said, answer, outcome))
        listener.settle = lambda state, hold: None
        drained: list[str] = []
        listener._drain = lambda: drained.append("drain")
        stops: list[str] = []
        listener.stop = lambda: stops.append("stop")

        listener.ask("Play blinding lights.")
        deadline = time.monotonic() + 3
        while listener.current is not None and time.monotonic() < deadline:
            time.sleep(0.02)
        check("the player was driven, not the model", played == ["play:blinding lights"] and drained == [], f"{played} {drained}")
        check("the answer went to the panel and the pill",
              'w "Playing Blinding Lights." done=true' in sent and 's "Playing Blinding Lights."' in sent, str(sent))
        check("and was spoken", spoken == ["Playing Blinding Lights."], str(spoken))
        check("and kept in the log", remembered == [("Play blinding lights.", "Playing Blinding Lights.", "done")], str(remembered))
        check("the glass is free again", listener.current is None and listener.running is None)

        listener.ask("Stop.")
        deadline = time.monotonic() + 3
        while listener.current is not None and time.monotonic() < deadline:
            time.sleep(0.02)
        check("a bare stop with music on pauses the music and does not stop the bridge",
              played[-1] == "pause" and stops == [] and spoken[-1] == "Paused.", f"{played} {stops} {spoken}")
        listener.ask("Stop.")
        check("a bare stop with nothing on is the bridge's stop", stops == ["stop"] and played[-1] == "pause", f"{stops} {played}")

        listener.ask("What is due this week?")
        check("anything else goes to the model", listener.current is not None and listener.current.said == "What is due this week?"
              and drained == ["drain"], f"{listener.current} {drained}")
        listener.current = None
        listener.ask("Play hotline bling.", typed=True)
        deadline = time.monotonic() + 3
        while listener.current is not None and time.monotonic() < deadline:
            time.sleep(0.02)
        check("a typed request is written, not spoken", played[-1] == "play:hotline bling" and spoken[-1] == "Paused.", f"{played} {spoken}")

        drained.clear()
        listener.ask("Play something chill.")
        deadline = time.monotonic() + 3
        while listener.current is not None and time.monotonic() < deadline:
            time.sleep(0.02)
        check("words that describe are played like any other, Spotify's search decides",
              drained == [] and played[-1] == "play:something chill" and spoken[-1] == "Playing Something Chill.", f"{drained} {played} {spoken}")
        drained.clear()
        listener.ask("Play freddie again.")
        deadline = time.monotonic() + 3
        while not drained and time.monotonic() < deadline:
            time.sleep(0.02)
        check("a guess nothing was sure of goes to the model with the music hint, and was not played",
              drained == ["drain"] and played[-1] == "play:freddie again" and listener.current is not None
              and "hud-music play --anyway" in listener.current.hint and spoken[-1] == "Playing Something Chill.", f"{drained} {played} {spoken}")
        prompt = listener.prompt_for(listener.current, "")
        check("the prompt carries the hint", "could not settle" in prompt and "Play freddie again." in prompt, prompt[:200])
        listener.current = None
    finally:
        m.music = kept


def test_remember(m) -> None:
    """Every request and its answer reach the superassistant log, and the
    prompt the agent is given carries the brain digest."""
    import tempfile
    module = m.superassistant()
    check("the superassistant module loads next to the bridge", module is not None)
    with tempfile.TemporaryDirectory() as tmp:
        log = Path(tmp) / "questions.jsonl"
        kept, module.LOG = module.LOG, log
        try:
            listener = m.Listener("claude -p", False, False)
            listener.aside = True
            req = m.Request(said="what is due this week", spoken_at=time.monotonic(), pointed=None)
            listener.remember(req, "Two things.\n\nANTH reading and the SPAN quiz.", True, "done")
            listener.remember(m.Request(said="never mind", spoken_at=time.monotonic(), pointed=None, typed=True),
                              "", False, "cancelled")
            rows = module.entries(log)
        finally:
            module.LOG = kept
    check("two questions, in order", [r["said"] for r in rows] == ["what is due this week", "never mind"],
          f"got {rows}")
    check("the answer, the outcome and the session travel with it",
          rows[0]["answer"].startswith("Two things.") and rows[0]["outcome"] == "done"
          and rows[0]["aside"] and rows[0]["session"] == listener.session and "at" in rows[0])
    check("a typed cancel is kept as one", rows[1]["typed"] and rows[1]["outcome"] == "cancelled")
    check("the agent is given the prompt with the digest",
          listener.prompt_path.name == "agent-prompt.md"
          and "--system-prompt-file" in listener.flags
          and listener.flags[listener.flags.index("--system-prompt-file") + 1] == str(listener.prompt_path)
          and "# Who you are talking to" in listener.prompt_path.read_text(),
          f"got {listener.prompt_path} {listener.flags}")


def test_read_aloud_skips_the_pointer(m) -> None:
    """The panel's read-aloud button starts at the answer, not at the
    sentence that pointed at the panel."""
    recap = ("All the info on the Civil War is ready for you in the hyper bar.\n\n"
             "The war ran from 1861 to 1865.\n\nRoughly 750,000 people died.")
    check("the pointer paragraph goes",
          m.without_pointer(recap) == "The war ran from 1861 to 1865.\n\nRoughly 750,000 people died.",
          repr(m.without_pointer(recap)))
    mixed = "Short version: it was about slavery. The full recap is in the hyper bar.\n\nIt ran from 1861 to 1865."
    check("only the pointing sentence goes",
          m.without_pointer(mixed) == "Short version: it was about slavery.\n\nIt ran from 1861 to 1865.",
          repr(m.without_pointer(mixed)))
    plain = "Paris.\n\nIt has been the capital since 987."
    check("an answer with no pointer is untouched", m.without_pointer(plain) == plain)
    body = "The hyper bar is the pill at the bottom.\n\nClick it to open the conversation."
    check("the first sentence naming it is still a pointer, the rest stays",
          m.without_pointer(body) == "Click it to open the conversation.", repr(m.without_pointer(body)))
    only = "The rest is in the hyper bar."
    check("a pointer with nothing after it is read as it is", m.without_pointer(only) == only)

    listener = m.Listener("claude -p", False, False)
    said: list[str] = []
    listener.speak = said.append
    listener.handle("e say turn text=" + json.dumps(recap))
    check("the button reads the answer only",
          said == ["The war ran from 1861 to 1865. Roughly 750,000 people died."], f"got {said}")


def test_hyper_bar(m) -> None:
    """A long answer is written for the hyper bar and the voice says only
    the sentence that points there."""

    def delta(text: str) -> dict:
        return {"type": "stream_event", "event": {"type": "content_block_delta", "index": 0,
                "delta": {"type": "text_delta", "text": text}}}

    start = {"type": "stream_event", "event": {"type": "content_block_start", "index": 0,
             "content_block": {"type": "text", "text": ""}}}
    recap = ("All the info on the Civil War is ready for you in the hyper bar.\n\n"
             "The war ran from 1861 to 1865. It began when Southern states seceded after Lincoln's "
             "election.\n\nRoughly 750,000 people died. It ended with the Union preserved and slavery "
             "abolished by the Thirteenth Amendment.")
    run = m.Run()
    run.subtitles = False
    lines = run.translate(start, 0.0)
    lines += run.translate(delta(recap[:40]), 0.1)
    lines += run.translate(delta(recap[40:120]), 0.2)
    lines += run.translate(delta(recap[120:]), 0.3)
    lines += run.translate({"type": "assistant", "message": {"content": [{"type": "text", "text": recap}]}}, 0.4)
    voice = run.take_voice()
    check("only the pointer is spoken",
          voice == ["All the info on the Civil War is ready for you in the hyper bar."], f"got {voice}")
    check("the whole answer reaches the panel", lines[-1] == "w " + json.dumps(recap), f"got {lines[-1]}")
    check("the run knows it wrote aside", run.written_aside)

    # A pointer that is not the first sentence still ends the spoken part.
    run = m.Run()
    run.subtitles = False
    text = "Short version: it was about slavery. The full recap is in the hyper bar.\n\nIt ran from 1861 to 1865."
    run.translate({"type": "assistant", "message": {"content": [{"type": "text", "text": text}]}}, 1.0)
    voice = run.take_voice()
    check("spoken up to and including the pointer",
          voice == ["Short version: it was about slavery.", "The full recap is in the hyper bar."], f"got {voice}")

    # No pointer and no end in sight: the cap cuts it and says where the rest is.
    run = m.Run()
    run.subtitles = False
    long = " ".join(f"Sentence number {i} of the recap has eight words in it." for i in range(1, 13))
    run.translate({"type": "assistant", "message": {"content": [{"type": "text", "text": long}]}}, 2.0)
    voice = run.take_voice()
    said = " ".join(voice[:-1]).split()
    check("the voice stops near the cap",
          m.SPOKEN_CAP <= len(said) < m.SPOKEN_CAP + 12, f"spoke {len(said)} words")
    check("and says where the rest went", voice[-1] == m.HYPER_BAR_POINTER, f"got {voice[-1]!r}")
    check("the panel still has all of it", run.answer() == long)
    check("the run knows it wrote aside", run.written_aside)

    # Short answers, and short steps around tool calls, are untouched.
    run = m.Run()
    run.subtitles = False
    run.translate({"type": "assistant", "message": {"content": [{"type": "text", "text": "Checking Friday."}]}}, 3.0)
    run.translate({"type": "assistant", "message": {"content": [{"type": "text", "text": "Nothing on Friday, it's wide open. Saturday has the game at noon."}]}}, 4.0)
    voice = run.take_voice()
    check("a short reply is spoken in full",
          voice == ["Checking Friday.", "Nothing on Friday, it's wide open.", "Saturday has the game at noon."], f"got {voice}")
    check("and nothing was written aside", not run.written_aside)

    # The fallback subtitle, with no voice to caption the pill, stops at the pointer too.
    check("the subtitle is the pointer alone",
          m.subtitle(recap) == "All the info on the Civil War is ready for you in the hyper bar.", f"got {m.subtitle(recap)!r}")

    standing = m.AGENT_PROMPT.read_text(encoding="utf-8")
    check("the prompt teaches the hyper bar",
          "hyper bar" in standing and "All the info on the Civil War" in standing)


def test_spoken(m) -> None:
    """What the voice gets: the words, not the markup."""
    check("emphasis and code marks go", m.spoken("It is **bold**, *soft*, and `code`.") == "It is bold, soft, and code.")
    check("headings and list markers go", m.spoken("## Plan\n1. first\n- second") == "Plan first second")
    check("a link is its text", m.spoken("see [the docs](https://x.y) now") == "see the docs now")
    check("a rule is nothing", m.spoken("---") == "")
    check("a table is its cells", m.spoken("| a | b |\n|---|---|\n| 1 | 2 |") == "a, b 1, 2")
    check("an asterisk in arithmetic stays", m.spoken("3 * 4 is 12") == "3 * 4 is 12")


def test_typed_request(m) -> None:
    """`h "<text>" via=typed` is a typed request; the string alone is spoken."""
    listener = m.Listener("claude -p", False, False)
    asked: list[tuple[str, bool]] = []
    listener.ask = lambda said, typed=False, **kw: asked.append((said, typed))  # type: ignore[method-assign]
    listener.handle('h "what is due"')
    listener.handle('h "and next week" via=typed')
    listener.handle('h 42')
    check("the flag is read after the string",
          asked == [("what is due", False), ("and next week", True)], f"got {asked}")


def test_voice_in_parts(m) -> None:
    """A reply goes to hud-speak a sentence at a time, and its captions
    come back as subtitles."""

    class FakePipe:
        def __init__(self) -> None:
            self.lines: list[str] = []

        def write(self, line: str) -> None:
            self.lines.append(line)

        def flush(self) -> None:
            pass

    class FakeSpeaker:
        def __init__(self) -> None:
            self.stdin = FakePipe()

        def poll(self):
            return None

    class FakeSock:
        def __init__(self) -> None:
            self.lines: list[str] = []

        def sendall(self, data: bytes) -> None:
            self.lines.append(data.decode().rstrip("\n"))

    listener = m.Listener("claude -p", False, False)
    listener.voice = "af_heart"
    listener.speaker = speaker = FakeSpeaker()
    listener.sock = sock = FakeSock()
    check("the first part cuts in and holds the quiet",
          listener.speak_part("Paris.", first=True) and speaker.stdin.lines == ['{"say": "Paris.", "more": true}\n'],
          f"got {speaker.stdin.lines}")
    check("the rest queue behind it",
          listener.speak_part("It is old.", first=False) and speaker.stdin.lines[-1] == '{"add": "It is old."}\n')
    check("the voice is counted as active before a level arrives", listener.voiced)
    listener.heard_speaker({"saying": "Paris."})
    check("a caption is the subtitle", sock.lines == ['s "Paris."'], f"got {sock.lines}")
    check("nothing goes to a missing speaker",
          not m.Listener("claude -p", False, False).speak_part("x", first=True))


def test_end_to_end() -> None:
    """Stand up a fake display and run the real script against it."""
    directory = tempfile.mkdtemp()
    path = os.path.join(directory, "hud.sock")

    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(path)
    server.listen(1)

    received: list[str] = []
    ready = threading.Event()

    def serve() -> None:
        conn, _ = server.accept()
        ready.set()
        # Say something to it, the way the display would after hearing it.
        conn.sendall(b'h "show me my week"\n')
        conn.settimeout(30)
        buffer = b""
        try:
            # Until `p dormant`, the settle after the answer. Counting lines
            # instead stopped early whenever the draw lines and `p done`
            # arrived in one chunk, which they do, and the test failed on its
            # last check.
            while "p dormant" not in received:
                chunk = conn.recv(4096)
                if not chunk:
                    break
                buffer += chunk
                while b"\n" in buffer:
                    line, buffer = buffer.split(b"\n", 1)
                    received.append(line.decode())
        except socket.timeout:
            pass
        conn.close()

    thread = threading.Thread(target=serve, daemon=True)
    thread.start()

    # A "model" that prints one panel and some prose around it.
    fake = os.path.join(directory, "fake-model")
    with open(fake, "w", encoding="utf-8") as handle:
        handle.write(
            "#!/bin/sh\n"
            "cat > /dev/null\n"
            "echo 'Here you go:'\n"
            "echo '@ week at=topRight'\n"
            "echo 'c s Screen title=\"WEEK\"'\n"
            "echo 'r s'\n"
        )
    os.chmod(fake, 0o755)

    env = dict(os.environ, BOB_HUD_SOCKET=path, HUD_NAMES="off")
    process = subprocess.Popen(
        [sys.executable, str(BIN), "--model-cmd", fake],
        env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    ready.wait(10)
    thread.join(35)
    process.terminate()
    process.wait(timeout=10)
    server.close()

    # `listen` first: the display sends nothing back until a client asks, so a
    # transcript never reaches a process that only wanted to draw.
    check("it subscribes before anything else", received and received[0] == "listen",
          f"got {received[:1]}")
    check("then it announces itself", "p attentive" in received, f"got {received[:2]}")
    check("it said it was thinking", "p thinking" in received, f"got {received}")
    check("it drew the panel", "@ week at=topRight" in received, f"got {received}")
    check("prose from the model was not sent to the parser",
          not any(line.startswith("Here you go") for line in received))
    check("the prose reached the pill as a subtitle", 's "Here you go:"' in received, f"got {received}")
    check("the subtitle lands before done",
          's "Here you go:"' in received and "p done" in received
          and received.index('s "Here you go:"') < received.index("p done"), f"got {received}")
    check("it left the glass", received[-1] == "p dormant", f"got {received[-1:]}")


def run_against(model: str, say: list, until, timeout: float = 40.0, name: str = "fake-model"):
    """Stand up a fake display, run the real script against `model` as its
    model command, and return (received, sent): (seconds after connecting,
    line) pairs, until `until(lines)` holds or `timeout` passes.

    Each `say` entry is (when, line): `when` is seconds after connecting, or
    a callable that says when the moment has come.
    """
    directory = tempfile.mkdtemp()
    path = os.path.join(directory, "hud.sock")
    fake = os.path.join(directory, name)
    Path(fake).write_text(model, encoding="utf-8")
    os.chmod(fake, 0o755)

    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(path)
    server.listen(1)

    received: list[tuple[float, str]] = []
    sent: list[tuple[float, str]] = []
    ready = threading.Event()

    def serve() -> None:
        conn, _ = server.accept()
        ready.set()
        started = time.monotonic()
        conn.settimeout(0.1)
        pending = list(say)
        buffer = b""
        while not until([line for _, line in received]):
            now = time.monotonic() - started
            if now > timeout:
                break
            for entry in list(pending):
                when, line = entry
                if when() if callable(when) else when <= now:
                    conn.sendall((line + "\n").encode())
                    sent.append((time.monotonic() - started, line))
                    pending.remove(entry)
            try:
                chunk = conn.recv(4096)
            except socket.timeout:
                continue
            if not chunk:
                break
            buffer += chunk
            while b"\n" in buffer:
                line, buffer = buffer.split(b"\n", 1)
                received.append((time.monotonic() - started, line.decode()))
        conn.close()

    thread = threading.Thread(target=serve, daemon=True)
    thread.start()
    env = dict(os.environ, BOB_HUD_SOCKET=path, HUD_NAMES="off")
    process = subprocess.Popen(
        [sys.executable, str(BIN), "--model-cmd", fake],
        env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    ready.wait(10)
    thread.join(timeout + 5)
    process.terminate()
    process.wait(timeout=10)
    server.close()
    return received, sent


# A model that draws one panel named after what was said, two seconds later.
# The prompt's first line is `The user said this out loud, to their screen:
# 'first'`, and sed pulls the word out of the quotes.
SLOW_ECHO = (
    "#!/bin/sh\n"
    # "said this out loud, to their screen" or "typed this ... on their screen".
    "said=$(sed -n \"s/.*their screen: '\\([^']*\\)'.*/\\1/p\" | head -1)\n"
    "sleep 2\n"
    "echo \"@ $said at=topRight\"\n"
)


def test_interrupt_end_to_end() -> None:
    """Spoken while busy: the run in flight is cut off without a word and the
    new words run instead. "It keeps talking over me" (2026-09-20)."""
    received, _ = run_against(
        SLOW_ECHO,
        [(0.0, 'h "first"'), (0.2, "k down"), (0.6, "k up"), (0.7, 'h "second"')],
        lambda lines: "p dormant" in lines,
    )
    lines = [line for _, line in received]
    check("the first run never finished", "@ first at=topRight" not in lines, f"got {lines}")
    check("the second ran", "@ second at=topRight" in lines, f"got {lines}")
    check("nothing was queued", "q 1" not in lines, f"got {lines}")
    check("the cut-off was not announced", not any("Stopped" in line for line in lines), f"got {lines}")
    check("it ended by leaving", lines and lines[-1] == "p dormant", f"got {lines[-1:]}")


def test_queue_end_to_end() -> None:
    """Typed while busy: queued, shown as depth, run in order, never dropped."""
    received, _ = run_against(
        SLOW_ECHO,
        [(0.0, 'h "first"'), (0.2, 'h "second" via=typed')],
        # `p dormant` is the settle after the second answer. The first answer
        # holds `done` for a second and goes straight on, without leaving in
        # between.
        lambda lines: "p dormant" in lines,
    )
    lines = [line for _, line in received]

    def index(line: str) -> int:
        return lines.index(line) if line in lines else -1

    first, second = index("@ first at=topRight"), index("@ second at=topRight")
    check("the second utterance was queued, not dropped", "q 1" in lines, f"got {lines}")
    check("the depth went up before the first panel", 0 <= index("q 1") < first, f"got {lines}")
    check("no busy panel was drawn", not any(line.startswith("@ busy") for line in lines))
    check("the first request drew first", 0 <= first < second, f"got {lines}")
    check("the depth went back to zero when the second started",
          first < index("q 0") < second, f"got {lines}")
    check("done was shown between the two", first < index("p done") < second, f"got {lines}")
    check("thinking was shown again for the second",
          "p thinking" in lines[first:second], f"got {lines[first:second]}")
    check("it ended by leaving", lines and lines[-1] == "p dormant", f"got {lines[-1:]}")


# A stand-in for Claude Code over `--input-format stream-json`: one process,
# one user message per turn on stdin, an init, a text and a result per turn.
# It counts its launches so the test can see there was one.
FAKE_CLAUDE = """#!/usr/bin/env python3
import json, re, sys
with open("LAUNCHES", "a") as f:
    f.write("launch\\n")
print(json.dumps({"type": "system", "subtype": "init"}), flush=True)
for line in sys.stdin:
    text = json.loads(line)["message"]["content"][0]["text"]
    m = re.search(r"to their screen: '([^']*)'", text)
    reply = "Here is " + m.group(1) if m else "ready"
    print(json.dumps({"type": "assistant", "message": {"content": [{"type": "text", "text": reply}]}}), flush=True)
    print(json.dumps({"type": "result", "subtype": "success", "result": reply}), flush=True)
"""


def test_one_model_process() -> None:
    """Two spoken requests, and the warm-up before them, are three turns of
    one Claude process, not three processes."""
    launches = os.path.join(tempfile.mkdtemp(), "launches")
    received, _ = run_against(
        FAKE_CLAUDE.replace("LAUNCHES", launches),
        [(0.0, 'h "first"'), (3.0, 'h "second"')],
        lambda lines: 's "Here is second"' in lines and "p dormant" in lines,
        name="claude",
    )
    lines = [line for _, line in received]
    check("both requests were answered by the model",
          's "Here is first"' in lines and 's "Here is second"' in lines, f"got {lines}")
    check("and written for the panel, closed",
          'w "Here is first" done=true' in lines and 'w "Here is second" done=true' in lines, f"got {lines}")
    count = len(Path(launches).read_text().splitlines()) if os.path.exists(launches) else 0
    check("and it was one process for the warm-up and both", count == 1, f"launched {count} times")
    check("every turn went through thinking", lines.count("p thinking") >= 2, f"got {lines}")


def test_stop_end_to_end() -> None:
    """A spoken stop ends the run, keeps the ring off red, and frees the loop."""
    pidfile = os.path.join(tempfile.mkdtemp(), "pid")
    # `exec` so the pid the bridge signals is the sleep itself; a shell that
    # dies on SIGTERM leaves its foreground child alive and holding stdout.
    model = f"#!/bin/sh\ncat > /dev/null\necho $$ > {pidfile}\nexec sleep 30\n"
    received, sent = run_against(
        model,
        [(0.0, 'h "wait"'), (lambda: os.path.exists(pidfile), 'h "stop"')],
        lambda lines: "p dormant" in lines,
        timeout=20.0,
    )
    lines = [line for _, line in received]
    stopped_at = next((at for at, line in sent if line == 'h "stop"'), None)
    left = [at for at, line in received if line == "p dormant"]
    check("the stop word reached the run", stopped_at is not None)
    check("the stop was not a failure on the ring", "p failed" not in lines, f"got {lines}")
    check("the pill was told in the X's own words", 's "Stopped. What was drawn stays."' in lines, f"got {lines}")
    check("it left within 5 s of the stop",
          stopped_at is not None and left and left[0] - stopped_at <= 5.0,
          f"stop at {stopped_at}, left at {left}")
    check("the stop was never queued as a request", "q 1" not in lines)
    alive = True
    try:
        pid = int(Path(pidfile).read_text().strip())
        os.kill(pid, 0)
    except (OSError, ValueError):
        alive = False
    check("the model process is gone", not alive)


def test_reconnects() -> None:
    """The display restarting must not kill the loop.

    The display gets rebuilt and relaunched constantly. A loop that exits when
    its socket closes leaves the person talking to nothing, and the only symptom
    is that nothing happens.
    """
    directory = tempfile.mkdtemp()
    path = os.path.join(directory, "hud.sock")

    fake = os.path.join(directory, "fake-model")
    with open(fake, "w", encoding="utf-8") as handle:
        handle.write("#!/bin/sh\ncat > /dev/null\necho 'r s'\n")
    os.chmod(fake, 0o755)

    env = dict(os.environ, BOB_HUD_SOCKET=path, HUD_NAMES="off")
    process = subprocess.Popen(
        [sys.executable, str(BIN), "--model-cmd", fake],
        env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )

    def accept_once(timeout: float) -> bool:
        """Stand up the socket, take one connection, then tear it down."""
        server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        server.settimeout(timeout)
        server.bind(path)
        server.listen(1)
        try:
            conn, _ = server.accept()
        except socket.timeout:
            return False
        finally:
            server.close()
            try:
                os.unlink(path)
            except OSError:
                pass
        conn.close()
        return True

    try:
        # It should be waiting for a display that does not exist yet.
        first = accept_once(15)
        check("it waits for a display that is not up yet", first)
        # Now the display goes away and comes back.
        second = accept_once(15)
        check("it reconnects after the display restarts", second)
        check("the process is still alive", process.poll() is None)
    finally:
        process.terminate()
        process.wait(timeout=10)


def main() -> int:
    module = load()
    print("draw_lines")
    test_draw_lines(module)
    print("subtitle")
    test_subtitle(module)
    print("breadcrumb")
    test_breadcrumb(module)
    print("the recorded stream")
    test_translate_recorded_stream(module)
    print("stop")
    test_stop(module)
    print("stop words")
    test_stop_words(module)
    print("what reached the glass")
    test_drawn(module)
    print("the prompt after a stop")
    test_prompt_prefix(module)
    print("session continuity")
    test_session_flags(module)
    print("names for the recogniser")
    test_pick_names(module)
    print("the turn line")
    test_turn_line(module)
    print("the talk key")
    test_talk_key(module)
    print("the silence filler")
    test_pick_filler(module)
    print("the hyper bar")
    test_hyper_bar(module)
    print("the long-answer switch")
    test_long_answer_switch(module)
    print("read aloud skips the pointer")
    test_read_aloud_skips_the_pointer(module)
    print("a click on a guide")
    test_guide_hit(module)
    print("music without the model")
    test_music_fast_path(module)
    print("the superassistant log")
    test_remember(module)
    print("the lean profile")
    test_agent_flags(module)
    test_lean_prompt(module)
    print("pointing")
    test_pointing(module)
    print("end to end")
    test_end_to_end()
    print("queue end to end")
    test_queue_end_to_end()
    print("interrupt end to end")
    test_interrupt_end_to_end()
    print("stop end to end")
    test_stop_end_to_end()
    print("reconnecting")
    test_reconnects()
    print()
    if failures:
        print(f"{len(failures)} failed: {', '.join(failures)}")
        return 1
    print("all passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())

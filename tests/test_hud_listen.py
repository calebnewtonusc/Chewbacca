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
    spec = importlib.util.spec_from_file_location(
        "hud_listen", BIN, loader=SourceFileLoader("hud_listen", str(BIN))
    )
    module = importlib.util.module_from_spec(spec)
    sys.modules["hud_listen"] = module
    spec.loader.exec_module(module)
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
    recorded = "Building ship-ready work today.\n\nIt's Saturday, September 19, 2026."
    check(
        "the session opener is dropped",
        m.subtitle(recorded) == "It's Saturday, September 19, 2026.",
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

    first_crumb = index('s "Display current date and time"')
    acting = index("p acting")
    second_crumb = index('s "Display OS type"')
    reply = index('s "It\'s Saturday, September 19, 2026."')
    check("the first tool call is its description", first_crumb >= 0, f"got {lines}")
    check("acting follows the first breadcrumb", 0 <= first_crumb < acting, f"got {lines}")
    check("the second tool call follows", acting < second_crumb, f"got {lines}")
    check("the final text block is the reply, opener dropped", second_crumb < reply, f"got {lines}")
    check("thinking is pulsed before any tool runs",
          "p thinking" in lines[:first_crumb], f"got {lines[:first_crumb]}")
    check("nothing after the reply", lines[-1] == 's "It\'s Saturday, September 19, 2026."', f"got {lines[-1:]}")
    check("no line is bare words",
          all(line.startswith(("p ", 's "')) for line in lines), f"got {lines}")
    check("the result is kept", run.ok and run.text.endswith("September 19, 2026."), f"got {run.text!r}")
    check("subtitle(run.text) drops the opener",
          m.subtitle(run.text) == "It's Saturday, September 19, 2026.", f"got {m.subtitle(run.text)!r}")
    check("the last phrase said is remembered", run.said == "It's Saturday, September 19, 2026.")

    # The throttle, the dedupe, and the subagent filter, each in one event.
    run = m.Run()
    tokens = {"type": "system", "subtype": "thinking_tokens"}
    burst = run.translate(tokens, now=10.0) + run.translate(tokens, now=11.0) + run.translate(tokens, now=12.5)
    check("two thinking_tokens inside PULSE_EVERY pulse once", burst == ["p thinking", "p thinking"], f"got {burst}")
    call = {"type": "assistant", "message": {"content": [{"type": "tool_use", "name": "Bash", "input": {"command": "mac calendar list", "description": "List today's events"}}]}}
    twice = run.translate(call, now=20.0) + run.translate(call, now=23.0)
    check("the same phrase twice is said once, pulsed twice",
          twice == ['s "List today\'s events"', "p acting", "p acting"], f"got {twice}")
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
    listener.ask = asked.append
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
    speaker.stdin.broken = True
    listener.speak("Again.")
    check("a dead speaker means say, not silence",
          listener.speaker is None and listener.voice == m.FALLBACK_VOICE)
    check("hud-speak is a Kokoro name, say is a Mac name",
          m.KOKORO_VOICE.fullmatch("af_heart") and m.KOKORO_VOICE.fullmatch("am_michael")
          and not m.KOKORO_VOICE.fullmatch("Samantha"))


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
    plain = listener.prompt_for(req, "")
    check("the pill is the whole answer", "it is the whole answer" in plain and "Do not draw anything" in plain)
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


def test_pointing(m) -> None:
    listener = m.Listener("claude -p", False, False)
    check("no region to start", listener.pointing() is None)
    listener.handle("g 100 200 320 90")
    check("a region is remembered", listener.pointing() == (100, 200, 320, 90))
    listener.region_at -= listener.POINT_TTL + 1
    check("a stale region is forgotten", listener.pointing() is None)
    listener.handle("g not numbers here")
    check("a malformed region is ignored", listener.pointing() is None)


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
            # Until the second `p attentive`: the first is the greeting, the
            # second is the settle after the answer. Counting lines instead
            # stopped early whenever the draw lines and `p done` arrived in
            # one chunk, which they do, and the test failed on its last check.
            while received.count("p attentive") < 2:
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

    env = dict(os.environ, BOB_HUD_SOCKET=path)
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
    check("it went back to attentive", received[-1] == "p attentive", f"got {received[-1:]}")


def run_against(model: str, say: list, until, timeout: float = 40.0):
    """Stand up a fake display, run the real script against `model` as its
    model command, and return (received, sent): (seconds after connecting,
    line) pairs, until `until(lines)` holds or `timeout` passes.

    Each `say` entry is (when, line): `when` is seconds after connecting, or
    a callable that says when the moment has come.
    """
    directory = tempfile.mkdtemp()
    path = os.path.join(directory, "hud.sock")
    fake = os.path.join(directory, "fake-model")
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
    env = dict(os.environ, BOB_HUD_SOCKET=path)
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
    "said=$(sed -n \"s/.*to their screen: '\\([^']*\\)'.*/\\1/p\" | head -1)\n"
    "sleep 2\n"
    "echo \"@ $said at=topRight\"\n"
)


def test_queue_end_to_end() -> None:
    """Spoken while busy: queued, shown as depth, run in order, never dropped."""
    received, _ = run_against(
        SLOW_ECHO,
        [(0.0, 'h "first"'), (0.2, 'h "second"')],
        # The greeting is the first `p attentive`; the settle after the second
        # answer is the second. The first answer holds `done` for a second and
        # goes straight on, without an attentive in between.
        lambda lines: lines.count("p attentive") >= 2,
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
    check("it ended attentive", lines and lines[-1] == "p attentive", f"got {lines[-1:]}")


def test_stop_end_to_end() -> None:
    """A spoken stop ends the run, keeps the ring off red, and frees the loop."""
    pidfile = os.path.join(tempfile.mkdtemp(), "pid")
    # `exec` so the pid the bridge signals is the sleep itself; a shell that
    # dies on SIGTERM leaves its foreground child alive and holding stdout.
    model = f"#!/bin/sh\ncat > /dev/null\necho $$ > {pidfile}\nexec sleep 30\n"
    received, sent = run_against(
        model,
        [(0.0, 'h "wait"'), (lambda: os.path.exists(pidfile), 'h "stop"')],
        lambda lines: lines.count("p attentive") >= 2,
        timeout=20.0,
    )
    lines = [line for _, line in received]
    stopped_at = next((at for at, line in sent if line == 'h "stop"'), None)
    attentive = [at for at, line in received if line == "p attentive"]
    check("the stop word reached the run", stopped_at is not None)
    check("the stop was not a failure on the ring", "p failed" not in lines, f"got {lines}")
    check("the pill was told in the X's own words", 's "Stopped. What was drawn stays."' in lines, f"got {lines}")
    check("attentive again within 5 s of the stop",
          stopped_at is not None and len(attentive) >= 2 and attentive[1] - stopped_at <= 5.0,
          f"stop at {stopped_at}, attentive at {attentive}")
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

    env = dict(os.environ, BOB_HUD_SOCKET=path)
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
    print("pointing")
    test_pointing(module)
    print("end to end")
    test_end_to_end()
    print("queue end to end")
    test_queue_end_to_end()
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

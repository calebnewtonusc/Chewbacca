"""The loop, tested without a display, a microphone, or a model.

`hud listen` sits between the display and a model and had never been exercised
end to end: everything about it was verified by reading it. This stands up a
Unix socket that pretends to be the display, points the listener at it with a
fake model command, and checks what comes back.

Run: python3 tests/test_hud_listen.py
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

BIN = Path(__file__).resolve().parent.parent / "bin" / "hud-listen"

failures: list[str] = []


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
        m.draw_lines("hello there\nq nope") == [],
    )


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
            while len(received) < 5:
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
          not any("Here you go" in line for line in received))
    check("it went back to attentive", received[-1] == "p attentive", f"got {received[-1:]}")


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
    print("session continuity")
    test_session_flags(module)
    print("pointing")
    test_pointing(module)
    print("end to end")
    test_end_to_end()
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

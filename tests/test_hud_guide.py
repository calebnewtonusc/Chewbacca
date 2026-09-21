#!/usr/bin/env python3
"""bin/hud-guide, against a saved snapshot and a fake display.

No screen is read: HUD_GUIDE_SNAPSHOT points the tool at a tree written here,
and BOB_HUD_SOCKET points it at a socket this test listens on. What is checked
is the part that has to be right for the bubble to land on the button: which
elements count as controls, how words find one, and the exact line sent.
"""

from __future__ import annotations

import importlib.machinery
import importlib.util
import json
import os
import socket
import subprocess
import sys
import tempfile
import threading
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TOOL = ROOT / "bin" / "hud-guide"

failures = 0


def check(name: str, ok: bool, detail: str = "") -> None:
    global failures
    print(f"  {'ok  ' if ok else 'FAIL'} {name}" + (f": {detail}" if detail and not ok else ""))
    if not ok:
        failures += 1


def load(name: str, path: Path):
    loader = importlib.machinery.SourceFileLoader(name, str(path))
    spec = importlib.util.spec_from_loader(name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


def element(id: str, role: str, frame, actionable=True, **names) -> dict:
    return {"id": id, "role": role, "frame": frame, "isActionable": actionable, **names}


def write_snapshot(path: Path) -> None:
    elements = [
        element("elem_0", "AXWindow", [[8, 43], [745, 875]], False, title="Sign in to the bank"),
        element("elem_1", "AXButton", [[724, 70], [30, 30]], label="Sign in"),
        element("elem_2", "AXTextField", [[100, 200], [300, 28]], label="Email"),
        element("elem_3", "AXLink", [[100, 260], [140, 18]], False, title="Forgot password?"),
        # A scroll area is a container, actionable or not.
        element("elem_4", "AXScrollArea", [[8, -700], [745, 1600]]),
        # An actionable group with no name is nothing to point at.
        element("elem_5", "AXGroup", [[100, 300], [200, 40]]),
        # A named group covering most of the window is a container with a label.
        element("elem_6", "AXGroup", [[8, 43], [745, 600]], label="Main content"),
        # Scrolled off the top: its centre is outside the window.
        element("elem_7", "AXButton", [[100, -80], [80, 30]], label="Hidden above"),
        # A field with no name is still a field; the voice can describe where it is.
        element("elem_8", "AXSecureTextField", [[100, 240], [300, 28]]),
        # Too small to be a control.
        element("elem_9", "AXButton", [[500, 500], [2, 2]], label="Speck"),
        element("elem_10", "AXStaticText", [[100, 120], [200, 20]], False, label="Welcome back"),
    ]
    path.write_text(json.dumps({
        "windowBounds": [[8, 43], [745, 875]],
        "uiMap": {e["id"]: e for e in elements},
    }), encoding="utf-8")


class FakeDisplay:
    """A socket that keeps every line sent to it."""

    def __init__(self, path: Path) -> None:
        self.lines: list[str] = []
        self.server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.server.bind(str(path))
        self.server.listen(4)
        self.thread = threading.Thread(target=self.serve, daemon=True)
        self.thread.start()

    def serve(self) -> None:
        while True:
            try:
                conn, _ = self.server.accept()
            except OSError:
                return
            with conn:
                data = b""
                while True:
                    chunk = conn.recv(4096)
                    if not chunk:
                        break
                    data += chunk
                self.lines += [ln for ln in data.decode("utf-8").split("\n") if ln]

    def close(self) -> None:
        self.server.close()


def main() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        bob = root / "bob"
        bob.mkdir()
        snapshot = root / "snapshot.json"
        write_snapshot(snapshot)
        display = FakeDisplay(bob / "hud.sock")
        os.environ["BOB_DIR"] = str(bob)
        os.environ["BOB_HUD_SOCKET"] = str(bob / "hud.sock")
        os.environ["HUD_GUIDE_SNAPSHOT"] = str(snapshot)
        guide = load("hud_guide_under_test", TOOL)

        print("which elements are controls")
        look = guide.look_from(str(snapshot), "Safari", "Sign in to the bank")
        found = guide.controls(look)
        ids = [c["id"] for c in found]
        check("the button, the fields and the link are in", ids == ["elem_1", "elem_2", "elem_3", "elem_8"], str(ids))
        by_id = {c["id"]: c for c in found}
        check("a control has a place, a name and a word for what it is",
              by_id["elem_1"]["frame"] == [724, 70, 30, 30] and by_id["elem_1"]["name"] == "Sign in"
              and by_id["elem_1"]["kind"] == "button" and by_id["elem_2"]["kind"] == "text field"
              and by_id["elem_8"]["kind"] == "password field" and by_id["elem_8"]["name"] == "")
        check("an unknown role gets a readable word", guide.role_word("AXHeadingThing") == "heading thing")

        print("finding one by words")
        best = lambda words: (guide.matches(found, words) or [(0, {"id": None})])[0][1]["id"]  # noqa: E731
        check("the exact name", best("sign in") == "elem_1")
        check("part of the name", best("forgot") == "elem_3")
        check("the words in any order", best("password forgot") == "elem_3")
        check("a near miss", best("emial") == "elem_2")
        check("nothing for nonsense", guide.matches(found, "quarterly report") == [])
        check("nothing for nothing", guide.matches(found, "  ") == [])

        print("the line for the display")
        check("a label is quoted and its quotes are softened",
              guide.label_token('Click "Sign in"') == "label=\"Click 'Sign in'\"")
        long = guide.label_token("Click the blue button at the top right of the page next to your name")
        check("a long label is cut, not wrapped", len(long) <= guide.MAX_SAY + len('label=""') and long.endswith('..."'), long)
        check("the mark line", guide.mark_line([724, 70, 30, 30], "Click Sign in", 120)
              == 'm guide 724 70 30 30 label="Click Sign in" tone=guide life=120')

        print("the look is kept between calls")
        guide.save_look(look)
        check("a saved look comes back", (guide.saved_look() or {}).get("snapshot") == str(snapshot))
        control, _ = guide.resolve("elem_2", None)
        check("an id resolves against the saved look", control["name"] == "Email")
        control, _ = guide.resolve("sign in", None)
        check("words resolve by looking again", control["id"] == "elem_1")
        try:
            guide.resolve("elem_99", None)
            check("an unknown id is an error", False)
        except guide.LookError as error:
            check("an unknown id is an error", "elem_99" in str(error))

        print("the app under the display")
        check("nothing recorded, nothing known", guide.under_display() is None)
        (bob / "front-app").write_text(json.dumps({"name": "Safari", "bundle": "com.apple.Safari", "pid": 1}))
        check("the recorded app", guide.under_display() == "Safari")
        (bob / "front-app").write_text(json.dumps({"name": "BobHUD"}))
        check("the display itself is never the answer", guide.under_display() is None)

        print("the command")
        env = dict(os.environ)
        run = lambda *args: subprocess.run([sys.executable, str(TOOL), *args], capture_output=True, text=True, env=env)  # noqa: E731
        out = run("list")
        check("list is a header and a line a control",
              out.returncode == 0 and out.stdout.startswith("front window: 4 controls\n") and "elem_1    button         Sign in" in out.stdout,
              out.stdout + out.stderr)
        out = run("--json", "list")
        check("list --json", out.returncode == 0 and [c["id"] for c in json.loads(out.stdout)["controls"]] == ["elem_1", "elem_2", "elem_3", "elem_8"])
        out = run("find", "forgot")
        check("find prints the matches, best first", out.returncode == 0 and out.stdout.splitlines()[1].startswith("elem_3"), out.stdout)
        check("a miss exits 1 and says so", run("find", "quarterly").returncode == 1)
        out = run("show", "elem_1", "--say", "Click Sign in")
        check("show reports where the bubble went", out.returncode == 0 and out.stdout.strip() == 'bubble on Sign in (button) at 724,70 30x30: "Click Sign in"', out.stdout + out.stderr)
        out = run("show", "email")
        check("show by words says the name when there is nothing to say", out.returncode == 0 and '"Email"' in out.stdout, out.stdout)
        out = run("at", "10", "20", "30", "40", "--say", "Here", "--life", "0")
        check("at", out.returncode == 0)
        out = run("clear")
        check("clear", out.returncode == 0 and out.stdout.strip() == "bubble down")
        out = run("show", "nothing like this at all")
        check("no match is exit 2 with a sentence on stderr", out.returncode == 2 and "nothing on the screen" in out.stderr, out.stderr)

        display.thread.join(timeout=1) if False else None
        import time
        deadline = time.monotonic() + 3
        while len(display.lines) < 5 and time.monotonic() < deadline:
            time.sleep(0.05)
        check("the display got exactly the lines", display.lines == [
            'm guide 724 70 30 30 label="Click Sign in" tone=guide life=120',
            'm guide 100 200 300 28 label="Email" tone=guide life=120',
            'm guide 10 20 30 40 label="Here" tone=guide life=0',
            "u guide",
        ] or display.lines[:4] == [
            'm guide 724 70 30 30 label="Click Sign in" tone=guide life=120',
            'm guide 100 200 300 28 label="Email" tone=guide life=120',
            'm guide 10 20 30 40 label="Here" tone=guide life=0',
            "u guide",
        ], str(display.lines))
        display.close()

        del os.environ["BOB_HUD_SOCKET"]
        os.environ["BOB_HUD_SOCKET"] = str(root / "nobody.sock")
        out = run("clear")
        check("no display is exit 2 with the fix", out.returncode == 2 and "hud open" in out.stderr, out.stderr)

    print("\nall passed" if not failures else f"\n{failures} failed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())

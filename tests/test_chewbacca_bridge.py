"""chewbacca-bridge runs only its fixed tools, refuses the rest, and round-trips a job. Offline."""
import importlib.machinery
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / "bin/chewbacca-bridge"


def load(tmp):
    os.environ["CHEWBACCA_BRIDGE_DIR"] = tmp
    loader = importlib.machinery.SourceFileLoader("bridge_mod", str(TOOL))
    spec = importlib.util.spec_from_loader("bridge_mod", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    mod.LOG = Path(tmp) / "bridge.log"
    return mod


class BridgeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.b = load(self.tmp)

    def test_allow_commit_is_refused(self):
        with self.assertRaises(self.b.Refused):
            self.b.jev_browse(["run", "--url", "https://x.com", "--goal", "g", "--allow-commit"])

    def test_non_https_refused(self):
        with self.assertRaises(self.b.Refused):
            self.b.jev_browse(["run", "--url", "file:///etc/passwd", "--goal", "g"])

    def test_unknown_flag_refused(self):
        with self.assertRaises(self.b.Refused):
            self.b.jev_browse(["run", "--url", "https://x.com", "--goal", "g", "--exec", "rm"])

    def test_valid_run_builds_json_argv(self):
        argv, _ = self.b.jev_browse(["run", "--url", "https://x.com/a", "--goal", "open it"])
        self.assertIn("--json", argv)
        self.assertEqual(argv[argv.index("--url") + 1], "https://x.com/a")

    def test_fixed_tools_take_no_args(self):
        with self.assertRaises(self.b.Refused):
            self.b.TOOLS["ping"](["; rm -rf ~"])

    def test_unknown_tool_and_round_trip(self):
        self.b.ensure_dirs()
        stop = threading.Event()

        def loop():
            while not stop.is_set():
                for p in sorted(self.b.INBOX.glob("*.json")):
                    self.b.run_job(p)
                time.sleep(0.05)

        t = threading.Thread(target=loop, daemon=True)
        t.start()
        try:
            self.assertEqual(self.b.call("ping", [], timeout=5), 0)
            self.assertEqual(self.b.call("bash", ["-c", "id"], timeout=5), 126)
        finally:
            stop.set()
        self.assertIn("refused", self.b.LOG.read_text())

    def test_page_read_is_https_only(self):
        with self.assertRaises(self.b.Refused):
            self.b.page_read(["javascript:alert(1)"])
        argv, _ = self.b.page_read(["https://app.clay.com/x", "4"])
        self.assertEqual(argv[-2:], ["https://app.clay.com/x", "4.0"])

    def test_git_is_read_and_fetch(self):
        with self.assertRaises(self.b.Refused):
            self.b.REGISTRY["git"](["-C", "/tmp", "push"])
        with self.assertRaises(self.b.Refused):
            self.b.REGISTRY["git"](["-C", "/tmp", "-c", "x=y", "status"])
        self.b.REGISTRY["git"](["-C", "/tmp", "status"])

    def test_no_shell_agents(self):
        with self.assertRaises(self.b.Refused):
            self.b.REGISTRY["claude-tab"](["send", "rm -rf ~"])
        self.assertNotIn("op", self.b.TOOLS)
        self.assertNotIn("gemini", self.b.TOOLS)

    def test_sends_are_out(self):
        with self.assertRaises(self.b.Refused):
            self.b.REGISTRY["imsg"](["send", "--to", "+15555550123", "--text", "hi"])
        with self.assertRaises(self.b.Refused):
            self.b.REGISTRY["himalaya"](["message", "send"])
        argv, _ = self.b.REGISTRY["gog"](["gmail", "search", "from:jonah"])
        self.assertIn("--gmail-no-send", argv)
        self.assertNotIn("write-file", self.b.TOOLS)

    def test_tools_listing(self):
        out = subprocess.run([sys.executable, str(TOOL), "tools"], capture_output=True, text=True).stdout
        self.assertIn("jev-browse", out)
        self.assertNotIn("bash", out.split())


if __name__ == "__main__":
    unittest.main()

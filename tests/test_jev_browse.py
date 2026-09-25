"""jev-browse's floor and result shape, against a fake jev_ultrafast. Offline."""
import json
import os
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUNNER = ROOT / "bin/lib/jev_browse_runner.py"
sys.path.insert(0, str(ROOT / "bin/lib"))
import jev_browse_runner as runner  # noqa: E402

FAKE = textwrap.dedent('''
    class Browser:
        def act(self, action, page, text=None):
            return {"ok": True}

    class Agent:
        def __init__(self, url, goals):
            self.b = Browser()
            self.state = {"page": {"url": url, "title": "t"}, "history": [], "decisions": []}
        def run(self):
            import os, json
            for action in json.loads(os.environ["FAKE_ACTIONS"]):
                self.state["decisions"].append({})
                self.b.act(action, self.state["page"])
                self.state["history"].append({"action": action["label"], "kind": action["kind"]})
                self.state["status"] = "running"
                self.state["elapsed_ms"] = 5
                yield self.state
            self.state["status"] = "done"
            yield self.state
        def close(self):
            pass
''')


class FloorTests(unittest.TestCase):
    def test_commit_words_are_caught(self):
        for label in ("Send", "Submit application", "Delete row", "Run column", "Enrich", "Sign in",
                      "Place order", "Book now", "Share"):
            self.assertTrue(runner.committing({"kind": "click", "label": label}), label)

    def test_ordinary_controls_pass(self):
        for label in ("Filter", "Sort by funding date", "Series A founders", "Next page", "Search people",
                      "Posts", "Facebook"):
            self.assertFalse(runner.committing({"kind": "click", "label": label}), label)

    def test_typing_is_never_a_commit(self):
        self.assertFalse(runner.committing({"kind": "type", "label": "Send a message"}))


class RunnerTests(unittest.TestCase):
    def run_fake(self, actions, allow=False):
        with tempfile.TemporaryDirectory() as tmp:
            pkg = Path(tmp) / "jev_ultrafast"
            pkg.mkdir()
            (pkg / "__init__.py").write_text("from .browser import Agent\n")
            (pkg / "browser.py").write_text(FAKE)
            env = {**os.environ, "PYTHONPATH": tmp, "FAKE_ACTIONS": json.dumps(actions)}
            req = json.dumps({"url": "https://example.com", "goals": ["g"], "allow_commit": allow})
            proc = subprocess.run([sys.executable, str(RUNNER)], input=req, capture_output=True, text=True, env=env)
            return json.loads(proc.stdout.strip().splitlines()[-1])

    def test_stops_at_send(self):
        r = self.run_fake([{"kind": "click", "label": "Filter"}, {"kind": "click", "label": "Send"}])
        self.assertEqual(r["status"], "yours_to_press")
        self.assertEqual(r["control"], "Send")
        self.assertEqual([a["action"] for a in r["actions"]], ["Filter"])

    def test_allow_commit_lifts_floor(self):
        r = self.run_fake([{"kind": "click", "label": "Send"}], allow=True)
        self.assertEqual(r["status"], "done")

    def test_done_carries_verify_note(self):
        r = self.run_fake([{"kind": "click", "label": "Filter"}])
        self.assertEqual(r["status"], "done")
        self.assertIn("verify", r)


class LauncherTests(unittest.TestCase):
    def test_help_and_bad_url(self):
        tool = str(ROOT / "bin/jev-browse")
        self.assertEqual(subprocess.run([tool, "--help"], capture_output=True).returncode, 0)
        bad = subprocess.run([tool, "run", "--url", "ftp://x", "--goal", "g"], capture_output=True, text=True)
        self.assertNotEqual(bad.returncode, 0)
        self.assertIn("https", bad.stderr)


if __name__ == "__main__":
    unittest.main()

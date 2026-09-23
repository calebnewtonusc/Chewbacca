"""Local durable scheduling tests. No workers or external services are spawned."""
import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("task_graph", ROOT / "tools/task_graph.py")
graph = importlib.util.module_from_spec(spec)
spec.loader.exec_module(graph)


class TaskGraphTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.folder = Path(self.temp.name).resolve()
        self.state = self.folder / "state.json"
        self.plan = {"schema_version": 1, "max_active": 3, "coordinator_slots": 1,
                     "nodes": [self.node(f"job{i}") for i in range(12)]}

    def node(self, identity, **updates):
        node = {"id": identity, "kind": "implementation", "owner": f"worker-{identity}",
                "depends_on": [], "max_attempts": 2, "expected_artifact": str(self.folder / (identity + ".txt")),
                "resources": [], "verifies": []}
        node.update(updates)
        return node

    def init(self):
        return graph.operate("init", self.state, self.plan)

    def claim(self, identity, worker=None):
        return graph.operate("claim", self.state, node=identity, worker=worker or f"worker-{identity}")["jobs"][identity]["attempt_id"]

    def finish(self, identity, token, outcome="succeeded", reason=""):
        return graph.operate("finish", self.state, node=identity, worker=f"worker-{identity}", attempt_id=token, outcome=outcome, reason=reason)

    def test_twelve_queued_jobs_obey_coordinator_cap(self):
        result = self.init()
        self.assertEqual(sum(node["ready"] for node in result["nodes"]), 12)
        self.claim("job0")
        self.claim("job1")
        with self.assertRaisesRegex(ValueError, "global_slots"):
            self.claim("job2")
        state = graph.operate("ready", self.state)
        self.assertEqual(state["active_slots"], 3)
        self.assertEqual(len(state["active_jobs"]), 2)

    def test_validation_cycles_dependencies_and_verifier_owner(self):
        for problem in ("cycle", "unknown", "same_owner", "bad_cap", "bool_attempts"):
            plan = copy.deepcopy(self.plan)
            if problem == "cycle":
                plan["nodes"][0]["depends_on"] = ["job1"]
                plan["nodes"][1]["depends_on"] = ["job0"]
            elif problem == "unknown":
                plan["nodes"][0]["depends_on"] = ["missing"]
            elif problem == "same_owner":
                plan["nodes"][1].update(kind="verification", owner="worker-job0", depends_on=["job0"], verifies=["job0"])
            elif problem == "bad_cap":
                plan["coordinator_slots"] = 3
            else:
                plan["nodes"][0]["max_attempts"] = True
            with self.subTest(problem=problem), self.assertRaises(ValueError):
                graph.validate(plan)

    def test_verified_prerequisite_artifact_and_different_worker(self):
        self.plan["nodes"].append(self.node("verify", kind="verification", depends_on=["job0"], verifies=["job0"]))
        self.init()
        with self.assertRaisesRegex(ValueError, "dependencies"):
            self.claim("verify")
        token = self.claim("job0")
        with self.assertRaises(OSError):
            self.finish("job0", token)
        (self.folder / "job0.txt").write_text("implementation receipt")
        self.finish("job0", token)
        with self.assertRaisesRegex(ValueError, "does not own"):
            self.claim("verify", worker="worker-job0")
        self.claim("verify")
        (self.folder / "job0.txt").write_text("changed after verification began")
        with self.assertRaisesRegex(ValueError, "expected bytes"):
            graph.operate("ready", self.state)

    def test_retry_limits_and_attempt_binding(self):
        self.init()
        token = self.claim("job0")
        before = self.state.read_bytes()
        with self.assertRaisesRegex(ValueError, "active attempt"):
            self.finish("job0", "wrong", "failed", "timeout")
        self.assertEqual(before, self.state.read_bytes())
        self.finish("job0", token, "failed", "worker timed out")
        retry = self.claim("job0")
        self.assertNotEqual(token, retry)
        with self.assertRaises(ValueError):
            self.finish("job0", token, "failed", "old receipt")
        self.finish("job0", retry, "failed", "second timeout")
        with self.assertRaisesRegex(ValueError, "attempt_limit"):
            self.claim("job0")

    def test_overlapping_workspace_and_file_resources(self):
        self.plan["nodes"][0]["resources"] = [{"kind": "workspace", "path": str(self.folder / "workspace")}]
        self.plan["nodes"][1]["resources"] = [{"kind": "file", "path": str(self.folder / "workspace" / "source.py")}]
        self.plan["nodes"][2]["resources"] = [{"kind": "workspace", "path": str(self.folder / "workspace" / "nested")}]
        self.init()
        token = self.claim("job0")
        for identity in ("job1", "job2"):
            with self.assertRaisesRegex(ValueError, "exclusive_resource"):
                self.claim(identity)
        self.finish("job0", token, "failed", "released after failure")
        self.claim("job1")

    def test_same_owner_cannot_run_two_jobs(self):
        self.plan["nodes"][1]["owner"] = "worker-job0"
        self.init()
        self.claim("job0")
        with self.assertRaisesRegex(ValueError, "owner_busy"):
            self.claim("job1", worker="worker-job0")

    def test_tampered_state_and_replayed_claim_refuse(self):
        self.init()
        self.claim("job0")
        state = json.loads(self.state.read_text())
        state["events"].append(copy.deepcopy(state["events"][0]))
        self.state.write_text(json.dumps(state))
        with self.assertRaisesRegex(ValueError, "duplicate"):
            graph.operate("ready", self.state)
        state["events"].pop()
        state["plan"]["max_active"] = 100
        self.state.write_text(json.dumps(state))
        with self.assertRaisesRegex(ValueError, "plan changed"):
            graph.operate("ready", self.state)

    def test_atomic_failure_preserves_prior_state(self):
        self.init()
        before = self.state.read_bytes()
        with patch.object(graph.os, "replace", side_effect=OSError("injected write failure")):
            with self.assertRaises(OSError):
                self.claim("job0")
        self.assertEqual(before, self.state.read_bytes())
        self.assertEqual(list(self.folder.glob(".task-graph-*")), [])

    def test_artifact_cannot_overwrite_scheduler_state_or_lock(self):
        for path in (str(self.state), str(self.state) + ".lock"):
            self.plan["nodes"][0]["expected_artifact"] = path
            with self.subTest(path=path), self.assertRaisesRegex(ValueError, "scheduler"):
                self.init()
            self.assertFalse(self.state.exists())

    def test_case_normalization_and_hardlink_aliases(self):
        import os
        self.plan["nodes"][0]["expected_artifact"] = str(self.folder / "Report.txt")
        self.plan["nodes"][1]["expected_artifact"] = str(self.folder / "report.txt")
        left, right = (node["expected_artifact"] for node in self.plan["nodes"][:2])
        if graph.path_key(left) == graph.path_key(right):
            with self.assertRaisesRegex(ValueError, "distinct"):
                graph.validate(self.plan)
        else:
            graph.validate(self.plan)
        self.plan["nodes"][1]["expected_artifact"] = str(self.folder / "other.txt")
        (self.folder / "Report.txt").write_text("same inode")
        os.link(self.folder / "Report.txt", self.folder / "other.txt")
        with self.assertRaisesRegex(ValueError, "distinct"):
            self.init()
        left, right = str(self.folder / "Workspace"), str(self.folder / "workspace")
        self.assertEqual(graph.conflict({"kind": "workspace", "path": left},
                                        {"kind": "file", "path": right + "/source.py"}),
                         graph.path_key(left) == graph.path_key(right))
        self.assertTrue(graph.path_alias(str(self.folder / "caf\u00e9.txt"), str(self.folder / "cafe\u0301.txt")))

    def test_case_sensitive_resource_names_remain_distinct(self):
        with patch.object(graph.os.path, "samefile", return_value=False):
            self.assertNotEqual(graph.path_key(str(self.folder / "Upper.txt")),
                                graph.path_key(str(self.folder / "upper.txt")))

    def test_fifo_is_not_an_artifact(self):
        import os
        self.init()
        token = self.claim("job0")
        os.mkfifo(self.folder / "job0.txt")
        with self.assertRaisesRegex(ValueError, "regular file"):
            self.finish("job0", token)

    def test_simultaneous_cli_claims_obey_global_limit(self):
        self.plan["max_active"] = 2
        self.init()
        base = [sys.executable, str(ROOT / "bin/task-graph"), "claim", "--state", str(self.state)]
        processes = [subprocess.Popen(base + ["--node", identity, "--worker", f"worker-{identity}"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True) for identity in ("job0", "job1")]
        outputs = [process.communicate(timeout=20) for process in processes]
        self.assertEqual(sorted(process.returncode for process in processes), [0, 2])
        for stdout, stderr in outputs:
            json.loads(stdout)
            self.assertEqual(stderr, "")
        state = graph.operate("ready", self.state)
        self.assertEqual(len(state["active_jobs"]), 1)
        self.assertEqual(state["active_slots"], 2)


if __name__ == "__main__":
    unittest.main()

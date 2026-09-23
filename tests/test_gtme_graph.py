import copy
from datetime import datetime, timezone, timedelta
import subprocess
import sys
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location("gtme_graph", Path(__file__).resolve().parents[1] / "tools/gtme_graph.py")
graph = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(graph)


class GraphTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.plan = {"workspace": "fixture", "credit_budget": 5, "nodes": [
            {"id": "identity", "kind": "identity", "requires": [], "max_credits": 0, "max_attempts": 1, "expect": {"matched": True}},
            {"id": "qualify", "kind": "qualify", "requires": ["identity"], "max_credits": 0, "max_attempts": 1, "expect": {"qualified": True}},
            {"id": "enrich", "kind": "enrich", "requires": ["qualify"], "max_credits": 3, "max_attempts": 2, "expect": {"verified_emails": 1}}]}
        self.path = self.root / "plan.json"
        self.path.write_text(json.dumps(self.plan))
        self.state = graph.fresh(self.plan, self.path)

    def proof(self, key, observations, cost=0, outcome="success"):
        artifact = self.root / f"{key}-result.json"
        artifact.write_text(json.dumps(observations))
        proof = self.root / f"{key}-evidence.json"
        proof.write_text(json.dumps({"workspace": "fixture", "node": key, "run_id": self.state["run_id"], "attempt_id": self.state["nodes"][key]["attempt_id"], "observed_at": datetime.now(timezone.utc).isoformat(), "outcome": outcome,
            "actual_credits": cost, "observations": observations,
            "artifacts": [{"path": str(artifact), "sha256": graph.digest(artifact)}]}))
        return proof

    def complete(self, key, observations, cost=0):
        graph.begin(self.plan, self.state, key)
        return graph.finish(self.plan, self.state, key, self.proof(key, observations, cost))

    def prerequisites(self):
        self.assertTrue(self.complete("identity", {"matched": True}))
        self.assertTrue(self.complete("qualify", {"qualified": True}))

    def test_paid_node_cannot_skip_identity(self):
        with self.assertRaises(ValueError): graph.begin(self.plan, self.state, "enrich")
        self.prerequisites()
        self.assertTrue(self.complete("enrich", {"verified_emails": 1}, 2))
        self.assertEqual(self.state["spent_credits"], 2)

    def test_wrong_company_and_boolean_count_refuse(self):
        self.assertFalse(self.complete("identity", {"matched": False}))
        with self.assertRaises(ValueError): graph.begin(self.plan, self.state, "qualify")
        self.state = graph.fresh(self.plan, self.path)
        self.prerequisites()
        self.assertFalse(self.complete("enrich", {"verified_emails": True}, 1))

    def test_cycle_and_missing_kind(self):
        self.plan["nodes"][0]["requires"] = ["enrich"]
        with self.assertRaises(ValueError): graph.validate(self.plan)
        self.plan["nodes"][0]["requires"] = []
        self.plan["nodes"][2]["requires"] = ["identity"]
        with self.assertRaises(ValueError): graph.validate(self.plan)

    def test_concurrent_reservations_and_retry_cost(self):
        self.prerequisites()
        second = copy.deepcopy(self.plan["nodes"][2]); second["id"] = "second"
        self.plan["nodes"].append(second)
        self.state["nodes"]["second"] = {"status": "pending", "attempts": 0, "reserved": 0}
        graph.begin(self.plan, self.state, "enrich")
        with self.assertRaises(ValueError): graph.begin(self.plan, self.state, "second")
        self.assertFalse(graph.finish(self.plan, self.state, "enrich", self.proof("enrich", {"verified_emails": 0}, 3)))
        with self.assertRaises(ValueError): graph.begin(self.plan, self.state, "enrich")

    def test_failed_attempts_are_bounded(self):
        graph.begin(self.plan, self.state, "identity")
        graph.finish(self.plan, self.state, "identity", self.proof("identity", {"matched": False}))
        with self.assertRaises(ValueError): graph.begin(self.plan, self.state, "identity")

    def test_corrupt_and_wrong_workspace_proof(self):
        graph.begin(self.plan, self.state, "identity")
        p = self.proof("identity", {"matched": True})
        data = json.loads(p.read_text()); data["workspace"] = "other"; p.write_text(json.dumps(data))
        with self.assertRaises(ValueError): graph.finish(self.plan, self.state, "identity", p)
        p = self.proof("identity", {"matched": True})
        (self.root / "identity-result.json").write_text("changed")
        with self.assertRaises(ValueError): graph.finish(self.plan, self.state, "identity", p)

    def test_verified_artifact_cannot_drift(self):
        self.complete("identity", {"matched": True})
        (self.root / "identity-result.json").write_text("changed")
        with self.assertRaises(ValueError): graph.check_evidence(self.state)

    def test_nonfinite_cost_refuses(self):
        self.plan["credit_budget"] = float("nan")
        with self.assertRaises(ValueError): graph.validate(self.plan)

    def test_overrun_is_recorded_and_blocks(self):
        self.prerequisites()
        self.assertFalse(self.complete("enrich", {"verified_emails": 1}, 6))
        self.assertEqual(self.state["spent_credits"], 6)
        with self.assertRaises(ValueError): graph.begin(self.plan, self.state, "enrich")

    def test_phase_review_must_precede_next_phase(self):
        self.plan["phases"] = ["research", "pilot"]
        for node in self.plan["nodes"]: node["phase"] = "pilot" if node["id"] == "enrich" else "research"
        self.prerequisites()
        with self.assertRaises(ValueError): graph.begin(self.plan, self.state, "enrich")
        report = {k: "Fixture evidence" for k in ("baseline", "result", "reuse_audit", "math_case", "falsifier", "cheapest_next_test", "decision_reason")}
        report.update(alternatives=["Native API", "UI", "Existing function"], novelty="adaptation", decision="continue")
        p = self.root / "review.json"; p.write_text(json.dumps(report))
        graph.review_phase(self.plan, self.state, "research", p)
        graph.begin(self.plan, self.state, "enrich")
        graph.validate_state(self.plan, self.state)

    def test_capture_overrules_conflicting_assertion(self):
        graph.begin(self.plan, self.state, "identity")
        p = self.proof("identity", {"matched": False})
        proof = json.loads(p.read_text()); proof["observations"] = {"matched": True}
        p.write_text(json.dumps(proof))
        with self.assertRaisesRegex(ValueError, "conflict"):
            graph.finish(self.plan, self.state, "identity", p)
        del proof["observations"]; p.write_text(json.dumps(proof))
        self.assertFalse(graph.finish(self.plan, self.state, "identity", p))

    def test_evidence_cannot_replay_across_runs_or_attempts(self):
        graph.begin(self.plan, self.state, "identity")
        p = self.proof("identity", {"matched": True})
        other = graph.fresh(self.plan, self.path)
        graph.begin(self.plan, other, "identity")
        with self.assertRaisesRegex(ValueError, "another run or attempt"):
            graph.finish(self.plan, other, "identity", p)
        proof = json.loads(p.read_text()); proof["run_id"] = other["run_id"]
        p.write_text(json.dumps(proof))
        with self.assertRaisesRegex(ValueError, "another run or attempt"):
            graph.finish(self.plan, other, "identity", p)

    def test_observation_time_must_be_current_attempt(self):
        graph.begin(self.plan, self.state, "identity")
        p = self.proof("identity", {"matched": True})
        proof = json.loads(p.read_text())
        for value in ("not-a-date", "2026-01-01T00:00:00", "2000-01-01T00:00:00Z",
                      (datetime.now(timezone.utc) + timedelta(days=1)).isoformat()):
            proof["observed_at"] = value; p.write_text(json.dumps(proof))
            with self.assertRaises(ValueError): graph.finish(self.plan, self.state, "identity", p)

    def test_event_ledger_reconciles_and_detects_tampering(self):
        self.prerequisites()
        graph.validate_state(self.plan, self.state)
        for field, value in (("spent_credits", -999), ("spent_credits", float("nan")), ("spent_credits", 1)):
            state = copy.deepcopy(self.state); state[field] = value
            with self.assertRaises(ValueError): graph.validate_state(self.plan, state)
        for field, value in (("reserved", -999), ("attempts", 0), ("status", "pending")):
            state = copy.deepcopy(self.state); state["nodes"]["identity"][field] = value
            with self.assertRaises(ValueError): graph.validate_state(self.plan, state)
        state = copy.deepcopy(self.state); state["events"].append(state["events"][0])
        with self.assertRaises(ValueError): graph.validate_state(self.plan, state)

    def test_failed_attempt_cost_and_retry_ledger(self):
        self.prerequisites()
        graph.begin(self.plan, self.state, "enrich")
        proof = self.proof("enrich", {"verified_emails": 0}, 1)
        self.assertFalse(graph.finish(self.plan, self.state, "enrich", proof))
        graph.validate_state(self.plan, self.state)
        graph.begin(self.plan, self.state, "enrich")
        # Preserve first attempt files while creating the second capture.
        artifact = self.root / "retry-result.json"; artifact.write_text('{"verified_emails": 1}')
        retry = self.root / "retry-proof.json"
        retry.write_text(json.dumps({"workspace": "fixture", "node": "enrich",
            "run_id": self.state["run_id"], "attempt_id": self.state["nodes"]["enrich"]["attempt_id"],
            "observed_at": datetime.now(timezone.utc).isoformat(), "actual_credits": 2, "outcome": "success",
            "artifacts": [{"path": str(artifact), "sha256": graph.digest(artifact)}]}))
        self.assertTrue(graph.finish(self.plan, self.state, "enrich", retry))
        graph.validate_state(self.plan, self.state)
        self.assertEqual(self.state["spent_credits"], 3)
        tampered = copy.deepcopy(self.state)
        tampered["events"][-1]["actual_credits"] = 0
        with self.assertRaises(ValueError): graph.validate_state(self.plan, tampered)

    def cli(self, *args):
        return subprocess.run([sys.executable, str(Path(graph.__file__)), *map(str, args)],
                              capture_output=True, text=True)

    def test_actual_cli_persists_and_refuses_tampered_state(self):
        state_path = self.root / "state.json"
        self.assertEqual(self.cli("init", self.path, "--state", state_path).returncode, 0)
        self.assertEqual(self.cli("begin", self.path, "--state", state_path, "--node", "identity").returncode, 0)
        self.state = json.loads(state_path.read_text())
        proof = self.proof("identity", {"matched": True})
        result = self.cli("finish", self.path, "--state", state_path, "--node", "identity", "--evidence", proof)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.cli("next", self.path, "--state", state_path).returncode, 0)
        state = json.loads(state_path.read_text()); state["spent_credits"] = -999
        state_path.write_text(json.dumps(state))
        result = self.cli("next", self.path, "--state", state_path)
        self.assertEqual(result.returncode, 2)
        self.assertIn("error", json.loads(result.stderr))

    def test_malformed_plan_shapes_return_structured_refusal(self):
        for value in ([], None, {"workspace": "x", "credit_budget": 1, "nodes": [None]},
                      {"workspace": "x", "credit_budget": 1, "nodes": self.plan["nodes"], "phases": [{}]}):
            self.path.write_text(json.dumps(value))
            result = self.cli("validate", self.path)
            self.assertEqual(result.returncode, 2)
            self.assertIn("error", json.loads(result.stderr))


if __name__ == "__main__": unittest.main()

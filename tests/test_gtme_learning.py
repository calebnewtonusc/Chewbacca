import copy
from fractions import Fraction
import hashlib
import importlib.util
import itertools
import json
import math
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
MODULE = importlib.util.spec_from_file_location("gtme_learning", ROOT / "tools/gtme_learning.py")
learning = importlib.util.module_from_spec(MODULE)
MODULE.loader.exec_module(learning)


def fixture():
    spec = {"experiment_id": "synthetic", "predeclared": True, "training_task_ids": ["train"],
            "holdout_task_ids": [f"h{i}" for i in range(6)], "regression_task_ids": ["r1"],
            "min_tasks": 6, "min_holdout_success_rate": .8, "alpha": .05, "cost_unit": "credits", "candidate_cost_budget": 10,
            "evaluator_id": "fixture-validator"}
    results = {"spec_sha256": "fixture-hash", "cost_unit": "credits",
               "evaluator_id": "fixture-validator", "independent_evaluator": True}
    for arm in ("baseline", "candidate"):
        results[arm] = []
        for identity in spec["holdout_task_ids"] + spec["regression_task_ids"]:
            passed = arm == "candidate" or identity == "r1"
            results[arm].append({"task_id": identity, "passed": passed, "severe_errors": [],
                                 "cost": 1, "duration_seconds": 2, "evidence": "fixture://receipt",
                                 "failure_reason": "" if passed else "wrong persisted row"})
    return spec, results


class GTMELearningTests(unittest.TestCase):
    def evaluate(self, spec, results):
        return learning.evaluate(spec, results, "fixture-hash")

    def test_promotion_and_totals(self):
        report = self.evaluate(*fixture())
        self.assertTrue(report["promotion_eligible"])
        self.assertEqual(report["holdout"], {"tasks": 6, "wins": 6, "losses": 0, "ties": 0,
                                              "one_sided_p_value": 1 / 64, "alpha": .05,
                                              "min_success_rate": .8,
                                              "baseline": {"passed": 0, "success_rate": 0},
                                              "candidate": {"passed": 6, "success_rate": 1}})
        self.assertEqual(report["candidate_totals"]["cost"], 7)
        self.assertEqual(report["candidate_totals"]["duration_seconds"], 14)
        self.assertEqual(report["regression"]["protected_passes"], 1)

    def test_relative_improvement_does_not_override_absolute_floor(self):
        spec, results = fixture()
        for index in range(6, 100):
            identity = f"h{index}"
            spec["holdout_task_ids"].append(identity)
            for arm in ("baseline", "candidate"):
                results[arm].append({"task_id": identity, "passed": False,
                                     "severe_errors": [], "cost": 0,
                                     "duration_seconds": 1, "evidence": "fixture://failed",
                                     "failure_reason": "wrong destination"})
        spec["min_tasks"] = 100
        report = self.evaluate(spec, results)
        self.assertFalse(report["promotion_eligible"])
        self.assertEqual(report["refusal_reasons"], ["candidate_holdout_success_floor"])
        self.assertTrue(report["checks"]["significant_paired_improvement"])
        self.assertEqual(report["holdout"]["candidate"], {"passed": 6, "success_rate": .06})
        self.assertEqual(report["holdout"]["baseline"], {"passed": 0, "success_rate": 0})
        self.assertEqual(report["holdout"]["one_sided_p_value"], 1 / 64)
        spec["min_holdout_success_rate"] = .06
        self.assertTrue(self.evaluate(spec, results)["promotion_eligible"])

    def test_readiness_floor_is_required_and_bounded(self):
        for invalid in (-1, 1.01, True, None, "0.8", math.nan, math.inf):
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                spec, results = fixture()
                spec["min_holdout_success_rate"] = invalid
                self.evaluate(spec, results)
        spec, results = fixture()
        del spec["min_holdout_success_rate"]
        with self.assertRaises(ValueError):
            self.evaluate(spec, results)
        for floor in (0, 1):
            spec, results = fixture()
            spec["min_holdout_success_rate"] = floor
            self.assertTrue(self.evaluate(spec, results)["promotion_eligible"])

    def test_sign_test_against_exhaustive_coin_outcomes(self):
        for count in range(8):
            outcomes = list(itertools.product((0, 1), repeat=count))
            for wins in range(count + 1):
                expected = Fraction(sum(sum(outcome) >= wins for outcome in outcomes), len(outcomes))
                self.assertEqual(learning.sign_test(wins, count - wins), expected)

    def test_ties_losses_and_reordered_rows(self):
        spec, results = fixture()
        results["candidate"][0].update(passed=False, failure_reason="timeout")
        results["baseline"][1].update(passed=True, failure_reason="")
        results["candidate"][1].update(passed=False, failure_reason="wrong row")
        results["candidate"].reverse()
        report = self.evaluate(spec, results)
        self.assertFalse(report["promotion_eligible"])
        self.assertEqual((report["holdout"]["wins"], report["holdout"]["losses"],
                          report["holdout"]["ties"]), (4, 1, 1))
        self.assertEqual(report["holdout"]["one_sided_p_value"], 6 / 32)

    def test_each_promotion_gate_refuses(self):
        mutations = {
            "minimum_holdout_tasks": lambda s, r: s.update(min_tasks=7),
            "significant_paired_improvement": lambda s, r: s.update(alpha=.001),
            "no_candidate_severe_errors": lambda s, r: r["candidate"][0].update(severe_errors=["wrong_tenant"]),
            "candidate_cost_within_budget": lambda s, r: s.update(candidate_cost_budget=6),
            "passing_regression_baseline_exists": lambda s, r: r["baseline"][-1].update(passed=False, failure_reason="bad row"),
            "regression_nonregression": lambda s, r: r["candidate"][-1].update(passed=False, failure_reason="bad row"),
        }
        for gate, mutate in mutations.items():
            with self.subTest(gate=gate):
                spec, results = fixture()
                mutate(spec, results)
                report = self.evaluate(spec, results)
                self.assertFalse(report["promotion_eligible"])
                self.assertEqual(report["refusal_reasons"], [gate])

    def test_baseline_severe_error_is_reported_without_vetoing_clean_candidate(self):
        spec, results = fixture()
        results["baseline"][0]["severe_errors"] = ["duplicate_write"]
        report = self.evaluate(spec, results)
        self.assertTrue(report["promotion_eligible"])
        self.assertEqual(report["baseline_totals"]["severe_errors"], 1)

    def test_coverage_and_ids_cannot_hide_failures(self):
        mutations = [
            lambda s, r: r["candidate"].pop(),
            lambda s, r: r["baseline"].append(copy.deepcopy(r["baseline"][0])),
            lambda s, r: r["candidate"][0].update(task_id="unplanned"),
            lambda s, r: s["holdout_task_ids"].append("h0"),
            lambda s, r: s["training_task_ids"].append("h0"),
            lambda s, r: s["regression_task_ids"].append("h0"),
            lambda s, r: s["training_task_ids"].append("r1"),
            lambda s, r: s.update(regression_task_ids=[]),
            lambda s, r: s.update(holdout_task_ids=[]),
        ]
        for index, mutate in enumerate(mutations):
            with self.subTest(index=index), self.assertRaises(ValueError):
                spec, results = fixture()
                mutate(spec, results)
                self.evaluate(spec, results)

    def test_numeric_validation_and_overflow(self):
        for field in ("cost", "duration_seconds"):
            for bad in (True, -1, math.nan, math.inf, "1", None, 10 ** 1000):
                with self.subTest(field=field, bad=str(bad)[:20]), self.assertRaises(ValueError):
                    spec, results = fixture()
                    results["candidate"][0][field] = bad
                    self.evaluate(spec, results)
        spec, results = fixture()
        for row in results["candidate"]:
            row["cost"] = 1e308
        with self.assertRaisesRegex(ValueError, "overflow"):
            self.evaluate(spec, results)
        for field, bad in (("min_tasks", True), ("min_tasks", 1.5), ("min_tasks", 0),
                           ("alpha", 0), ("alpha", 1), ("alpha", math.nan),
                           ("candidate_cost_budget", -1)):
            with self.subTest(field=field, bad=bad), self.assertRaises(ValueError):
                spec, results = fixture()
                spec[field] = bad
                self.evaluate(spec, results)

    def test_declarations_schema_and_receipts_required(self):
        mutations = [
            lambda s, r: s.update(predeclared=False),
            lambda s, r: r.update(independent_evaluator=1),
            lambda s, r: r.update(evaluator_id="other"),
            lambda s, r: r.update(cost_unit="usd"),
            lambda s, r: r.update(spec_sha256="changed"),
            lambda s, r: r["candidate"][0].update(passed=1),
            lambda s, r: r["baseline"][0].update(failure_reason=""),
            lambda s, r: r["candidate"][0].update(evidence=""),
            lambda s, r: r["candidate"][0].pop("severe_errors"),
            lambda s, r: r["candidate"][0].update(severe_errors="none"),
            lambda s, r: s.update(unknown=True),
        ]
        for index, mutate in enumerate(mutations):
            with self.subTest(index=index), self.assertRaises(ValueError):
                spec, results = fixture()
                mutate(spec, results)
                self.evaluate(spec, results)

    def test_no_discordance_cannot_promote(self):
        spec, results = fixture()
        results["baseline"] = copy.deepcopy(results["candidate"])
        report = self.evaluate(spec, results)
        self.assertEqual(report["holdout"]["one_sided_p_value"], 1)
        self.assertFalse(report["promotion_eligible"])

    def test_actual_cli_permits_refuses_and_detects_changed_spec(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            spec, results = fixture()
            spec_path, results_path = folder / "spec.json", folder / "results.json"
            spec_path.write_text(json.dumps(spec))
            digest = hashlib.sha256(spec_path.read_bytes()).hexdigest()
            results["spec_sha256"] = digest
            results_path.write_text(json.dumps(results))
            command = [sys.executable, str(ROOT / "bin/gtme-learning"), "evaluate",
                       "--spec", str(spec_path), "--spec-sha256", digest, "--results", str(results_path)]
            permitted = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(permitted.returncode, 0, permitted.stderr)
            self.assertTrue(json.loads(permitted.stdout)["promotion_eligible"])
            results["candidate"][0]["severe_errors"] = ["wrong_workspace"]
            results_path.write_text(json.dumps(results))
            refused = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(refused.returncode, 1, refused.stderr)
            self.assertIn("no_candidate_severe_errors", json.loads(refused.stdout)["refusal_reasons"])
            spec_path.write_text(json.dumps({**spec, "alpha": .5}))
            changed = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(changed.returncode, 2)
            self.assertIn("frozen hash", json.loads(changed.stderr)["error"])

    def test_duplicate_json_keys_refuse(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "duplicate.json"
            path.write_text('{"passed": false, "passed": true}')
            with self.assertRaisesRegex(ValueError, "duplicate JSON"):
                learning.load(path)


if __name__ == "__main__":
    unittest.main()

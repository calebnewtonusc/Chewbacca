import hashlib
import importlib.util
import itertools
import json
import math
from pathlib import Path
import random
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("gtme_math", ROOT / "tools/gtme_math.py")
math_tool = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(math_tool)


class GTMEMathTests(unittest.TestCase):
    def order_input(self, mode="or"):
        key = "valid_success_probability" if mode == "or" else "rejection_probability"
        return {"mode": mode, "assumption": "fixed_cost_independent", "cost_unit": "credits",
                "steps": [{"id": "expensive", "cost": 3, key: .9},
                          {"id": "cheap", "cost": 1, key: .5}]}

    def test_waterfall_cost_and_rate(self):
        result = math_tool.order(self.order_input())
        self.assertEqual(result["chosen_order"], ["cheap", "expensive"])
        self.assertAlmostEqual(result["baseline_expected_cost"], 3.1)
        self.assertAlmostEqual(result["chosen_expected_cost"], 2.5)
        self.assertAlmostEqual(result["validated_success_probability"], .95)

    def test_and_gate(self):
        document = self.order_input("and")
        document["steps"] = [{"id": "a", "cost": 1, "rejection_probability": .8},
                             {"id": "b", "cost": 2, "rejection_probability": .2}]
        result = math_tool.order(document)
        self.assertAlmostEqual(result["chosen_expected_cost"], 1.4)
        self.assertAlmostEqual(result["all_checks_pass_probability"], .16)

    def test_matches_exhaustive_optimum(self):
        rng = random.Random(73)
        for mode in ("and", "or"):
            key = "rejection_probability" if mode == "and" else "valid_success_probability"
            for _ in range(10):
                document = self.order_input(mode)
                document["steps"] = [{"id": str(i), "cost": rng.randrange(5),
                                       key: rng.choice([0, .2, .5, 1])} for i in range(5)]
                optimum = min(math_tool.expected_cost(p, key)[0]
                              for p in itertools.permutations(document["steps"]))
                self.assertAlmostEqual(math_tool.order(document)["chosen_expected_cost"], optimum)

    def test_order_rejects_invalid_and_unsupported(self):
        for field, value in (("cost", math.nan), ("cost", math.inf), ("cost", -1),
                             ("cost", True), ("valid_success_probability", 1.1),
                             ("valid_success_probability", None), ("prerequisites", ["a"]),
                             ("billing", "per_success")):
            with self.subTest(field=field, value=value), self.assertRaises(ValueError):
                document = self.order_input()
                document["steps"][0][field] = value
                math_tool.order(document)
        document = self.order_input()
        del document["assumption"]
        with self.assertRaises(ValueError):
            math_tool.order(document)
        document = self.order_input()
        document["steps"][1]["id"] = "expensive"
        with self.assertRaises(ValueError):
            math_tool.order(document)

    def funnel_input(self):
        return {"successes": 5, "trials": 10, "pending": 4, "outcome": "held meeting",
                "cohort": "fixture", "maturity_window": "14 days"}

    def test_wilson_known_interval_and_pending(self):
        document = self.funnel_input()
        result = math_tool.funnel(document)
        self.assertAlmostEqual(result["interval"][0], .2365930905)
        self.assertAlmostEqual(result["interval"][1], .7634069095)
        document["pending"] = 999
        self.assertEqual(result["interval"], math_tool.funnel(document)["interval"])

    def test_zero_trials_and_boundaries(self):
        document = self.funnel_input()
        document.update(successes=0, trials=0)
        result = math_tool.funnel(document)
        self.assertIsNone(result["rate"])
        self.assertEqual(result["interval"], [0, 1])
        for successes in (0, 10):
            document.update(successes=successes, trials=10)
            low, high = math_tool.funnel(document)["interval"]
            self.assertTrue(0 <= low < high <= 1)

    def test_invalid_funnel(self):
        for field, value in (("successes", 11), ("trials", 1.5), ("trials", True),
                             ("pending", -1), ("confidence", math.nan), ("confidence", 1),
                             ("confidence", 0), ("confidence", 1e-20), ("maturity_window", "")):
            with self.subTest(field=field, value=value), self.assertRaises(ValueError):
                document = self.funnel_input()
                document[field] = value
                math_tool.funnel(document)

    def fixtures(self):
        labels = [{"id": "a", "label": 1}, {"id": "b", "label": 0},
                  {"id": "c", "label": 1}, {"id": "d", "label": 0}]
        predictions = [{"id": "a", "decision": "positive", "probability": .8},
                       {"id": "b", "decision": "positive", "probability": .6},
                       {"id": "c", "decision": "abstain"},
                       {"id": "d", "decision": "negative"}]
        return labels, predictions, {"split": "heldout", "labels_sha256": "test"}

    def test_evaluation_abstains_and_brier(self):
        result = math_tool.evaluate(*self.fixtures(), "test")
        self.assertEqual(result["precision"], .5)
        self.assertEqual(result["recall_all_labeled"], .5)
        self.assertEqual(result["coverage"], .75)
        self.assertAlmostEqual(result["brier_score"], .2)
        self.assertEqual(result["probability_count"], 2)
        labels, predictions, manifest = self.fixtures()
        for prediction in predictions:
            prediction["decision"] = "abstain"
        result = math_tool.evaluate(labels, predictions, manifest, "test")
        self.assertEqual(result["coverage"], 0)
        self.assertIsNone(result["precision"])
        self.assertEqual(result["recall_all_labeled"], 0)

    def test_duplicate_missing_leaked_bad_labels(self):
        for case in ("duplicate", "missing", "leak", "hash", "label", "nan", "decision"):
            with self.subTest(case=case), self.assertRaises(ValueError):
                labels, predictions, manifest = self.fixtures()
                if case == "duplicate":
                    predictions.append(predictions[0])
                elif case == "missing":
                    predictions.pop()
                elif case == "leak":
                    manifest["train_ids"] = ["a"]
                elif case == "hash":
                    manifest["labels_sha256"] = "wrong"
                elif case == "label":
                    labels[0]["label"] = True
                elif case == "nan":
                    predictions[0]["probability"] = math.nan
                else:
                    del predictions[0]["decision"]
                math_tool.evaluate(labels, predictions, manifest, "test")

    def test_cli_reads_files_and_rejects_changed_labels(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            labels, predictions, manifest = self.fixtures()
            raw = json.dumps(labels).encode()
            manifest["labels_sha256"] = hashlib.sha256(raw).hexdigest()
            for name, value in (("labels", labels), ("predictions", predictions),
                                ("manifest", manifest)):
                (folder / f"{name}.json").write_text(json.dumps(value))
            command = [sys.executable, str(ROOT / "bin/gtme-math"), "evaluate"]
            for name in ("labels", "predictions", "manifest"):
                command += [f"--{name}", str(folder / f"{name}.json")]
            run = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(run.returncode, 0, run.stderr)
            self.assertEqual(json.loads(run.stdout)["total"], 4)
            (folder / "labels.json").write_text(json.dumps(labels) + "\n")
            run = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(run.returncode, 2)
            self.assertIn("SHA256", run.stderr)


if __name__ == "__main__":
    unittest.main()

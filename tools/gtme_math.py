#!/usr/bin/env python3
"""Offline GTM decision arithmetic. No network, credentials, or model calls."""

import argparse
import hashlib
import json
import math
from pathlib import Path
from statistics import NormalDist
import sys


def number(value, name, lower=0, upper=math.inf):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError(f"{name} must be a number")
    if not math.isfinite(value) or not lower <= value <= upper:
        raise ValueError(f"{name} must be finite and in [{lower}, {upper}]")
    return value


def count(value, name):
    number(value, name)
    if not isinstance(value, int):
        raise ValueError(f"{name} must be an integer")
    return value


def records(rows):
    if not isinstance(rows, list):
        raise ValueError("records must be a list")
    result = {}
    for row in rows:
        if not isinstance(row, dict):
            raise ValueError("each record must be an object")
        identity = row.get("id")
        if not isinstance(identity, str) or not identity.strip():
            raise ValueError("record id must be a nonempty string")
        if identity in result:
            raise ValueError("duplicate record id")
        result[identity] = row
    return result


def expected_cost(steps, probability_key):
    remaining, total = 1.0, 0.0
    for step in steps:
        total += remaining * step["cost"]
        remaining *= 1 - step[probability_key]
    if not math.isfinite(total):
        raise ValueError("expected cost overflow")
    return total, remaining


def order(document):
    if document.get("assumption") != "fixed_cost_independent":
        raise ValueError("order requires assumption: fixed_cost_independent")
    mode = document.get("mode")
    if mode not in ("and", "or"):
        raise ValueError("mode must be and (reject checks) or or (validated waterfall)")
    unit = document.get("cost_unit")
    if not isinstance(unit, str) or not unit.strip():
        raise ValueError("cost_unit is required")
    steps = list(records(document.get("steps")).values())
    key = "rejection_probability" if mode == "and" else "valid_success_probability"
    for step in steps:
        number(step.get("cost"), "cost")
        number(step.get(key), key, upper=1)
        if step.get("prerequisites") or step.get("billing") not in (None, "per_attempt"):
            raise ValueError("constrained ordering and success-only billing are unsupported")
    chosen = sorted(steps, key=lambda step: (
        step["cost"] / step[key] if step[key] else math.inf, step["id"]))
    baseline, remaining = expected_cost(steps, key)
    optimized, _ = expected_cost(chosen, key)
    savings = baseline - optimized
    return {
        "mode": mode, "assumption": document["assumption"], "cost_unit": unit,
        "baseline_order": [step["id"] for step in steps],
        "chosen_order": [step["id"] for step in chosen],
        "baseline_expected_cost": baseline, "chosen_expected_cost": optimized,
        "expected_savings": savings,
        "expected_savings_fraction": savings / baseline if baseline else None,
        "all_checks_pass_probability" if mode == "and" else "validated_success_probability":
            remaining if mode == "and" else 1 - remaining,
        "limitation": "Conditional on supplied rates and fixed per-attempt costs; "
                      "not measured savings or calibrated outcome probabilities.",
    }


def funnel(document):
    successes = count(document.get("successes"), "successes")
    trials = count(document.get("trials"), "trials")
    pending = count(document.get("pending", 0), "pending")
    if successes > trials:
        raise ValueError("successes cannot exceed matured trials")
    confidence = number(document.get("confidence", .95), "confidence", upper=1)
    if not 0 < confidence < 1 or not .5 < (1 + confidence) / 2 < 1:
        raise ValueError("confidence must be strictly between 0 and 1 at float precision")
    for field in ("outcome", "cohort", "maturity_window"):
        if not isinstance(document.get(field), str) or not document[field].strip():
            raise ValueError(f"{field} is required")
    rate, interval = None, [0.0, 1.0]
    if trials:
        # Wilson score inversion: NIST handbook prc/section2/prc241.htm.
        rate = successes / trials
        z_squared = NormalDist().inv_cdf((1 + confidence) / 2) ** 2
        denominator = 1 + z_squared / trials
        center = (rate + z_squared / (2 * trials)) / denominator
        half = math.sqrt(rate * (1 - rate) / trials +
                         z_squared / (4 * trials ** 2)) * math.sqrt(z_squared) / denominator
        interval = [max(0.0, center - half), min(1.0, center + half)]
    return {
        "successes": successes, "matured_trials": trials, "pending": pending,
        "rate": rate, "confidence": confidence, "interval": interval,
        "method": "Wilson score interval" if trials else "no observations; full range",
        **{field: document[field] for field in ("outcome", "cohort", "maturity_window")},
        "limitation": "Assumes independent binomial trials in the declared cohort; "
                      "not an always-valid sequential interval or causal effect.",
    }


def evaluate(labels, predictions, manifest, labels_hash):
    if manifest.get("split") != "heldout" or manifest.get("labels_sha256") != labels_hash:
        raise ValueError("heldout manifest must match the labels file SHA256")
    truth, proposed = records(labels), records(predictions)
    if truth.keys() != proposed.keys():
        raise ValueError("prediction IDs must exactly match labels; use explicit abstain")
    for split in ("train_ids", "calibration_ids"):
        ids = manifest.get(split, [])
        if not isinstance(ids, list) or any(not isinstance(item, str) for item in ids):
            raise ValueError(f"{split} must be a list of IDs")
        if truth.keys() & set(ids):
            raise ValueError("heldout IDs overlap training or calibration IDs")
    counts = dict(tp=0, fp=0, tn=0, fn=0, abstain_positive=0, abstain_negative=0)
    errors = []
    for identity, row in truth.items():
        label = row.get("label")
        if type(label) is not int or label not in (0, 1):
            raise ValueError("labels must be integer 0 or 1")
        prediction = proposed[identity]
        decision = prediction.get("decision")
        if decision == "abstain":
            counts["abstain_positive" if label else "abstain_negative"] += 1
        elif decision in ("positive", "negative"):
            correct = (decision == "positive") == bool(label)
            counts[("t" if correct else "f") + ("p" if decision == "positive" else "n")] += 1
        else:
            raise ValueError("decision must be positive, negative, or abstain")
        if "probability" in prediction:
            probability = number(prediction["probability"], "probability", upper=1)
            errors.append((probability - label) ** 2)
    total = len(truth)
    covered = total - counts["abstain_positive"] - counts["abstain_negative"]
    positive_calls = counts["tp"] + counts["fp"]
    positives = counts["tp"] + counts["fn"] + counts["abstain_positive"]
    return {
        "total": total, "confusion": counts,
        "coverage": covered / total if total else None,
        "precision": counts["tp"] / positive_calls if positive_calls else None,
        "recall_all_labeled": counts["tp"] / positives if positives else None,
        "accuracy_covered": (counts["tp"] + counts["tn"]) / covered if covered else None,
        "brier_score": sum(errors) / len(errors) if errors else None,
        "probability_count": len(errors), "labels_sha256": labels_hash,
        "limitation": "Hash verifies the label snapshot, not independence of its author. "
                      "Brier score covers only supplied probabilities, not proof of calibration.",
    }


def read_json(path):
    raw = sys.stdin.buffer.read() if path == "-" else Path(path).read_bytes()
    return json.loads(raw), hashlib.sha256(raw).hexdigest()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("order", "funnel"):
        command = commands.add_parser(name, help=f"Compute {name} from a JSON file (or -)")
        command.add_argument("input")
    command = commands.add_parser("evaluate", help="Score a frozen heldout label file")
    for name in ("labels", "predictions", "manifest"):
        command.add_argument(f"--{name}", required=True)
    args = parser.parse_args(argv)
    try:
        if args.command == "evaluate":
            paths = (args.labels, args.predictions, args.manifest)
            if paths.count("-") > 1:
                raise ValueError("only one input may read stdin")
            labels, digest = read_json(args.labels)
            predictions, _ = read_json(args.predictions)
            manifest, _ = read_json(args.manifest)
            if not isinstance(manifest, dict):
                raise ValueError("manifest must be an object")
            result = evaluate(labels, predictions, manifest, digest)
        else:
            document, _ = read_json(args.input)
            if not isinstance(document, dict):
                raise ValueError("input must be an object")
            result = {"order": order, "funnel": funnel}[args.command](document)
        print(json.dumps(result, indent=2, allow_nan=False))
        return 0
    except (ValueError, OSError, OverflowError) as error:
        print(json.dumps({"error": str(error)}), file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())

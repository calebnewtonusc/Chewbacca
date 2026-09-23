#!/usr/bin/env python3
"""Evaluate a frozen, paired workflow experiment offline; never apply promotion."""

import argparse
from fractions import Fraction
import hashlib
import json
import math
from pathlib import Path
import sys


def fields(document, names, label):
    if not isinstance(document, dict) or set(document) != set(names.split()):
        raise ValueError(f"{label} must contain exactly: {names}")


def text(value, label):
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{label} must be a nonempty string")
    return value


def number(value, label):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError(f"{label} must be numeric")
    try:
        valid = math.isfinite(value) and value >= 0
    except OverflowError:
        valid = False
    if not valid:
        raise ValueError(f"{label} must be finite and nonnegative")
    return value


def identities(values, label):
    if not isinstance(values, list):
        raise ValueError(f"{label} must be a list")
    for value in values:
        text(value, label)
    if len(set(values)) != len(values):
        raise ValueError(f"{label} contains duplicate IDs")
    return set(values)


def unique_object(pairs):
    document = {}
    for key, value in pairs:
        if key in document:
            raise ValueError("duplicate JSON object key")
        document[key] = value
    return document


def load(path):
    raw = Path(path).read_bytes()
    return json.loads(raw, object_pairs_hook=unique_object), hashlib.sha256(raw).hexdigest()


def task_results(rows, expected, arm):
    if not isinstance(rows, list):
        raise ValueError(f"{arm} must be a list")
    indexed = {}
    for row in rows:
        fields(row, "task_id passed severe_errors cost duration_seconds evidence failure_reason", arm)
        identity = text(row["task_id"], "task_id")
        if identity in indexed:
            raise ValueError(f"{arm} contains duplicate task IDs")
        if type(row["passed"]) is not bool:
            raise ValueError("passed must be a boolean")
        identities(row["severe_errors"], "severe_errors")
        number(row["cost"], "cost")
        number(row["duration_seconds"], "duration_seconds")
        text(row["evidence"], "evidence")
        if not row["passed"]:
            text(row["failure_reason"], "failure_reason for a failed task")
        elif row["failure_reason"] != "":
            raise ValueError("a passed task must have empty failure_reason")
        indexed[identity] = row
    if set(indexed) != expected:
        raise ValueError(f"{arm} must cover every holdout and regression ID exactly once")
    return indexed


def sign_test(wins, losses):
    """Exact Binomial(wins + losses, 1/2) upper tail; ties are excluded."""
    discordant = wins + losses
    return Fraction(sum(math.comb(discordant, k) for k in range(wins, discordant + 1)),
                    2 ** discordant)


def totals(rows):
    result = {"tasks": len(rows), "passed": sum(row["passed"] for row in rows),
              "severe_errors": sum(len(row["severe_errors"]) for row in rows)}
    for field in ("cost", "duration_seconds"):
        try:
            result[field] = math.fsum(row[field] for row in rows)
        except OverflowError as exc:
            raise ValueError(f"total {field} overflow") from exc
        number(result[field], f"total {field}")
    return result


def evaluate(spec, results, spec_hash):
    fields(spec, "experiment_id predeclared training_task_ids holdout_task_ids "
           "regression_task_ids min_tasks min_holdout_success_rate alpha cost_unit candidate_cost_budget evaluator_id", "spec")
    fields(results, "spec_sha256 cost_unit evaluator_id independent_evaluator baseline candidate", "results")
    text(spec["experiment_id"], "experiment_id")
    text(spec["cost_unit"], "cost_unit")
    text(spec["evaluator_id"], "evaluator_id")
    if spec["predeclared"] is not True or results["independent_evaluator"] is not True:
        raise ValueError("predeclared and independent_evaluator declarations must be true")
    if results["spec_sha256"] != spec_hash:
        raise ValueError("results refer to a different spec hash")
    for field in ("cost_unit", "evaluator_id"):
        if results[field] != spec[field]:
            raise ValueError(f"results {field} does not match spec")
    training = identities(spec["training_task_ids"], "training_task_ids")
    holdout = identities(spec["holdout_task_ids"], "holdout_task_ids")
    regression = identities(spec["regression_task_ids"], "regression_task_ids")
    if training & holdout or training & regression or holdout & regression:
        raise ValueError("training, holdout and regression IDs must be disjoint")
    if not holdout or not regression:
        raise ValueError("holdout and regression sets must both be nonempty")
    if type(spec["min_tasks"]) is not int or spec["min_tasks"] < 1:
        raise ValueError("min_tasks must be a positive integer")
    success_floor = number(spec["min_holdout_success_rate"], "min_holdout_success_rate")
    if success_floor > 1:
        raise ValueError("min_holdout_success_rate must be between zero and one")
    alpha = number(spec["alpha"], "alpha")
    if not 0 < alpha < 1:
        raise ValueError("alpha must be strictly between zero and one")
    budget = number(spec["candidate_cost_budget"], "candidate_cost_budget")
    baseline = task_results(results["baseline"], holdout | regression, "baseline")
    candidate = task_results(results["candidate"], holdout | regression, "candidate")
    wins = sum(candidate[key]["passed"] and not baseline[key]["passed"] for key in holdout)
    losses = sum(baseline[key]["passed"] and not candidate[key]["passed"] for key in holdout)
    baseline_holdout_passes = sum(baseline[key]["passed"] for key in holdout)
    candidate_holdout_passes = sum(candidate[key]["passed"] for key in holdout)
    probability = sign_test(wins, losses)
    baseline_totals, candidate_totals = totals(list(baseline.values())), totals(list(candidate.values()))
    protected = {key for key in regression if baseline[key]["passed"]}
    regressions = sorted(key for key in protected if not candidate[key]["passed"])
    checks = {
        "minimum_holdout_tasks": len(holdout) >= spec["min_tasks"],
        "significant_paired_improvement": wins > losses and probability <= Fraction(alpha),
        "candidate_holdout_success_floor": (
            Fraction(candidate_holdout_passes, len(holdout)) >= Fraction(str(success_floor))),
        "no_candidate_severe_errors": candidate_totals["severe_errors"] == 0,
        "candidate_cost_within_budget": candidate_totals["cost"] <= budget,
        "passing_regression_baseline_exists": bool(protected),
        "regression_nonregression": not regressions,
    }
    return {
        "experiment_id": spec["experiment_id"], "spec_sha256": spec_hash,
        "promotion_eligible": all(checks.values()), "checks": checks,
        "refusal_reasons": [name for name, passed in checks.items() if not passed],
        "holdout": {"tasks": len(holdout), "wins": wins, "losses": losses,
                    "ties": len(holdout) - wins - losses,
                    "one_sided_p_value": float(probability), "alpha": alpha,
                    "min_success_rate": success_floor,
                    "baseline": {"passed": baseline_holdout_passes,
                                 "success_rate": baseline_holdout_passes / len(holdout)},
                    "candidate": {"passed": candidate_holdout_passes,
                                  "success_rate": candidate_holdout_passes / len(holdout)}},
        "regression": {"tasks": len(regression), "protected_passes": len(protected),
                       "regressed_task_ids": regressions},
        "cost_unit": spec["cost_unit"], "candidate_cost_budget": budget,
        "baseline_totals": baseline_totals, "candidate_totals": candidate_totals,
        "limitations": [
            "Hashes verify bytes, not that the experiment was frozen before results existed.",
            "Evaluator independence and evidence references are declarations, not verified proof.",
            "The exact sign test assumes independent task pairs and a fixed comparison; "
            "repeated tuning, peeking or multiple candidates need a separate error-control design.",
            "Distinct IDs do not prove unseen task families, blind evaluation or causal business uplift.",
            "The predeclared success floor is a caller-chosen readiness criterion, not a universal standard.",
            "Totals include holdout and regression tasks; this report does not apply a promotion.",
        ],
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    command = subparsers.add_parser("evaluate", help="report promotion eligibility; never mutate a library")
    command.add_argument("--spec", required=True)
    command.add_argument("--spec-sha256", required=True, help="previously recorded SHA256 of raw spec bytes")
    command.add_argument("--results", required=True)
    args = parser.parse_args(argv)
    try:
        spec, digest = load(args.spec)
        if digest != args.spec_sha256:
            raise ValueError("spec hash differs from the supplied frozen hash")
        results, _ = load(args.results)
        report = evaluate(spec, results, digest)
    except (OSError, UnicodeError, ValueError) as exc:
        print(json.dumps({"error": str(exc)}), file=sys.stderr)
        return 2
    print(json.dumps(report, indent=2, allow_nan=False))
    return 0 if report["promotion_eligible"] else 1


if __name__ == "__main__":
    sys.exit(main())

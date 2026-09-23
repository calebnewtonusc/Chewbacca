#!/usr/bin/env python3
"""Plan and checkpoint GTM DAGs using a reconciled local evidence ledger.

The first artifact is a JSON object containing observed fields. Hashes and event
replay detect corruption and stale proofs, not fabrication by the local owner.
No network calls or campaign execution.
"""
import argparse
from datetime import datetime, timezone
import uuid
import fcntl
import hashlib
import json
import math
import os
from pathlib import Path
import sys
import tempfile


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def number(value, label):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or value < 0:
        raise ValueError(f"{label} must be finite and nonnegative")
    return value


def timestamp(value):
    if not isinstance(value, str):
        raise ValueError("timestamp must be an ISO string")
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as error:
        raise ValueError("invalid ISO timestamp") from error
    if parsed.tzinfo is None:
        raise ValueError("timestamp must include timezone")
    return parsed


def identifier(value):
    if not isinstance(value, str):
        raise ValueError("run and attempt IDs must be UUIDs")
    uuid.UUID(value)
    return value


def validate(plan):
    if not isinstance(plan, dict):
        raise ValueError("plan must be an object")
    if not isinstance(plan.get("workspace"), str) or not plan["workspace"]:
        raise ValueError("workspace is required")
    number(plan.get("credit_budget"), "credit_budget")
    nodes = plan.get("nodes", [])
    if not isinstance(nodes, list) or not nodes or any(not isinstance(n, dict) or not isinstance(n.get("id"), str) for n in nodes) or len({n.get("id") for n in nodes}) != len(nodes):
        raise ValueError("nodes must have unique IDs")
    by_id = {n["id"]: n for n in nodes}
    phases = plan.get("phases", [])
    if not isinstance(phases, list) or any(not isinstance(p, str) or not p for p in phases) or len(set(phases)) != len(phases):
        raise ValueError("phases must be an ordered list of unique names")
    kinds = {"read", "identity", "qualify", "import", "enrich", "verify", "draft", "send"}
    for node in nodes:
        if phases and node.get("phase") not in phases:
            raise ValueError("every node must belong to a declared phase")
        if not isinstance(node["id"], str) or not node["id"] or node.get("kind") not in kinds:
            raise ValueError("invalid node ID or kind")
        deps = node.get("requires", [])
        if not isinstance(deps, list) or any(not isinstance(d, str) for d in deps) or len(set(deps)) != len(deps) or any(d not in by_id for d in deps):
            raise ValueError(f"{node['id']}: invalid dependencies")
        if phases and any(phases.index(by_id[d].get("phase")) > phases.index(node["phase"]) for d in deps):
            raise ValueError("dependency points into a later phase")
        number(node.get("max_credits"), "max_credits")
        attempts = node.get("max_attempts")
        if isinstance(attempts, bool) or not isinstance(attempts, int) or attempts < 1:
            raise ValueError("max_attempts must be a positive integer")
        if not isinstance(node.get("expect"), dict) or not node["expect"]:
            raise ValueError(f"{node['id']}: observable postconditions required")
    visited, active, order = set(), set(), []

    def visit(key):
        if key in active:
            raise ValueError("dependency cycle")
        if key in visited:
            return
        active.add(key)
        for dep in by_id[key].get("requires", []):
            visit(dep)
        active.remove(key)
        visited.add(key)
        order.append(key)

    for key in by_id:
        visit(key)
    ancestors = {}
    for key in order:
        ancestors[key] = set()
        for dep in by_id[key].get("requires", []):
            ancestors[key].add(by_id[dep]["kind"])
            ancestors[key].update(ancestors[dep])
        required = {"enrich": {"identity", "qualify"}, "send": {"verify", "draft"}}.get(by_id[key]["kind"], set())
        if not required <= ancestors[key]:
            raise ValueError(f"{key}: missing prerequisite kinds {sorted(required - ancestors[key])}")
    return by_id, order


def fresh(plan, plan_path):
    validate(plan)
    return {"run_id": str(uuid.uuid4()), "plan_sha256": digest(plan_path), "spent_credits": 0,
            "reviews": {}, "nodes": {n["id"]: {"status": "pending", "attempts": 0, "reserved": 0}
                      for n in plan["nodes"]}, "events": []}


def ready(plan, state):
    by_id, order = validate(plan)
    remaining = plan["credit_budget"] - state["spent_credits"] - sum(n["reserved"] for n in state["nodes"].values())
    results = []
    for key in order:
        spec, node = by_id[key], state["nodes"][key]
        reasons = []
        if node["status"] != "pending":
            reasons.append(node["status"])
        if node["attempts"] >= spec["max_attempts"]:
            reasons.append("retry limit")
        if any(state["nodes"][dep]["status"] != "verified" for dep in spec.get("requires", [])):
            reasons.append("unverified dependency")
        if spec["max_credits"] > remaining:
            reasons.append("credit budget")
        if spec["kind"] == "send":
            reasons.append("human handoff: this tool never releases send nodes")
        phases = plan.get("phases", [])
        if phases:
            for phase in phases[:phases.index(spec["phase"])]:
                if state.get("reviews", {}).get(phase, {}).get("decision") != "continue":
                    reasons.append(f"phase review required: {phase}")
        results.append({"id": key, "ready": not reasons, "blocked_by": reasons,
                        "attempt_id": node.get("attempt_id"), "started_at": node.get("started_at")})
    return {"run_id": state["run_id"], "remaining_unreserved_credits": remaining, "nodes": results}


def begin(plan, state, key, attempt_id=None, started_at=None):
    decision = next((n for n in ready(plan, state)["nodes"] if n["id"] == key), None)
    if not decision or not decision["ready"]:
        raise ValueError(f"cannot begin {key}: {decision}")
    spec = next(n for n in plan["nodes"] if n["id"] == key)
    attempt_id = identifier(attempt_id or str(uuid.uuid4()))
    started_at = started_at or datetime.now(timezone.utc).isoformat()
    if timestamp(started_at) > datetime.now(timezone.utc):
        raise ValueError("attempt begins in the future")
    state["nodes"][key].update(attempt_id=attempt_id, started_at=started_at, status="running", attempts=state["nodes"][key]["attempts"] + 1,
                               reserved=spec["max_credits"])
    state["events"].append({"node": key, "event": "begin", "reserved": spec["max_credits"], "attempt_id": attempt_id, "started_at": started_at})


def finish(plan, state, key, evidence_path):
    node = state["nodes"][key]
    if node["status"] != "running":
        raise ValueError("node must be running")
    proof = json.loads(Path(evidence_path).read_text())
    if not isinstance(proof, dict):
        raise ValueError("evidence must be an object")
    if proof.get("run_id") != state["run_id"] or proof.get("attempt_id") != node["attempt_id"]:
        raise ValueError("evidence belongs to another run or attempt")
    if proof.get("workspace") != plan["workspace"] or proof.get("node") != key:
        raise ValueError("evidence belongs to another workspace or node")
    cost = number(proof.get("actual_credits"), "actual_credits")
    observed = timestamp(proof.get("observed_at"))
    if not timestamp(node["started_at"]) <= observed <= datetime.now(timezone.utc):
        raise ValueError("observation must fall between attempt start and now")
    artifacts = proof.get("artifacts", [])
    if not isinstance(artifacts, list) or not artifacts or any(not isinstance(a, dict) or not isinstance(a.get("path"), str) for a in artifacts):
        raise ValueError("evidence requires a captured artifact")
    verified_artifacts = []
    for item in artifacts:
        path = (Path(evidence_path).parent / item["path"]).resolve()
        if not path.is_file() or digest(path) != item.get("sha256"):
            raise ValueError("evidence artifact missing or changed")
        verified_artifacts.append({"path": str(path), "sha256": item["sha256"]})
    spec = next(n for n in plan["nodes"] if n["id"] == key)
    observations = json.loads(Path(verified_artifacts[0]["path"]).read_text())
    if not isinstance(observations, dict):
        raise ValueError("first evidence artifact must be a JSON object of observations")
    if "observations" in proof and proof["observations"] != observations:
        raise ValueError("self-reported observations conflict with captured artifact")
    passed = proof.get("outcome") == "success" and all(
        k in observations and type(observations[k]) is type(v) and observations[k] == v
        for k, v in spec["expect"].items())
    overrun = cost > node["reserved"]
    state["spent_credits"] += cost
    passed = passed and not overrun and state["spent_credits"] <= plan["credit_budget"]
    node.update(status="verified" if passed else "pending", reserved=0,
                evidence={"path": str(Path(evidence_path).resolve()), "sha256": digest(evidence_path),
                          "artifacts": verified_artifacts})
    state["events"].append({"node": key, "event": "verified" if passed else "failed",
                            "actual_credits": cost, "overrun": overrun, "evidence": node["evidence"], "attempt_id": node["attempt_id"]})
    return passed


def check_evidence(state):
    for review in state.get("reviews", {}).values():
        if digest(review["path"]) != review["sha256"]:
            raise ValueError("phase review changed; start a new run")
    for node in state["nodes"].values():
        if node["status"] != "verified":
            continue
        proof = node["evidence"]
        for item in [proof] + proof["artifacts"]:
            if not Path(item["path"]).is_file() or digest(item["path"]) != item["sha256"]:
                raise ValueError("verified evidence changed; start a new run")


def review_phase(plan, state, phase, review_path):
    if phase not in plan.get("phases", []):
        raise ValueError("unknown phase")
    members = [n for n in plan["nodes"] if n["phase"] == phase]
    if not members or any(state["nodes"][n["id"]]["status"] != "verified" for n in members):
        raise ValueError("finish and verify the phase before reviewing")
    if phase in state.get("reviews", {}):
        raise ValueError("phase already reviewed; revise the plan in a new run")
    report = json.loads(Path(review_path).read_text())
    if not isinstance(report, dict):
        raise ValueError("review must be an object")
    for field in ("baseline", "result", "reuse_audit", "math_case", "falsifier", "cheapest_next_test", "decision_reason"):
        if not isinstance(report.get(field), str) or not report[field].strip():
            raise ValueError(f"phase review missing {field}")
    alternatives = report.get("alternatives", [])
    if not isinstance(alternatives, list) or len(alternatives) < 3 or any(not isinstance(x, str) or not x.strip() for x in alternatives):
        raise ValueError("phase review requires three concrete alternatives")
    if report.get("novelty") not in {"existing", "adaptation", "unverified"}:
        raise ValueError("novelty must be existing, adaptation, or unverified; a review cannot prove a world first")
    if report.get("decision") not in {"continue", "revise", "stop"}:
        raise ValueError("invalid phase decision")
    state.setdefault("reviews", {})[phase] = {"path": str(Path(review_path).resolve()),
        "sha256": digest(review_path), "decision": report["decision"]}
    state["events"].append({"event": "review", "phase": phase, "review": state["reviews"][phase]})


def validate_state(plan, state):
    """Reconcile the local event ledger, not cryptographically authenticate its owner."""
    if not isinstance(state, dict):
        raise ValueError("state must be an object")
    identifier(state.get("run_id"))
    number(state.get("spent_credits"), "spent_credits")
    if not isinstance(state.get("nodes"), dict) or set(state["nodes"]) != {n["id"] for n in plan["nodes"]}:
        raise ValueError("state nodes do not match plan")
    for node in state["nodes"].values():
        if not isinstance(node, dict):
            raise ValueError("state node must be an object")
        number(node.get("reserved"), "reserved")
        if type(node.get("attempts")) is not int or node["attempts"] < 0:
            raise ValueError("invalid attempt count")
    if not isinstance(state.get("events"), list):
        raise ValueError("state events must be a list")
    replay = {"run_id": state["run_id"], "plan_sha256": state["plan_sha256"],
              "spent_credits": 0, "reviews": {}, "nodes": {
                  n["id"]: {"status": "pending", "attempts": 0, "reserved": 0} for n in plan["nodes"]}, "events": []}
    seen_attempts = set()
    for event in state["events"]:
        if not isinstance(event, dict):
            raise ValueError("event must be an object")
        kind = event.get("event")
        if kind == "begin":
            if event.get("attempt_id") in seen_attempts:
                raise ValueError("replayed attempt ID")
            seen_attempts.add(event.get("attempt_id"))
            begin(plan, replay, event.get("node"), event.get("attempt_id"), event.get("started_at"))
        elif kind in {"verified", "failed"}:
            evidence = event["evidence"]
            if digest(evidence["path"]) != evidence["sha256"]:
                raise ValueError("historical evidence changed")
            finish(plan, replay, event["node"], evidence["path"])
        elif kind == "review":
            review = event["review"]
            if digest(review["path"]) != review["sha256"]:
                raise ValueError("historical review changed")
            review_phase(plan, replay, event["phase"], review["path"])
        else:
            raise ValueError("invalid event kind")
        if replay["events"][-1] != event:
            raise ValueError("event does not reconcile")
    if replay != state:
        raise ValueError("state does not reconcile with event ledger")


def atomic_write(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(dir=path.parent, prefix=".gtme-")
    try:
        with os.fdopen(fd, "w") as stream:
            json.dump(value, stream, indent=2, allow_nan=False)
            stream.write("\n")
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["validate", "init", "next", "begin", "finish", "review"])
    parser.add_argument("plan", type=Path)
    parser.add_argument("--state", type=Path)
    parser.add_argument("--node")
    parser.add_argument("--evidence", type=Path)
    parser.add_argument("--phase")
    args = parser.parse_args()
    try:
        plan = json.loads(args.plan.read_text())
        _, order = validate(plan)
        if args.command == "validate":
            print(json.dumps({"valid": True, "order": order}))
            return 0
        if args.state is None:
            raise ValueError("--state required")
        args.state.parent.mkdir(parents=True, exist_ok=True)
        with open(str(args.state) + ".lock", "a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            if args.command == "init":
                if args.state.exists():
                    raise ValueError("state already exists; refusing overwrite")
                state = fresh(plan, args.plan)
            else:
                state = json.loads(args.state.read_text())
                if not isinstance(state, dict):
                    raise ValueError("state must be an object")
                if state.get("plan_sha256") != digest(args.plan):
                    raise ValueError("plan changed; start a new run")
                validate_state(plan, state)
                check_evidence(state)
            passed = True
            if args.command == "begin":
                begin(plan, state, args.node)
            elif args.command == "finish":
                if args.evidence is None:
                    raise ValueError("--evidence required")
                passed = finish(plan, state, args.node, args.evidence)
            elif args.command == "review":
                if args.evidence is None:
                    raise ValueError("--evidence required")
                review_phase(plan, state, args.phase, args.evidence)
            if args.command != "next":
                atomic_write(args.state, state)
            print(json.dumps(ready(plan, state), indent=2))
            return 0 if passed else 2
    except (ValueError, KeyError, TypeError, OSError, OverflowError, RecursionError) as error:
        print(json.dumps({"error": str(error)}), file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())

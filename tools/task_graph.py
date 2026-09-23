#!/usr/bin/env python3
"""Durable local job DAG. The host executes jobs; this tool never spawns workers.

Owner identities and successful outcomes are declarations. Artifact hashes bind
bytes, not quality or the identity of a human or model. POSIX locking is required.
"""
import argparse
from datetime import datetime, timezone
import fcntl
import hashlib
import json
import os
import stat
from pathlib import Path
import sys
import tempfile
import uuid
import unicodedata


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()


def digest(path):
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_NONBLOCK", 0)
    with os.fdopen(os.open(path, flags), "rb") as source:
        if not stat.S_ISREG(os.fstat(source.fileno()).st_mode):
            raise ValueError("expected artifact must be a regular file")
        return hashlib.file_digest(source, "sha256").hexdigest()


def exact(value, keys):
    if not isinstance(value, dict) or set(value) != set(keys.split()):
        raise ValueError("unexpected or missing object fields")


def label(value):
    if not isinstance(value, str) or not value.strip():
        raise ValueError("nonempty identifier required")
    return value


def positive(value, minimum=1):
    if type(value) is not int or value < minimum:
        raise ValueError("invalid integer limit")


def path_value(value):
    label(value)
    path = Path(value)
    if not path.is_absolute() or str(path.resolve()) != value:
        raise ValueError("paths must be absolute and canonical, without symlink aliases")
    return value


def path_key(value):
    # APFS aliases allowed two jobs to claim one artifact. Probe an existing
    # component read-only; preserve distinct names on case-sensitive volumes.
    normalized = unicodedata.normalize("NFC", value)
    path = Path(value)
    for existing in (path, *path.parents):
        alternate_name = existing.name.swapcase()
        if alternate_name == existing.name or not existing.exists():
            continue
        try:
            insensitive = os.path.samefile(existing, existing.with_name(alternate_name))
        except FileNotFoundError:
            insensitive = False
        return normalized.casefold() if insensitive else normalized
    # No existing named component to inspect: reject ambiguous names conservatively.
    return normalized.casefold()


def path_alias(left, right):
    if path_key(left) == path_key(right):
        return True
    try:
        return os.path.samefile(left, right)
    except (FileNotFoundError, NotADirectoryError):
        return False


def unique(values):
    if not isinstance(values, list):
        raise ValueError("expected a list of identifiers")
    for value in values:
        label(value)
    if len(set(values)) != len(values):
        raise ValueError("duplicate identifiers")
    return set(values)


def validate(plan):
    exact(plan, "schema_version max_active coordinator_slots nodes")
    if type(plan["schema_version"]) is not int or plan["schema_version"] != 1:
        raise ValueError("unsupported plan version")
    positive(plan["max_active"])
    positive(plan["coordinator_slots"], 0)
    if plan["coordinator_slots"] >= plan["max_active"]:
        raise ValueError("coordinator must leave at least one worker slot")
    if not isinstance(plan["nodes"], list) or not plan["nodes"]:
        raise ValueError("nodes must be nonempty")
    nodes = {}
    artifacts = []
    for node in plan["nodes"]:
        exact(node, "id kind owner depends_on max_attempts expected_artifact resources verifies")
        identity = label(node["id"])
        if identity in nodes or node["kind"] not in ("implementation", "verification"):
            raise ValueError("duplicate node or invalid kind")
        label(node["owner"])
        positive(node["max_attempts"])
        unique(node["depends_on"])
        unique(node["verifies"])
        artifact = path_value(node["expected_artifact"])
        if any(path_alias(artifact, other) for other in artifacts):
            raise ValueError("each job requires a distinct immutable expected artifact")
        artifacts.append(artifact)
        if not isinstance(node["resources"], list):
            raise ValueError("resources must be a list")
        for resource in node["resources"]:
            exact(resource, "kind path")
            if resource["kind"] not in ("file", "workspace"):
                raise ValueError("invalid resource kind")
            path_value(resource["path"])
        nodes[identity] = node
    for node in nodes.values():
        if not set(node["depends_on"]) <= nodes.keys():
            raise ValueError("missing dependency")
        verified = node["verifies"]
        if node["kind"] == "verification":
            if not verified or not set(verified) <= set(node["depends_on"]):
                raise ValueError("verification targets must be direct prerequisites")
            for identity in verified:
                target = nodes[identity]
                if target["kind"] != "implementation" or target["owner"] == node["owner"]:
                    raise ValueError("verification requires a different worker from implementation")
        elif verified:
            raise ValueError("implementation cannot declare verifies")
    pending, order = set(nodes), []
    while pending:
        ready = [identity for identity in nodes if identity in pending and set(nodes[identity]["depends_on"]) <= set(order)]
        if not ready:
            raise ValueError("dependency cycle")
        order.extend(ready)
        pending.difference_update(ready)
    return nodes, order


def resources(node):
    return node["resources"] + [{"kind": "file", "path": node["expected_artifact"]}]


def conflict(left, right):
    a, b = Path(path_key(left["path"])), Path(path_key(right["path"]))
    return path_alias(left["path"], right["path"]) or (left["kind"] == "workspace" and a in b.parents) or (right["kind"] == "workspace" and b in a.parents)


def availability(plan, jobs, nodes, order):
    active = [identity for identity, job in jobs.items() if job["status"] == "running"]
    output = []
    for identity in order:
        node, job = nodes[identity], jobs[identity]
        reasons = []
        if job["status"] not in ("pending", "failed"):
            reasons.append(job["status"])
        if job["attempts"] >= node["max_attempts"]:
            reasons.append("attempt_limit")
        if any(jobs[dep]["status"] != "succeeded" for dep in node["depends_on"]):
            reasons.append("dependencies")
        if len(active) + plan["coordinator_slots"] >= plan["max_active"]:
            reasons.append("global_slots")
        if any(nodes[key]["owner"] == node["owner"] for key in active):
            reasons.append("owner_busy")
        if any(conflict(a, b) for key in active for a in resources(node) for b in resources(nodes[key])):
            reasons.append("exclusive_resource")
        output.append({"id": identity, "owner": node["owner"], "ready": not reasons, "blocked_by": reasons})
    return {"max_active": plan["max_active"], "coordinator_slots": plan["coordinator_slots"],
            "active_jobs": active, "active_slots": len(active) + plan["coordinator_slots"], "nodes": output}


def apply_event(plan, jobs, nodes, order, event):
    if not isinstance(event, dict) or event.get("kind") not in ("claim", "finish"):
        raise ValueError("invalid event")
    identity = event.get("node")
    if identity not in nodes or event.get("worker") != nodes[identity]["owner"]:
        raise ValueError("worker does not own this node")
    node, job = nodes[identity], jobs[identity]
    if event["kind"] == "claim":
        exact(event, "kind node worker attempt_id at")
        uuid.UUID(event["attempt_id"])
        timestamp = datetime.fromisoformat(event["at"])
        if timestamp.tzinfo is None:
            raise ValueError("claim timestamp requires timezone")
        decision = next(item for item in availability(plan, jobs, nodes, order)["nodes"] if item["id"] == identity)
        if not decision["ready"]:
            raise ValueError("job not ready: " + ", ".join(decision["blocked_by"]))
        job.update(status="running", attempts=job["attempts"] + 1, attempt_id=event["attempt_id"], worker=event["worker"])
    else:
        exact(event, "kind node worker attempt_id outcome artifact reason")
        if job["status"] != "running" or event["attempt_id"] != job["attempt_id"]:
            raise ValueError("finish must match the active attempt")
        if event["outcome"] not in ("succeeded", "failed"):
            raise ValueError("invalid outcome")
        if event["outcome"] == "succeeded":
            exact(event["artifact"], "path sha256")
            if event["reason"] != "" or event["artifact"]["path"] != node["expected_artifact"] or digest(node["expected_artifact"]) != event["artifact"]["sha256"]:
                raise ValueError("successful artifact does not match expected bytes")
        else:
            label(event["reason"])
            if event["artifact"] is not None:
                raise ValueError("failed attempts do not assert an artifact")
        job["status"] = event["outcome"]


def replay(state):
    exact(state, "schema_version run_id plan plan_sha256 events")
    if type(state["schema_version"]) is not int or state["schema_version"] != 1:
        raise ValueError("unsupported state version")
    uuid.UUID(state["run_id"])
    plan = state["plan"]
    if hashlib.sha256(canonical(plan)).hexdigest() != state["plan_sha256"]:
        raise ValueError("plan changed")
    nodes, order = validate(plan)
    if not isinstance(state["events"], list):
        raise ValueError("events must be a list")
    jobs = {identity: {"status": "pending", "attempts": 0} for identity in nodes}
    attempts = set()
    for event in state["events"]:
        if isinstance(event, dict) and event.get("kind") == "claim":
            token = event.get("attempt_id")
            if not isinstance(token, str) or token in attempts:
                raise ValueError("duplicate or invalid attempt ID")
            attempts.add(token)
        apply_event(plan, jobs, nodes, order, event)
    return jobs, nodes, order


def atomic_write(path, value):
    fd, name = tempfile.mkstemp(dir=path.parent, prefix=".task-graph-")
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(canonical(value))
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(name, path)
        directory = os.open(path.parent, os.O_RDONLY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def unique_object(pairs):
    output = {}
    for key, value in pairs:
        if key in output:
            raise ValueError("duplicate JSON key")
        output[key] = value
    return output


def operate(command, state_path, plan=None, node=None, worker=None, attempt_id=None, outcome=None, reason=""):
    path = Path(state_path).resolve()
    path.parent.mkdir(parents=True, exist_ok=True)
    with Path(str(path) + ".lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if command == "init":
            validate(plan)
            if path.exists():
                raise ValueError("state already exists")
            state = {"schema_version": 1, "run_id": str(uuid.uuid4()), "plan": plan,
                     "plan_sha256": hashlib.sha256(canonical(plan)).hexdigest(), "events": []}
        else:
            if not path.is_file():
                raise ValueError("state must be a regular file")
            state = json.loads(path.read_text(), object_pairs_hook=unique_object)
        jobs, nodes, order = replay(state)
        protected = {str(path), str(path) + ".lock"}
        if any(path_alias(node["expected_artifact"], protected_path) for node in nodes.values() for protected_path in protected):
            raise ValueError("expected artifacts cannot overwrite scheduler state or lock")
        if command in ("claim", "finish"):
            if node not in nodes:
                raise ValueError("unknown node")
            if command == "claim":
                event = {"kind": "claim", "node": node, "worker": worker,
                         "attempt_id": str(uuid.uuid4()), "at": datetime.now(timezone.utc).isoformat()}
            else:
                artifact = {"path": nodes[node]["expected_artifact"], "sha256": digest(nodes[node]["expected_artifact"])} if outcome == "succeeded" else None
                event = {"kind": "finish", "node": node, "worker": worker,
                         "attempt_id": attempt_id, "outcome": outcome, "artifact": artifact, "reason": reason}
            apply_event(state["plan"], jobs, nodes, order, event)
            state["events"].append(event)
        elif command not in ("init", "ready"):
            raise ValueError("unknown command")
        if command != "ready":
            atomic_write(path, state)
        result = availability(state["plan"], jobs, nodes, order)
        result.update(run_id=state["run_id"], jobs=jobs)
        return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("init", "ready", "claim", "finish"))
    parser.add_argument("--state", type=Path, required=True)
    parser.add_argument("--plan", type=Path)
    parser.add_argument("--node")
    parser.add_argument("--worker")
    parser.add_argument("--attempt-id")
    parser.add_argument("--outcome", choices=("succeeded", "failed"))
    parser.add_argument("--reason", default="")
    args = parser.parse_args()
    try:
        plan = json.loads(args.plan.read_text(), object_pairs_hook=unique_object) if args.plan else None
        result = operate(args.command, args.state, plan, args.node, args.worker, args.attempt_id, args.outcome, args.reason)
        print(json.dumps(result))
        return 0
    except (OSError, ValueError, KeyError, TypeError, AttributeError):
        print(json.dumps({"error": "operation refused or failed; inspect durable state before retrying"}))
        return 2


if __name__ == "__main__":
    sys.exit(main())

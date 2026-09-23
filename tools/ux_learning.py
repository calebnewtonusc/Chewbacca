#!/usr/bin/env python3
"""Validate portable UX maps, suggest routes, and retain local evidence receipts."""
import argparse
from contextlib import closing
import datetime
import hashlib
import heapq
import json
import math
import os
from pathlib import Path
import re
import sqlite3
import sys


class Invalid(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise Invalid(message)


def fields(value, required, optional=()):
    require(isinstance(value, dict), 'expected an object')
    require(set(required) <= value.keys(), 'missing required fields')
    require(value.keys() <= set(required) | set(optional), 'unknown fields')


def string(value, name):
    require(isinstance(value, str) and bool(value.strip()), f'{name} must be nonempty text')


def identifier(value):
    require(isinstance(value, str) and re.fullmatch(r'[a-zA-Z0-9][a-zA-Z0-9_.-]*', value),
            'IDs must contain only letters, digits, dot, underscore, or hyphen')


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, 'duplicate JSON key')
        result[key] = value
    return result


def read_json(path):
    raw = Path(path).read_bytes()
    def bad_constant(value):
        raise Invalid(f'non-finite JSON number: {value}')
    return json.loads(raw, object_pairs_hook=unique_object, parse_constant=bad_constant), raw


def package(path):
    value, raw = read_json(path)
    fields(value, ('schema_version', 'package_id', 'revision', 'title', 'cost_unit', 'states', 'edges'), ('notes',))
    require(type(value['schema_version']) is int and value['schema_version'] == 1, 'unsupported schema_version')
    identifier(value['package_id'])
    identifier(value['revision'])
    string(value['title'], 'title')
    require(value['cost_unit'] in ('relative_effort', 'seconds'), 'invalid cost_unit')
    require(isinstance(value.get('notes', ''), str), 'notes must be text')
    require(isinstance(value['states'], list) and value['states'], 'states must be a nonempty list')
    require(isinstance(value['edges'], list), 'edges must be a list')
    states = set()
    for state in value['states']:
        fields(state, ('id', 'label'))
        identifier(state['id'])
        string(state['label'], 'label')
        require(state['id'] not in states, 'duplicate state ID')
        states.add(state['id'])
    edges = set()
    for edge in value['edges']:
        fields(edge, ('id', 'from', 'to', 'action', 'postcondition', 'status', 'cost', 'forbidden'))
        identifier(edge['id'])
        require(edge['id'] not in edges, 'duplicate edge ID')
        edges.add(edge['id'])
        require(isinstance(edge['from'], str) and edge['from'] in states and
                isinstance(edge['to'], str) and edge['to'] in states, 'missing edge endpoint')
        for key in ('action', 'postcondition'):
            string(edge[key], key)
        require(edge['status'] in ('observed', 'documented'), 'invalid edge status')
        require(type(edge['forbidden']) is bool, 'forbidden must be boolean')
        cost = edge['cost']
        require(type(cost) in (int, float), 'cost must be numeric')
        try:
            require(math.isfinite(cost) and cost >= 0, 'cost must be finite and nonnegative')
        except OverflowError:
            raise Invalid('cost too large') from None
    return value, hashlib.sha256(raw).hexdigest()


def route(value, start, goal, include_documented=False, excluded=()):
    states = {state['id'] for state in value['states']}
    require(start in states and goal in states, 'unknown start or goal')
    edges = {edge['id']: edge for edge in value['edges']}
    require(set(excluded) <= edges.keys(), 'unknown excluded edge')
    adjacency = {state: [] for state in states}
    for edge in edges.values():
        if not edge['forbidden'] and edge['id'] not in excluded and (
                edge['status'] == 'observed' or include_documented):
            adjacency[edge['from']].append(edge)
    # Dijkstra settles each state once, bounding cycles and zero-cost loops.
    queue = [(0, start, ())]
    settled = set()
    while queue:
        cost, state, path = heapq.heappop(queue)
        if state in settled:
            continue
        settled.add(state)
        if state == goal:
            return {'reachable': True, 'edges': list(path), 'estimated_cost': cost,
                    'cost_unit': value['cost_unit'], 'tentative': any(
                        edges[item]['status'] == 'documented' for item in path),
                    'executed': False}
        for edge in adjacency[state]:
            if edge['to'] not in settled:
                total = cost + edge['cost']
                require(math.isfinite(total), 'route cost overflow')
                heapq.heappush(queue, (total, edge['to'], path + (edge['id'],)))
    return {'reachable': False, 'edges': [], 'executed': False}


def file_hash(path):
    require(Path(path).is_file(), 'evidence must be a regular file')
    with Path(path).open('rb') as source:
        digest = hashlib.sha256()
        for block in iter(lambda: source.read(1024 * 1024), b''):
            digest.update(block)
        return digest.hexdigest()


def receipt(path, value):
    result, _ = read_json(path)
    fields(result, ('schema_version', 'id', 'package_id', 'revision', 'edge_id', 'outcome',
                    'observed_at', 'evidence_path', 'evidence_sha256'))
    require(type(result['schema_version']) is int and result['schema_version'] == 1, 'unsupported receipt schema_version')
    identifier(result['id'])
    require(result['package_id'] == value['package_id'] and result['revision'] == value['revision'],
            'receipt package or revision mismatch')
    require(result['edge_id'] in {edge['id'] for edge in value['edges']}, 'unknown receipt edge')
    require(result['outcome'] in ('success', 'failure'), 'invalid outcome')
    timestamp = result['observed_at']
    require(isinstance(timestamp, str) and re.fullmatch(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z', timestamp),
            'observed_at must be UTC RFC3339 ending Z')
    observed = datetime.datetime.fromisoformat(timestamp.replace('Z', '+00:00'))
    require(observed <= datetime.datetime.now(datetime.timezone.utc), 'observed_at is in the future')
    string(result['evidence_path'], 'evidence_path')
    evidence = Path(result['evidence_path']).expanduser()
    if not evidence.is_absolute():
        evidence = Path(path).resolve().parent / evidence
    result['evidence_path'] = str(evidence.resolve())
    require(isinstance(result['evidence_sha256'], str) and re.fullmatch(r'[a-f0-9]{64}', result['evidence_sha256']),
            'evidence_sha256 must be lowercase SHA-256')
    require(file_hash(evidence) == result['evidence_sha256'], 'evidence hash mismatch')
    return result


def record(value, digest, receipt_path, store):
    item = receipt(receipt_path, value)
    directory = Path(store)
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    database = directory / 'receipts.sqlite3'
    # Private receipts can contain local paths. New files use owner-only permissions.
    descriptor = os.open(database, os.O_CREAT | os.O_WRONLY, 0o600)
    os.close(descriptor)
    payload = json.dumps(item, sort_keys=True, separators=(',', ':'))
    with closing(sqlite3.connect(database)) as connection, connection:
        connection.execute('CREATE TABLE IF NOT EXISTS receipts (package TEXT, revision TEXT, digest TEXT, id TEXT, payload TEXT, PRIMARY KEY(package, revision, id))')
        connection.execute('BEGIN IMMEDIATE')
        existing = connection.execute('SELECT digest, payload FROM receipts WHERE package=? AND revision=? AND id=?',
                                      (value['package_id'], value['revision'], item['id'])).fetchone()
        require(existing is None or existing == (digest, payload), 'receipt ID already exists with different content or package bytes')
        prior = connection.execute('SELECT payload FROM receipts WHERE package=? AND revision=? AND digest=?',
                                   (value['package_id'], value['revision'], digest)).fetchall()
        for (prior_payload,) in prior:
            other = json.loads(prior_payload)
            require(not (other['edge_id'] == item['edge_id'] and
                         other['evidence_sha256'] == item['evidence_sha256'] and
                         other['outcome'] != item['outcome']), 'same evidence has conflicting outcomes')
        if existing is None:
            connection.execute('INSERT INTO receipts VALUES (?, ?, ?, ?, ?)',
                               (value['package_id'], value['revision'], digest, item['id'], payload))
    return {'recorded': existing is None, 'duplicate': existing is not None,
            'evidence_integrity': 'matched', 'independent_authentication': False}


def wilson(successes, count):
    if not count:
        return None
    # 1.95996 is the standard normal quantile for a two-sided 95% interval.
    z = 1.959963984540054
    proportion = successes / count
    denominator = 1 + z * z / count
    center = (proportion + z * z / (2 * count)) / denominator
    radius = z * math.sqrt(proportion * (1 - proportion) / count + z * z / (4 * count * count)) / denominator
    return [max(0, center - radius), min(1, center + radius)]


def status(value, digest, store):
    counts = {edge['id']: {'attempts': 0, 'successes': 0, 'failures': 0} for edge in value['edges']}
    invalid = 0
    database = Path(store) / 'receipts.sqlite3'
    rows = []
    if database.exists():
        # Read-only URI avoids creating either a store or database during inspection.
        with closing(sqlite3.connect(database.resolve().as_uri() + '?mode=ro', uri=True)) as connection:
            rows = connection.execute('SELECT payload FROM receipts WHERE package=? AND revision=? AND digest=?',
                                      (value['package_id'], value['revision'], digest)).fetchall()
    seen_evidence = set()
    duplicates = 0
    for (payload,) in rows:
        item = json.loads(payload)
        try:
            require(item['edge_id'] in counts and item['outcome'] in ('success', 'failure'), 'invalid stored receipt')
            require(file_hash(item['evidence_path']) == item['evidence_sha256'], 'changed evidence')
        except (OSError, ValueError, KeyError):
            invalid += 1
            continue
        # Reusing the same evidence for an edge does not manufacture extra trials.
        identity = (item['edge_id'], item['evidence_sha256'])
        if identity in seen_evidence:
            duplicates += 1
            continue
        seen_evidence.add(identity)
        count = counts[item['edge_id']]
        count['attempts'] += 1
        count['successes' if item['outcome'] == 'success' else 'failures'] += 1
    for count in counts.values():
        count['wilson_95'] = wilson(count['successes'], count['attempts'])
        count['readiness'] = 'observed-success' if count['successes'] else 'not-demonstrated'
    return {'package_id': value['package_id'], 'revision': value['revision'], 'package_sha256': digest,
            'edges': counts, 'invalid_evidence_receipts': invalid, 'reused_evidence_receipts': duplicates,
            'mastery': 'not-assessed', 'independent_authentication': False,
            'interval_caveat': 'Descriptive only; independence and representativeness are not established.'}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    for command in ('validate', 'route', 'record', 'status'):
        sub = commands.add_parser(command)
        sub.add_argument('package')
        if command == 'route':
            sub.add_argument('--start', required=True)
            sub.add_argument('--goal', required=True)
            sub.add_argument('--include-documented', action='store_true')
            sub.add_argument('--exclude-edge', action='append', default=[])
        if command in ('record', 'status'):
            sub.add_argument('--store', required=True)
        if command == 'record':
            sub.add_argument('--receipt', required=True)
    args = parser.parse_args(argv)
    try:
        value, digest = package(args.package)
        if args.command == 'validate':
            result = {'valid': True, 'package_id': value['package_id'], 'package_sha256': digest}
        elif args.command == 'route':
            result = route(value, args.start, args.goal, args.include_documented, args.exclude_edge)
        elif args.command == 'record':
            result = record(value, digest, args.receipt, args.store)
        else:
            result = status(value, digest, args.store)
        print(json.dumps(result, indent=2, allow_nan=False))
        return 0
    except (OSError, ValueError, TypeError, sqlite3.Error) as error:
        print(json.dumps({'error': str(error)}), file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())

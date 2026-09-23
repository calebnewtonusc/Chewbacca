#!/usr/bin/env python3
"""Offline, evidence-bound UX planning and categorical contextual bandit learning."""
import argparse
import fcntl
import heapq
import json
import math
import os
from pathlib import Path
import sqlite3
import sys
import tempfile

from ux_learning import Invalid, fields, file_hash, identifier, package, read_json, require, status


def finite(value, name, low=0, high=None):
    require(type(value) in (int, float), f'{name} must be numeric')
    try:
        valid = math.isfinite(value) and value >= low and (high is None or value <= high)
    except OverflowError:
        valid = False
    require(valid, f'{name} outside finite bounds')
    return value


def minimum(value):
    require(type(value) is int and value >= 1, 'min_trials must be a positive integer')


def eligible(value, permitted):
    require(isinstance(permitted, list) and all(isinstance(x, str) for x in permitted), 'permit must be a list of IDs')
    edges = {edge['id']: edge for edge in value['edges']}
    require(len(set(permitted)) == len(permitted) and set(permitted) <= edges.keys(), 'unknown or duplicate permitted edge')
    return {key: edges[key] for key in permitted if not edges[key]['forbidden'] and edges[key]['status'] == 'observed'}


def plan(value, digest, store, start, goal, permitted, min_trials, independent_retries=False):
    minimum(min_trials)
    states = {state['id'] for state in value['states']}
    require(start in states and goal in states, 'unknown state')
    edges = eligible(value, permitted)
    evidence = status(value, digest, store)
    assessments = {}
    adjacency = {state: [] for state in states}
    for key, edge in edges.items():
        counts = evidence['edges'][key]
        assessed = counts['attempts'] >= min_trials
        lower = counts['wilson_95'][0] if counts['wilson_95'] else None
        usable = assessed and counts['successes'] > 0 and lower is not None and lower > 0
        assessments[key] = {**counts, 'assessment': 'assessed' if assessed else 'unassessed',
                            'wilson_lower': lower}
        if usable:
            cost = edge['cost'] / lower if independent_retries else edge['cost']
            finite(cost, 'weighted cost')
            adjacency[edge['from']].append((key, edge['to'], cost))
    queue = [(0, (), start)]
    settled = set()
    while queue:
        cost, path, current = heapq.heappop(queue)
        if current in settled:
            continue
        settled.add(current)
        if current == goal:
            return {'reachable': True, 'edges': list(path), 'cost': cost,
                    'objective': 'conservative_retry_cost' if independent_retries else 'declared_cost',
                    'cost_unit': value['cost_unit'], 'assessments': assessments, 'executed': False,
                    'assumption': 'Independent stationary Bernoulli attempts; failure returns to same state with same cost.' if independent_retries else 'No retry model asserted.',
                    'warning': 'Evidence integrity checked, not independent truth or representative trials.'}
        for key, target, weight in sorted(adjacency[current]):
            total = cost + weight
            finite(total, 'path cost')
            if target not in settled:
                heapq.heappush(queue, (total, path + (key,), target))
    return {'reachable': False, 'edges': [], 'assessments': assessments,
            'fallback': 'inspect_current_state_and_collect_verified_evidence', 'executed': False}


def binding(value, digest):
    return {'package_id': value['package_id'], 'revision': value['revision'], 'package_sha256': digest}


def load_state(path, value, digest):
    state, _ = read_json(path)
    fields(state, ('schema_version', 'binding', 'reward', 'events', 'contexts'))
    require(type(state['schema_version']) is int and state['schema_version'] == 1, 'unsupported policy schema')
    require(state['binding'] == binding(value, digest), 'stale policy: package bytes or version changed; use a new state path')
    reward_config(state['reward'])
    require(isinstance(state['events'], dict) and isinstance(state['contexts'], dict), 'invalid policy state')
    for event_id, event in state['events'].items():
        require(isinstance(event, dict) and event.get('id') == event_id, 'event ledger ID mismatch')
    validate_replay({'schema_version': 1, 'binding': state['binding'], 'reward': state['reward'],
                     'events': list(state['events'].values())}, value, digest, path)
    rebuilt = {}
    for event in state['events'].values():
        update_arm(rebuilt, event, state['reward'])
    require(set(rebuilt) == set(state['contexts']), 'state contexts disagree with verified events')
    for context, arms in rebuilt.items():
        require(isinstance(state['contexts'][context], dict) and set(arms) == set(state['contexts'][context]), 'state arms disagree with verified events')
        for action, expected in arms.items():
            actual = state['contexts'][context][action]
            fields(actual, ('count', 'mean'))
            require(type(actual['count']) is int and actual['count'] == expected['count'], 'state counts disagree with verified events')
            finite(actual['mean'], 'mean reward', -1, 1)
            # JSON key sorting changes summation order; tolerate round-off only.
            require(math.isclose(actual['mean'], expected['mean'], rel_tol=1e-12, abs_tol=1e-12), 'state mean disagrees with verified events')
    return state


def reward_config(config):
    fields(config, ('cost_weight', 'cost_scale'))
    finite(config['cost_weight'], 'cost_weight', 0, 1)
    finite(config['cost_scale'], 'cost_scale')
    require(config['cost_scale'] > 0, 'cost_scale must be positive')


def replay(path, value, digest):
    payload, _ = read_json(path)
    return validate_replay(payload, value, digest, path)


def validate_replay(payload, value, digest, path):
    fields(payload, ('schema_version', 'binding', 'reward', 'events'))
    require(type(payload['schema_version']) is int and payload['schema_version'] == 1, 'unsupported replay schema')
    require(payload['binding'] == binding(value, digest), 'replay binding mismatch')
    reward_config(payload['reward'])
    require(isinstance(payload['events'], list), 'events must be a list')
    seen, evidence_seen = set(), set()
    for item in payload['events']:
        fields(item, ('id', 'context', 'action', 'eligible', 'success', 'cost', 'evidence_path', 'evidence_sha256'))
        identifier(item['id'])
        identifier(item['context'])
        require(item['id'] not in seen, 'duplicate replay event ID')
        seen.add(item['id'])
        allowed = eligible(value, item['eligible'])
        require(isinstance(item['action'], str) and item['action'] in allowed, 'logged action is ineligible')
        require(type(item['success']) is bool, 'success must be verifier boolean')
        finite(item['cost'], 'event cost')
        require(isinstance(item['evidence_path'], str) and item['evidence_path'], 'missing evidence path')
        evidence = Path(item['evidence_path'])
        if not evidence.is_absolute():
            evidence = Path(path).resolve().parent / evidence
        require(file_hash(evidence) == item['evidence_sha256'], 'evidence hash mismatch')
        item['evidence_path'] = str(evidence.resolve())
        require(item['evidence_sha256'] not in evidence_seen, 'reused evidence is not another trial')
        evidence_seen.add(item['evidence_sha256'])
    return payload


def event_fingerprint(event):
    # IDs and file locations do not create new independent evidence.
    return event['evidence_sha256']


def reward(event, config):
    penalty = config['cost_weight'] * min(event['cost'] / config['cost_scale'], 1)
    return float(event['success']) - penalty


def update_arm(contexts, item, config):
    arm = contexts.setdefault(item['context'], {}).setdefault(item['action'], {'count': 0, 'mean': 0})
    arm['count'] += 1
    arm['mean'] += (reward(item, config) - arm['mean']) / arm['count']


def train(state_path, value, digest, payload):
    destination = Path(state_path)
    destination.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    # Stable adjacent lock survives atomic replacement of the state inode.
    descriptor = os.open(str(destination) + '.lock', os.O_CREAT | os.O_RDWR, 0o600)
    with os.fdopen(descriptor, 'r+') as lock:
        try:
            fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise Invalid('policy state has another training writer; retry later') from None
        return train_locked(state_path, value, digest, payload)


def train_locked(state_path, value, digest, payload):
    validate_replay(payload, value, digest, state_path)
    if Path(state_path).exists():
        state = load_state(state_path, value, digest)
        require(state['reward'] == payload['reward'], 'reward configuration changed')
    else:
        state = {'schema_version': 1, 'binding': binding(value, digest), 'reward': payload['reward'], 'events': {}, 'contexts': {}}
    require(not (set(state['events']) & {item['id'] for item in payload['events']}), 'replayed training ID; training is append-only')
    require(not ({event_fingerprint(item) for item in state['events'].values()} & {event_fingerprint(item) for item in payload['events']}), 'training evidence already used')
    for item in payload['events']:
        update_arm(state['contexts'], item, state['reward'])
        state['events'][item['id']] = item
    destination = Path(state_path)
    destination.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    descriptor, temporary = tempfile.mkstemp(dir=destination.parent, prefix='.ux-policy-')
    try:
        with os.fdopen(descriptor, 'w') as handle:
            json.dump(state, handle, sort_keys=True, indent=2, allow_nan=False)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, destination)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    return {'trained_events': len(payload['events']), 'total_events': len(state['events']), 'executed': False}


def recommend(state, value, context, permitted, min_trials):
    minimum(min_trials)
    identifier(context)
    allowed = eligible(value, permitted)
    arms = state['contexts'].get(context, {})
    assessed = [(arm['mean'], key) for key, arm in arms.items() if key in allowed and arm['count'] >= min_trials]
    unassessed = sorted(key for key in allowed if key not in arms or arms[key]['count'] < min_trials)
    if not assessed:
        return {'action': None, 'reason': 'insufficient_context_evidence', 'unassessed': unassessed, 'executed': False}
    mean, action = sorted(assessed, key=lambda pair: (-pair[0], pair[1]))[0]
    # Under this reward definition, abstaining costs nothing and returns zero.
    if mean <= 0:
        return {'action': None, 'reason': 'no_positive_reward', 'best_mean_reward': mean,
                'abstain_reward': 0, 'unassessed': unassessed, 'executed': False}
    return {'action': action, 'mean_reward': mean, 'trials': arms[action]['count'],
            'unassessed': unassessed, 'policy': 'offline_greedy_categorical_context', 'executed': False}


def evaluate(state, value, payload, min_trials):
    require(state['reward'] == payload['reward'], 'reward configuration changed')
    require(not (set(state['events']) & {item['id'] for item in payload['events']}), 'holdout IDs overlap training')
    require(not ({event_fingerprint(item) for item in state['events'].values()} & {event_fingerprint(item) for item in payload['events']}), 'holdout evidence overlaps training')
    matched = []
    for item in payload['events']:
        choice = recommend(state, value, item['context'], item['eligible'], min_trials)
        if choice['action'] == item['action']:
            matched.append(reward(item, state['reward']))
    return {'holdout_events': len(payload['events']), 'matched_events': len(matched),
            'matched_mean_reward': sum(matched) / len(matched) if matched else None,
            'warning': 'Action-matched descriptive replay only; biased logging is not causal policy evaluation. No counterfactual reward imputed.',
            'trained': False, 'executed': False}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    for command in ('plan', 'train', 'recommend', 'evaluate'):
        sub = commands.add_parser(command)
        sub.add_argument('package')
        if command != 'plan':
            sub.add_argument('--state', required=True)
        if command in ('train', 'evaluate'):
            sub.add_argument('--replay', required=True)
        if command != 'train':
            sub.add_argument('--min-trials', type=int, required=True)
        if command in ('plan', 'recommend'):
            sub.add_argument('--permit', action='append', default=[])
        if command == 'plan':
            sub.add_argument('--store', required=True)
            sub.add_argument('--start', required=True)
            sub.add_argument('--goal', required=True)
            sub.add_argument('--independent-retries', action='store_true')
        if command == 'recommend':
            sub.add_argument('--context', required=True)
    args = parser.parse_args(argv)
    try:
        value, digest = package(args.package)
        if args.command == 'plan':
            result = plan(value, digest, args.store, args.start, args.goal, args.permit, args.min_trials, args.independent_retries)
        elif args.command == 'train':
            result = train(args.state, value, digest, replay(args.replay, value, digest))
        else:
            state = load_state(args.state, value, digest)
            result = recommend(state, value, args.context, args.permit, args.min_trials) if args.command == 'recommend' else evaluate(state, value, replay(args.replay, value, digest), args.min_trials)
        print(json.dumps(result, indent=2, allow_nan=False))
        return 0
    except (OSError, ValueError, TypeError, KeyError, sqlite3.Error) as error:
        print(json.dumps({'error': str(error)}), file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())

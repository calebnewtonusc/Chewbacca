"""Explicit, bounded decision experiments; predictions never authorize actions."""
from __future__ import annotations
import argparse
from contextlib import contextmanager
import fcntl
import hashlib
import json
import math
import os
from pathlib import Path
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'bin' / 'lib'))
import jev


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':'), allow_nan=False).encode()).hexdigest()


def number(value, name, low=0, high=None):
    try:
        valid = not isinstance(value, bool) and isinstance(value, (int, float)) and value >= low and (high is None or value <= high) and math.isfinite(value)
    except OverflowError:
        valid = False
    if not valid:
        raise ValueError(f'invalid {name}')
    return value


def text(value, name):
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f'missing {name}')


def validate_registry(config):
    if not isinstance(config, dict) or type(config.get('schema_version')) is not int or config['schema_version'] != 1:
        raise ValueError('unsupported registry schema_version')
    for key in ('id', 'version', 'question', 'model'):
        text(config.get(key), key)
    criteria = config.get('criteria')
    if not isinstance(criteria, dict) or len(criteria) < 2 or 'abstain' in criteria:
        raise ValueError('criteria needs at least two choices; abstain is reserved')
    for key, value in criteria.items():
        text(key, 'choice'); text(value, 'criterion')
    math_spec = config['mathematical']
    if not isinstance(math_spec, dict): raise ValueError('mathematical must be an object')
    text(math_spec.get('objective'), 'objective')
    for key in ('error_loss', 'abstain_loss'):
        number(math_spec.get(key), key)
    probability_floor(config)
    if 'loss_matrix' in math_spec:
        matrix = math_spec['loss_matrix']
        if not isinstance(matrix, dict) or set(matrix) != {*criteria, 'abstain'}:
            raise ValueError('loss_matrix requires every action and abstain row')
        for row in matrix.values():
            if not isinstance(row, dict) or set(row) != set(criteria):
                raise ValueError('loss_matrix requires every true class in every row')
            for value in row.values(): number(value, 'loss_matrix entry')
    budget = math_spec['budget']
    if not isinstance(budget, dict): raise ValueError('budget must be an object')
    for key in ('max_calls', 'max_input_bytes'):
        if type(budget.get(key)) is not int or budget[key] < 1:
            raise ValueError(f'invalid {key}')
    number(budget.get('timeout_seconds'), 'timeout_seconds', 0.001)
    creative = config['creative']
    if not isinstance(creative, dict): raise ValueError('creative must be an object')
    alternatives = creative.get('alternatives')
    if not isinstance(alternatives, list) or len(alternatives) < 2:
        raise ValueError('two distinct alternatives required')
    for value in alternatives:
        text(value, 'alternative')
    if len(set(alternatives)) < 2: raise ValueError('distinct alternatives required')
    for key in ('baseline', 'falsifier'):
        text(creative.get(key), key)
    proprietary = config['proprietary']
    if not isinstance(proprietary, dict): raise ValueError('proprietary must be an object')
    for key in ('reusable_asset', 'privacy', 'ownership'):
        text(proprietary.get(key), key)
    if proprietary.get('novelty') not in ('existing', 'adaptation', 'unverified'):
        raise ValueError('novelty must not claim unproven originality')
    digest(config)
    return config


def probability_floor(config):
    spec = config['mathematical']
    modern = spec.get('selected_probability_floor')
    legacy = spec.get('confidence_threshold')
    if modern is not None and legacy is not None and modern != legacy:
        raise ValueError('conflicting selected_probability_floor and confidence_threshold')
    if modern is not None: number(modern, 'selected_probability_floor', 0, 1)
    if legacy is not None: number(legacy, 'confidence_threshold', 0, 1)
    value = modern if modern is not None else legacy
    return number(value, 'selected_probability_floor', 0, 1)


def expected_losses(config, probabilities):
    matrix = config['mathematical'].get('loss_matrix')
    if matrix is None:
        return None
    return {action: sum(probabilities[label] * loss for label, loss in row.items())
            for action, row in matrix.items()}


def realized_loss(config, action, label):
    spec = config['mathematical']
    if 'loss_matrix' in spec:
        return spec['loss_matrix'][action][label]
    return spec['abstain_loss'] if action == 'abstain' else spec['error_loss'] * (action != label)


def questions(config):
    return {'decision': {'type': 'choice', 'instructions': config['question'], 'criteria': config['criteria']}}


def validate_example(example, config):
    if not isinstance(example, dict): raise ValueError('example must be an object')
    for key in ('id', 'dataset_version', 'provenance'):
        text(example.get(key), key)
    if example.get('config_version') != config['version']:
        raise ValueError('stale example config_version')
    if example.get('split') not in ('train', 'heldout') or example.get('data_class') not in ('synthetic', 'public', 'nonpublic'):
        raise ValueError('invalid split or data_class')
    if 'state' not in example or example.get('baseline') not in [*config['criteria'], 'abstain']:
        raise ValueError('state and valid baseline required')
    if len(json.dumps({'state': example['state'], 'model': config['model'], 'questions': questions(config)}, allow_nan=False).encode()) > config['mathematical']['budget']['max_input_bytes']:
        raise ValueError('input byte budget exceeded')
    digest(example)


def parse_answer(answers, config):
    answer = answers.get('decision') if isinstance(answers, dict) else None
    if not isinstance(answer, dict):
        raise ValueError('missing decision')
    if 'type' in answer and answer['type'] != 'choice':
        raise ValueError('wrong answer type')
    probs = answer.get('probabilities')
    if not isinstance(probs, dict) or set(probs) != set(config['criteria']):
        raise ValueError('incomplete probability distribution')
    for value in probs.values():
        number(value, 'probability', 0, 1)
    # Numerical serialization tolerance, not an empirically calibrated threshold.
    if abs(sum(probs.values()) - 1) > 1e-6:
        raise ValueError('probabilities do not sum to one')
    choice = answer.get('choice')
    if choice not in probs or probs[choice] != max(probs.values()):
        raise ValueError('invalid choice')
    if 'loss_matrix' not in config['mathematical'] and sum(value == probs[choice] for value in probs.values()) > 1:
        return 'abstain', 'tied', probs
    risks = expected_losses(config, probs)
    if risks is not None:
        minimum = min(risks.values())
        winners = [action for action, risk in risks.items() if risk == minimum]
        if len(winners) != 1: return 'abstain', 'risk_tied', probs
        choice = winners[0]
        if choice == 'abstain': return 'abstain', 'minimum_expected_loss_abstain', probs
    if probs[choice] < decision_threshold(config):
        return 'abstain', 'low_confidence', probs
    return choice, 'minimum_expected_loss' if risks is not None else 'predicted', probs


def decision_threshold(config):
    """Bayes risk boundary for calibrated probabilities and zero correct loss.

    With constant wrong loss C and abstention A, select only if C*(1-p)<=A.
    Raw provider scores are not proven calibrated; the configured floor can be
    stricter. This calculation alone is not a reliability certificate.
    """
    spec = config['mathematical']
    cost_floor = max(0, 1-spec['abstain_loss']/spec['error_loss']) if spec['error_loss'] else 0
    return probability_floor(config) if 'loss_matrix' in spec else max(probability_floor(config), cost_floor)


def decide(config, example, *, ask=None, live=False, allow_nonpublic=False):
    validate_registry(config); validate_example(example, config)
    if live and ask is not None:
        raise ValueError('live mode cannot use injected provider')
    if (live or ask is not None) and example['data_class'] == 'nonpublic' and not allow_nonpublic:
        raise ValueError('nonpublic transmission requires explicit --allow-nonpublic')
    request = questions(config)
    started = time.monotonic()
    mode = 'live' if live else ('mock' if ask is not None else 'offline')
    choice, reason, probabilities = 'abstain', 'offline', None
    resolved_model, usage, vendor_confidence = None, None, None
    if live or ask is not None:
        if live:
            # Gavin's transport reads MODEL, so reject drift instead of changing global runtime settings.
            if jev.MODEL != config['model']:
                raise ValueError('registry model differs from TYPESAFE_MODEL; set it explicitly before invocation')
            ask = jev.ask_result
        try:
            answers = ask(example['state'], request, timeout=config['mathematical']['budget']['timeout_seconds'])
            if live and isinstance(answers, dict):
                metadata = answers
                resolved_model = metadata.get('model') if isinstance(metadata.get('model'), str) and metadata['model'].strip() else None
                supplied_usage = metadata.get('usage')
                if isinstance(supplied_usage, dict):
                    usage = {k: supplied_usage[k] for k in ('input_tokens', 'output_tokens', 'total_tokens') if type(supplied_usage.get(k)) is int and supplied_usage[k] >= 0}
                    usage = usage or None
                answers = metadata.get('answers')
            choice, reason, probabilities = parse_answer(answers, config)
            supplied_confidence = answers['decision'].get('confidence')
            if type(supplied_confidence) in (int, float) and 0 <= supplied_confidence <= 1 and math.isfinite(supplied_confidence):
                vendor_confidence = supplied_confidence
        except (ValueError, TypeError, KeyError, OSError, TimeoutError):
            choice, reason, probabilities = 'abstain', 'provider_failure_or_invalid', None
    identity = {'config_hash': digest(config), 'input_hash': digest(example), 'mode': mode}
    return {'kind': 'decision', 'id': digest(identity), **identity,
            'config': config, 'state_hash': digest(example['state']), 'example_id': example['id'], 'dataset_version': example['dataset_version'],
            'split': example['split'], 'data_class': example['data_class'], 'provenance': example['provenance'],
            'baseline': example['baseline'], 'choice': choice, 'reason': reason, 'probabilities': probabilities,
            'latency_seconds': time.monotonic() - started, 'actual_cost': None,
            'resolved_model': resolved_model, 'usage': usage, 'vendor_confidence': vendor_confidence,
            'effective_threshold': decision_threshold(config),
            'expected_losses': expected_losses(config, probabilities) if probabilities is not None else None, 'action_authorized': False, 'nonpublic_opt_in': bool(allow_nonpublic)}


def read_records(path):
    if not Path(path).exists():
        return []
    with Path(path).open() as stream:
        return [json.loads(line) for line in stream if line.strip()]


def append_record(path, record):
    """Private append-only ledger; exact retry accepted, different payload rejected."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(path, os.O_RDWR | os.O_CREAT | os.O_APPEND, 0o600)
    with os.fdopen(fd, 'r+') as stream:
        fcntl.flock(stream, fcntl.LOCK_EX)
        os.fchmod(stream.fileno(), 0o600)
        existing = [json.loads(line) for line in stream if line.strip()]
        for prior in existing:
            if prior['kind'] == record['kind'] and prior['id'] == record['id']:
                if prior != record:
                    raise ValueError('ledger id conflicts with prior payload')
                return False
        stream.seek(0, 2)
        stream.write(json.dumps(record, sort_keys=True, allow_nan=False) + '\n')
        stream.flush(); os.fsync(stream.fileno())
    return True


def join_outcome(path, decision_id, outcome):
    decisions = [r for r in read_records(path) if r['kind'] == 'decision' and r['id'] == decision_id]
    if len(decisions) != 1:
        raise ValueError('outcome must join exactly one decision')
    decision = decisions[0]
    if outcome.get('input_hash') != decision['input_hash'] or outcome.get('config_hash') != decision['config_hash']:
        raise ValueError('stale or mismatched outcome hashes')
    if outcome.get('label') not in decision['config']['criteria'] or outcome.get('verified') is not True:
        raise ValueError('explicit verified label required')
    for key in ('verifier', 'evidence', 'evidence_sha256'):
        text(outcome.get(key), key)
    evidence_path = Path(outcome['evidence'])
    if not evidence_path.is_absolute() or not evidence_path.is_file():
        raise ValueError('evidence must name an existing absolute file path')
    if hashlib.sha256(evidence_path.read_bytes()).hexdigest() != outcome['evidence_sha256']:
        raise ValueError('outcome evidence digest does not match file')
    if 'actual_cost' in outcome and outcome['actual_cost'] is not None:
        number(outcome['actual_cost'], 'actual_cost')
        text(outcome.get('cost_currency'), 'cost_currency')
    record = {**outcome, 'kind': 'outcome', 'id': decision_id}
    append_record(path, record)
    return record


def wilson(errors, count):
    if not count:
        return None
    z = 1.959963984540054  # Standard normal two-sided 95% quantile.
    rate = errors / count
    center = (rate + z*z/(2*count)) / (1 + z*z/count)
    half = z * math.sqrt(rate*(1-rate)/count + z*z/(4*count*count)) / (1 + z*z/count)
    return [max(0, center-half), min(1, center+half)]


def report(records, config):
    validate_registry(config)
    config_hash = digest(config)
    assigned = {r['id']: r for r in records if r['kind'] in ('assignment', 'decision') and r.get('config_hash') == config_hash and r.get('split') == 'heldout'}
    modes = {r.get('mode') for r in assigned.values()}
    if len(modes) > 1:
        raise ValueError('mixed experiment modes; use separate ledgers for live, mock and offline')
    outcomes = {r['id']: r for r in records if r['kind'] == 'outcome'}
    decisions = {r['id']: r for r in records if r['kind'] == 'decision'}
    pairs = []
    seen_inputs = set()
    exclusions = {'pending_decision': 0, 'pending_outcome': 0, 'invalid_outcome': 0,
                  'missing_or_changed_evidence': 0, 'training_overlap': 0}
    training_states = {r.get('state_hash') for r in records if r['kind'] == 'decision' and r.get('split') == 'train'}
    for identity, assignment in assigned.items():
        state_hash = assignment.get('state_hash', assignment['input_hash'])
        if state_hash in seen_inputs:
            raise ValueError('duplicate held-out state; examples must be independent')
        seen_inputs.add(state_hash)
        if state_hash in training_states:
            exclusions['training_overlap'] += 1
            continue
        decision = decisions.get(identity)
        if decision is None:
            exclusions['pending_decision'] += 1
            continue
        outcome = outcomes.get(identity)
        if outcome is None:
            exclusions['pending_outcome'] += 1
            continue
        if (outcome.get('verified') is not True or outcome.get('config_hash') != config_hash
                or outcome.get('input_hash') != decision['input_hash'] or outcome.get('label') not in config['criteria']):
            exclusions['invalid_outcome'] += 1
            continue
        try:
            evidence = Path(outcome.get('evidence', ''))
            if not evidence.is_absolute() or hashlib.sha256(evidence.read_bytes()).hexdigest() != outcome.get('evidence_sha256'):
                raise ValueError('changed evidence')
        except (OSError, ValueError, TypeError):
            exclusions['missing_or_changed_evidence'] += 1
            continue
        pairs.append((decision, outcome))
    count = len(assigned)
    completed = sum(identity in decisions for identity in assigned)
    failures = sum(decisions[identity].get('reason') == 'provider_failure_or_invalid' for identity in assigned if identity in decisions)
    result = {'assigned_heldout_count': count, 'completed_decision_count': completed,
              'decision_completion_rate': completed / count if count else None,
              'outcome_completion_rate': len(pairs) / count if count else None,
              'provider_failure_count': failures, 'excluded_counts': exclusions,
              'evaluation_complete': bool(count) and len(pairs) == count,
              'mode': next(iter(modes)) if modes else None,
              'paired_count': len(pairs), 'metrics': {}, 'promotion_allowed': False,
              'promotion_reason': 'Manual review and representative held-out evidence required; this tool never promotes.',
              'live_real_heldout_count': sum(d['mode'] == 'live' and d['data_class'] != 'synthetic' for d, _ in pairs),
              'cost': None, 'cost_note': 'Unknown unless verified actual costs supplied for every paired decision.'}
    losses = {}
    for name in ('baseline', 'choice'):
        predictions = [(d[name], o['label']) for d, o in pairs]
        covered = sum(p != 'abstain' for p, _ in predictions)
        errors = sum(p != 'abstain' and p != y for p, y in predictions)
        losses[name] = [realized_loss(config, p, y) for p, y in predictions]
        result['metrics']['jev' if name == 'choice' else name] = {'coverage': covered / len(pairs) if pairs else None,
            'coverage_of_all_assigned': covered / count if count else None,
            'errors': errors, 'conditional_error_rate': errors / covered if covered else None,
            'conditional_error_wilson95': wilson(errors, covered),
            'mean_loss': sum(losses[name]) / len(pairs) if pairs else None}
    differences = [a-b for a,b in zip(losses['choice'], losses['baseline'])]
    mean = sum(differences)/len(differences) if differences else None
    # Distribution-free bounded paired mean interval (Hoeffding), assuming independent examples.
    matrix = config['mathematical'].get('loss_matrix')
    bound = max(value for row in matrix.values() for value in row.values()) if matrix is not None else max(config['mathematical']['error_loss'], config['mathematical']['abstain_loss'])
    half = 2*bound*math.sqrt(math.log(40)/(2*len(pairs))) if pairs else None
    result['paired_loss_difference'] = {'jev_minus_baseline': mean,
        'hoeffding95': [max(-bound, mean-half), min(bound, mean+half)] if pairs else None,
        'assumption': 'Independent representative paired examples; repeated entities may invalidate interval.'}
    costs = [o.get('actual_cost') for _, o in pairs]
    currencies = {o.get('cost_currency') for _,o in pairs}
    if costs and all(c is not None for c in costs) and len(currencies) == 1:
        for cost in costs: number(cost, 'actual_cost')
        result['cost'] = {'total': sum(costs), 'currency': next(iter(currencies))}
    return result


@contextmanager
def experiment_lock(ledger):
    """Nonblocking process lock across reservation, provider call and append."""
    target = Path(ledger).resolve()
    target.parent.mkdir(parents=True, exist_ok=True)
    descriptor = os.open(str(target) + '.run.lock', os.O_RDWR | os.O_CREAT, 0o600)
    with os.fdopen(descriptor, 'r+') as lock:
        os.fchmod(lock.fileno(), 0o600)
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise ValueError('experiment already running; no provider call made') from None
        yield


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['validate', 'run', 'outcome', 'report'])
    parser.add_argument('--registry', required=True)
    parser.add_argument('--examples')
    parser.add_argument('--ledger')
    parser.add_argument('--outcome')
    parser.add_argument('--decision-id')
    parser.add_argument('--live', action='store_true')
    parser.add_argument('--allow-nonpublic', action='store_true')
    args = parser.parse_args(argv)
    try:
        config = validate_registry(json.loads(Path(args.registry).read_text()))
        if args.command == 'validate':
            output = {'valid': True, 'config_hash': digest(config)}
        elif args.command == 'run':
            if not args.examples or not args.ledger: raise ValueError('--examples and --ledger required')
            examples = [json.loads(s) for s in Path(args.examples).read_text().splitlines() if s.strip()]
            if len(examples) > config['mathematical']['budget']['max_calls']: raise ValueError('call budget exceeded')
            for example in examples:
                validate_example(example, config)
                if args.live and example['data_class'] == 'nonpublic' and not args.allow_nonpublic:
                    raise ValueError('nonpublic transmission requires explicit --allow-nonpublic')
            with experiment_lock(args.ledger):
                existing = read_records(args.ledger)
                consumed = len({r['id'] for r in existing if r['kind'] in ('assignment', 'decision') and r.get('config_hash') == digest(config) and r.get('mode') == 'live'})
                new_ids = {digest({'config_hash': digest(config), 'input_hash': digest(e), 'mode': 'live'}) for e in examples} - {r['id'] for r in existing}
                if args.live and consumed + len(new_ids) > config['mathematical']['budget']['max_calls']:
                    raise ValueError('experiment ledger call budget exceeded')
                assigned_ids = {r['id'] for r in existing if r['kind'] == 'assignment'}
                completed_ids = {r['id'] for r in existing if r['kind'] == 'decision'}
                requested_ids = {digest({'config_hash': digest(config), 'input_hash': digest(e), 'mode': 'live' if args.live else 'offline'}) for e in examples}
                if requested_ids & (assigned_ids - completed_ids):
                    raise ValueError('pending assignment has unknown prior call outcome; implicit retry refused')
                output = []
                for example in examples:
                    identity = {'config_hash': digest(config), 'input_hash': digest(example), 'mode': 'live' if args.live else 'offline'}
                    assignment = {'kind': 'assignment', 'id': digest(identity), **identity,
                                  'state_hash': digest(example['state']), 'split': example['split'],
                                  'example_id': example['id'], 'dataset_version': example['dataset_version']}
                    append_record(args.ledger, assignment)
                for example in examples:
                    identity = {'config_hash': digest(config), 'input_hash': digest(example), 'mode': 'live' if args.live else 'offline'}
                    prior = next((r for r in existing if r['kind'] == 'decision' and r['id'] == digest(identity)), None)
                    decision = prior or decide(config, example, live=args.live, allow_nonpublic=args.allow_nonpublic)
                    if prior is None:
                        append_record(args.ledger, decision)
                        existing.append(decision)
                    output.append({'id': decision['id'], 'choice': decision['choice'], 'reason': decision['reason'], 'reused': prior is not None})
        elif args.command == 'outcome':
            if not args.ledger or not args.outcome or not args.decision_id: raise ValueError('ledger, outcome and decision-id required')
            outcome = json.loads(Path(args.outcome).read_text())
            if outcome.get('config_hash') != digest(config): raise ValueError('outcome does not match supplied registry')
            output = join_outcome(args.ledger, args.decision_id, outcome)
        else:
            if not args.ledger: raise ValueError('--ledger required')
            output = report(read_records(args.ledger), config)
        print(json.dumps(output, indent=2, allow_nan=False))
        return 0
    except (ValueError, KeyError, TypeError, OSError) as error:
        print(f'decision-lab: {error}', file=sys.stderr)
        return 2

if __name__ == '__main__':
    raise SystemExit(main())

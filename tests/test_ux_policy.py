import copy
import fcntl
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import ux_policy as policy
from ux_learning import Invalid, package, record, wilson


class PolicyTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.map_path = self.root / 'map.json'
        self.map = {'schema_version': 1, 'package_id': 'test', 'revision': '1', 'title': 'test', 'cost_unit': 'seconds',
                    'states': [{'id': item, 'label': item} for item in ('s', 'm', 'g')], 'edges': []}
        for key, start, end, cost, forbidden in [('a', 's', 'g', 3, False), ('b', 's', 'm', 1, False), ('c', 'm', 'g', 1, False), ('danger', 's', 'g', 0, True)]:
            self.map['edges'].append({'id': key, 'from': start, 'to': end, 'cost': cost, 'forbidden': forbidden, 'status': 'observed', 'action': key, 'postcondition': 'verified'})
        self.map_path.write_text(json.dumps(self.map))
        self.value, self.digest = package(self.map_path)
        self.state_path = self.root / 'state.json'

    def data(self, events):
        items = []
        for event_id, action, success, cost in events:
            evidence = self.root / (event_id + '.txt')
            evidence.write_text(event_id)
            items.append({'id': event_id, 'context': 'dialog', 'action': action, 'eligible': ['a', 'b'], 'success': success, 'cost': cost,
                          'evidence_path': str(evidence), 'evidence_sha256': hashlib.sha256(evidence.read_bytes()).hexdigest()})
        return {'schema_version': 1, 'binding': policy.binding(self.value, self.digest), 'reward': {'cost_weight': 0.5, 'cost_scale': 10}, 'events': items}

    def cli(self, *args, expected=0):
        command = [sys.executable, str(Path(policy.__file__)), *args]
        result = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(result.returncode, expected, result.stderr)
        return json.loads(result.stdout if expected == 0 else result.stderr)

    def run_training(self, data):
        path = self.root / 'replay.json'
        path.write_text(json.dumps(data))
        return self.cli('train', str(self.map_path), '--state', str(self.state_path), '--replay', str(path))

    def choice(self, permits=('a', 'b')):
        args = ['recommend', str(self.map_path), '--state', str(self.state_path), '--context', 'dialog', '--min-trials', '1']
        for action in permits:
            args += ['--permit', action]
        return self.cli(*args)

    def stats(self, successes=20, attempts=20):
        return {'edges': {edge['id']: {'successes': successes, 'attempts': attempts, 'failures': attempts-successes, 'wilson_95': wilson(successes, attempts)} for edge in self.value['edges']}}

    def test_shortest_path_masks_forbidden_and_nonpermitted(self):
        with patch.object(policy, 'status', return_value=self.stats()):
            route = policy.plan(self.value, self.digest, '', 's', 'g', ['a', 'b', 'c', 'danger'], 5)
            self.assertEqual(route['edges'], ['b', 'c'])
            route = policy.plan(self.value, self.digest, '', 's', 'g', ['a', 'danger'], 5)
            self.assertEqual(route['edges'], ['a'])
            self.assertFalse(policy.plan(self.value, self.digest, '', 's', 'g', ['danger'], 5)['reachable'])

    def test_low_evidence_and_all_failures_abstain(self):
        for successes, attempts in [(1, 1), (0, 20)]:
            with patch.object(policy, 'status', return_value=self.stats(successes, attempts)):
                self.assertFalse(policy.plan(self.value, self.digest, '', 's', 'g', ['a'], 5)['reachable'])

    def test_outcomes_change_retry_route_only_with_explicit_assumption(self):
        stats = self.stats()
        stats['edges']['b'] = {'successes': 1, 'attempts': 20, 'failures': 19, 'wilson_95': wilson(1, 20)}
        with patch.object(policy, 'status', return_value=stats):
            self.assertEqual(policy.plan(self.value, self.digest, '', 's', 'g', ['a', 'b', 'c'], 5)['edges'], ['b', 'c'])
            self.assertEqual(policy.plan(self.value, self.digest, '', 's', 'g', ['a', 'b', 'c'], 5, True)['edges'], ['a'])

    def test_learning_changes_new_process_recommendation(self):
        self.run_training(self.data([('one', 'a', True, 0), ('two', 'b', True, 2)]))
        self.assertEqual(self.choice()['action'], 'a')
        self.run_training(self.data([('three', 'a', False, 10), ('four', 'a', False, 10)]))
        self.assertEqual(self.choice()['action'], 'b')
        self.assertIsNone(self.choice(())['action'])
        self.assertIsNone(self.choice(('a',))['action'])

    def test_nonpositive_arms_abstain_at_free_inaction_baseline(self):
        self.run_training(self.data([('one', 'a', False, 2), ('two', 'b', False, 0)]))
        decision = self.choice()
        self.assertIsNone(decision['action'])
        self.assertEqual(decision['reason'], 'no_positive_reward')
        self.assertEqual(decision['best_mean_reward'], 0)
        self.assertEqual(decision['abstain_reward'], 0)
        decision = self.choice(('a',))
        self.assertIsNone(decision['action'])
        self.assertLess(decision['best_mean_reward'], 0)

    def test_deterministic_tie(self):
        self.run_training(self.data([('one', 'b', True, 0), ('two', 'a', True, 0)]))
        self.assertEqual(self.choice(('b', 'a'))['action'], 'a')

    def test_stale_policy_bytes_rejected(self):
        self.run_training(self.data([('one', 'a', True, 0)]))
        self.map_path.write_text(json.dumps(self.map, indent=2))
        result = self.cli('recommend', str(self.map_path), '--state', str(self.state_path), '--context', 'dialog', '--min-trials', '1', expected=2)
        self.assertIn('stale policy', result['error'])

    def test_holdout_disjoint_and_nonmutating(self):
        training = self.data([('one', 'a', True, 0)])
        self.run_training(training)
        state = policy.load_state(self.state_path, self.value, self.digest)
        with self.assertRaises(Invalid):
            policy.evaluate(state, self.value, training, 1)
        holdout = self.data([('other', 'a', False, 0), ('third', 'b', True, 0)])
        before = self.state_path.read_bytes()
        result = policy.evaluate(state, self.value, holdout, 1)
        self.assertEqual(result['matched_events'], 1)
        self.assertEqual(result['matched_mean_reward'], 0)
        self.assertEqual(before, self.state_path.read_bytes())
        holdout['events'][0]['evidence_sha256'] = training['events'][0]['evidence_sha256']
        with self.assertRaises(Invalid):
            policy.evaluate(state, self.value, holdout, 1)

    def test_bad_replays_fail_closed(self):
        original = self.data([('one', 'a', True, 0)])
        mutations = [('success', 1), ('cost', -1), ('cost', float('nan')), ('cost', float('inf')), ('action', 'danger'), ('evidence_sha256', '0'*64), ('eligible', ['a', 'a'])]
        for field, bad in mutations:
            data = copy.deepcopy(original)
            data['events'][0][field] = bad
            path = self.root / 'bad.json'
            path.write_text(json.dumps(data))
            with self.assertRaises((Invalid, ValueError)):
                policy.replay(path, self.value, self.digest)

    def test_duplicate_evidence_not_extra_training(self):
        original = self.data([('one', 'a', True, 0)])
        self.run_training(original)
        duplicate = copy.deepcopy(original)
        duplicate['events'][0]['id'] = 'different'
        with self.assertRaises(Invalid):
            policy.train(self.state_path, self.value, self.digest, duplicate)

    def test_tampered_counts_rejected(self):
        self.run_training(self.data([('one', 'a', True, 0)]))
        state = json.loads(self.state_path.read_text())
        state['contexts']['dialog']['a']['count'] = 999
        self.state_path.write_text(json.dumps(state))
        with self.assertRaises(Invalid):
            policy.load_state(self.state_path, self.value, self.digest)

    def test_real_receipt_store_revalidates_evidence(self):
        evidence = self.root / 'proof.txt'
        evidence.write_text('synthetic successful transition')
        receipt = {'schema_version': 1, 'id': 'receipt-1', 'package_id': 'test', 'revision': '1',
                   'edge_id': 'a', 'outcome': 'success', 'observed_at': '2020-01-01T00:00:00Z',
                   'evidence_path': str(evidence), 'evidence_sha256': hashlib.sha256(evidence.read_bytes()).hexdigest()}
        receipt_path = self.root / 'receipt.json'
        receipt_path.write_text(json.dumps(receipt))
        store = self.root / 'receipts'
        record(self.value, self.digest, receipt_path, store)
        self.assertTrue(policy.plan(self.value, self.digest, store, 's', 'g', ['a'], 1)['reachable'])
        evidence.write_text('changed')
        self.assertFalse(policy.plan(self.value, self.digest, store, 's', 'g', ['a'], 1)['reachable'])

    def test_concurrent_writer_fails_explicitly_without_loss(self):
        self.run_training(self.data([('one', 'a', True, 0)]))
        before = self.state_path.read_bytes()
        pending = self.root / 'pending.json'
        pending.write_text(json.dumps(self.data([('two', 'b', True, 0)])))
        with open(str(self.state_path) + '.lock', 'r+') as lock:
            fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
            result = self.cli('train', str(self.map_path), '--state', str(self.state_path), '--replay', str(pending), expected=2)
            self.assertIn('another training writer', result['error'])
        self.assertEqual(before, self.state_path.read_bytes())
        result = self.cli('train', str(self.map_path), '--state', str(self.state_path), '--replay', str(pending))
        self.assertEqual(result['total_events'], 2)

    def test_changed_or_missing_training_evidence_rejected(self):
        self.run_training(self.data([('one', 'a', True, 0)]))
        evidence = self.root / 'one.txt'
        evidence.write_text('changed')
        with self.assertRaises(Invalid):
            policy.load_state(self.state_path, self.value, self.digest)
        evidence.unlink()
        with self.assertRaises(Invalid):
            policy.load_state(self.state_path, self.value, self.digest)

    def test_tampered_mean_rejected(self):
        self.run_training(self.data([('one', 'a', True, 0)]))
        state = json.loads(self.state_path.read_text())
        state['contexts']['dialog']['a']['mean'] = 0.123
        self.state_path.write_text(json.dumps(state))
        with self.assertRaises(Invalid):
            policy.load_state(self.state_path, self.value, self.digest)

    def test_documented_edges_remain_ineligible(self):
        self.value['edges'][0]['status'] = 'documented'
        self.assertEqual(policy.eligible(self.value, ['a', 'danger']), {})


if __name__ == '__main__':
    unittest.main()

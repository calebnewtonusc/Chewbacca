import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import subprocess
import sys
import unittest

SPEC = importlib.util.spec_from_file_location('ux_learning', Path(__file__).resolve().parents[1] / 'tools/ux_learning.py')
ux = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ux)


class LearningTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.path = self.root / 'package.json'
        self.value = {'schema_version': 1, 'package_id': 'sample', 'revision': '1', 'title': 'Sample',
                      'cost_unit': 'relative_effort', 'states': [{'id': key, 'label': key} for key in ('a', 'b', 'c')],
                      'edges': [self.edge('ab', 'a', 'b'), self.edge('ba', 'b', 'a'), self.edge('bc', 'b', 'c')]}
        self.save()

    def edge(self, key, source, target):
        return {'id': key, 'from': source, 'to': target, 'action': 'Click <control>',
                'postcondition': 'Target visible', 'status': 'observed', 'cost': 1, 'forbidden': False}

    def save(self):
        self.path.write_text(json.dumps(self.value))

    def receipt(self, key='receipt-1', outcome='success'):
        evidence = self.root / (key + '.txt')
        evidence.write_text('local screenshot description ' + key)
        item = {'schema_version': 1, 'id': key, 'package_id': 'sample', 'revision': '1', 'edge_id': 'ab',
                'outcome': outcome, 'observed_at': '2025-01-01T00:00:00Z',
                'evidence_path': evidence.name, 'evidence_sha256': hashlib.sha256(evidence.read_bytes()).hexdigest()}
        path = self.root / (key + '.json')
        path.write_text(json.dumps(item))
        return path, item

    def test_installed_symlink(self):
        link = self.root / 'ux-learning'
        link.symlink_to(Path(__file__).resolve().parents[1] / 'bin/ux-learning')
        result = subprocess.run([sys.executable, str(link), 'validate', str(self.path)],
                                cwd=self.root, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(json.loads(result.stdout)['valid'])

    def test_reused_and_conflicting_evidence(self):
        value, digest = ux.package(self.path)
        path, item = self.receipt()
        store = self.root / 'private'
        ux.record(value, digest, path, store)
        item['id'] = 'receipt-2'
        path.write_text(json.dumps(item))
        ux.record(value, digest, path, store)
        result = ux.status(value, digest, store)
        self.assertEqual(result['edges']['ab']['attempts'], 1)
        self.assertEqual(result['reused_evidence_receipts'], 1)
        item['id'] = 'receipt-3'
        item['outcome'] = 'failure'
        path.write_text(json.dumps(item))
        with self.assertRaises(ux.Invalid):
            ux.record(value, digest, path, store)

    def test_graph_cycles_and_unreachable(self):
        self.assertEqual(ux.route(self.value, 'a', 'c')['edges'], ['ab', 'bc'])
        self.assertFalse(ux.route(self.value, 'c', 'a')['reachable'])
        self.assertEqual(ux.route(self.value, 'a', 'a')['edges'], [])
        self.value['edges'][0]['cost'] = 0
        self.value['edges'][1]['cost'] = 0
        self.assertTrue(ux.route(self.value, 'a', 'c')['reachable'])
        self.assertFalse(ux.route(self.value, 'a', 'c', excluded=['ab'])['reachable'])
        with self.assertRaises(ux.Invalid):
            ux.route(self.value, 'a', 'missing')
        with self.assertRaises(ux.Invalid):
            ux.route(self.value, 'a', 'c', excluded=['missing'])

    def test_documented_and_forbidden_edges(self):
        self.value['edges'][2]['status'] = 'documented'
        self.assertFalse(ux.route(self.value, 'a', 'c')['reachable'])
        self.assertTrue(ux.route(self.value, 'a', 'c', True)['tentative'])
        self.value['edges'][2]['forbidden'] = True
        self.assertFalse(ux.route(self.value, 'a', 'c', True)['reachable'])

    def test_invalid_packages(self):
        original = copy.deepcopy(self.value)
        for cost in (-1, float('nan'), float('inf'), True, '1', 10 ** 1000):
            self.value = copy.deepcopy(original)
            self.value['edges'][0]['cost'] = cost
            self.save()
            with self.assertRaises((ux.Invalid, ValueError)):
                ux.package(self.path)
        for field, value in [('schema_version', 2), ('schema_version', True), ('cost_unit', 'probability'),
                             ('package_id', '/tmp/a'), ('package_id', 'https://example.com'), ('revision', '../x')]:
            self.value = copy.deepcopy(original)
            self.value[field] = value
            self.save()
            with self.assertRaises(ux.Invalid):
                ux.package(self.path)
        for mutation in ('duplicate_state', 'duplicate_edge', 'endpoint'):
            self.value = copy.deepcopy(original)
            if mutation == 'duplicate_state':
                self.value['states'].append(self.value['states'][0])
            elif mutation == 'duplicate_edge':
                self.value['edges'].append(self.value['edges'][0])
            else:
                self.value['edges'][0]['to'] = 'missing'
            self.save()
            with self.assertRaises(ux.Invalid):
                ux.package(self.path)
        self.path.write_text('{"schema_version":1,"schema_version":2}')
        with self.assertRaises(ux.Invalid):
            ux.package(self.path)

    def test_record_duplicates_and_exact_revision(self):
        value, digest = ux.package(self.path)
        path, item = self.receipt()
        store = self.root / 'private'
        self.assertTrue(ux.record(value, digest, path, store)['recorded'])
        self.assertTrue(ux.record(value, digest, path, store)['duplicate'])
        self.assertEqual(ux.status(value, digest, store)['edges']['ab']['attempts'], 1)
        item['outcome'] = 'failure'
        path.write_text(json.dumps(item))
        with self.assertRaises(ux.Invalid):
            ux.record(value, digest, path, store)
        self.assertEqual(ux.status(value, 'different-bytes', store)['edges']['ab']['attempts'], 0)
        item['revision'] = '0'
        path.write_text(json.dumps(item))
        with self.assertRaises(ux.Invalid):
            ux.record(value, digest, path, store)

    def test_missing_forged_changed_evidence(self):
        value, digest = ux.package(self.path)
        path, item = self.receipt()
        store = self.root / 'private'
        item['evidence_sha256'] = '0' * 64
        path.write_text(json.dumps(item))
        with self.assertRaises(ux.Invalid):
            ux.record(value, digest, path, store)
        path, item = self.receipt()
        ux.record(value, digest, path, store)
        (self.root / item['evidence_path']).write_text('changed')
        result = ux.status(value, digest, store)
        self.assertEqual(result['edges']['ab']['attempts'], 0)
        self.assertEqual(result['invalid_evidence_receipts'], 1)
        (self.root / item['evidence_path']).unlink()
        with self.assertRaises((OSError, ux.Invalid)):
            ux.record(value, digest, path, store)

    def test_no_mastery_and_read_only_status(self):
        value, digest = ux.package(self.path)
        store = self.root / 'private'
        self.assertIsNone(ux.status(value, digest, store)['edges']['ab']['wilson_95'])
        self.assertFalse(store.exists())
        path, _ = self.receipt(outcome='failure')
        ux.record(value, digest, path, store)
        result = ux.status(value, digest, store)
        self.assertEqual(result['mastery'], 'not-assessed')
        self.assertEqual(result['edges']['ab']['readiness'], 'not-demonstrated')
        self.assertEqual(result['edges']['ab']['failures'], 1)
        path, _ = self.receipt('receipt-2')
        ux.record(value, digest, path, store)
        result = ux.status(value, digest, store)
        self.assertEqual(result['edges']['ab']['readiness'], 'observed-success')
        self.assertLess(result['edges']['ab']['wilson_95'][0], 0.5)


if __name__ == '__main__':
    unittest.main()

"""Private task persistence and concurrent cross-runtime CLI access, without models."""
import importlib.util
import json
import os
from pathlib import Path
import sqlite3
import stat
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('work_ledger', ROOT / 'tools/work_ledger.py')
ledger = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ledger)


class WorkLedgerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.scope = self.root / 'workspace'
        self.scope.mkdir()
        env = patch.dict(os.environ, {'CHEWBACCA_HOME': str(self.root / 'private')})
        env.start()
        self.addCleanup(env.stop)

    def add(self, title='Finish research', key='request-1'):
        return ledger.add(self.scope, title, key, owner='worker', next_action='Read source methods')

    def cli(self, *args):
        return subprocess.run([sys.executable, str(ROOT / 'bin/work-ledger'), *args,
                               '--scope', str(self.scope)], capture_output=True, text=True, timeout=15)

    def test_context_and_list_do_not_create_storage(self):
        self.assertEqual(ledger.context_for(self.scope), '')
        self.assertEqual(ledger.list_tasks(self.scope), [])
        self.assertFalse(ledger.database_path().parent.exists())
        result = self.cli('context')
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, '')
        self.assertFalse(ledger.database_path().parent.exists())

    def test_new_tasks_keep_prior_commitments_and_idempotency(self):
        first = self.add()
        ledger.update(self.scope, first['task']['id'], status='active')
        second = self.add('New request', 'request-2')
        retry = self.add()
        self.assertFalse(retry['created'])
        self.assertEqual(retry['task']['status'], 'active')
        self.assertNotEqual(first['task']['id'], second['task']['id'])
        self.assertEqual(len(ledger.list_tasks(self.scope)), 2)
        with self.assertRaises(ValueError):
            self.add('Different task', 'request-1')
        self.assertEqual(len(ledger.list_tasks(self.scope)), 2)

    def test_exact_scope_isolation_and_symlink_canonicalization(self):
        task = self.add()['task']
        other = self.root / 'other'
        other.mkdir()
        self.assertEqual(ledger.context_for(other), '')
        self.assertEqual(ledger.list_tasks(self.scope.parent), [])
        with self.assertRaises(ValueError):
            ledger.update(other, task['id'], status='active')
        second = ledger.add(other, 'Other scope', 'request-1')
        self.assertNotEqual(task['id'], second['task']['id'])
        alias = self.root / 'alias'
        alias.symlink_to(self.scope, target_is_directory=True)
        self.assertEqual(ledger.list_tasks(alias), ledger.list_tasks(self.scope))

    def test_terminal_validation_and_reopening(self):
        task_id = self.add()['task']['id']
        for status, fields in [('done', {}), ('done', {'evidence': ' '}),
                               ('cancelled', {}), ('cancelled', {'reason': ''})]:
            with self.subTest(status=status, fields=fields), self.assertRaises(ValueError):
                ledger.update(self.scope, task_id, status=status, **fields)
        self.assertEqual(ledger.list_tasks(self.scope)[0]['status'], 'queued')
        ledger.update(self.scope, task_id, status='done', evidence='outputs/report.md checked')
        self.assertEqual(ledger.list_tasks(self.scope), [])
        self.assertEqual(len(ledger.list_tasks(self.scope, True)), 1)
        with self.assertRaises(ValueError):
            ledger.update(self.scope, task_id, evidence='')
        ledger.update(self.scope, task_id, status='active')
        with self.assertRaises(ValueError):
            ledger.update(self.scope, task_id, status='done')
        ledger.update(self.scope, task_id, status='cancelled', reason='User explicitly replaced this task')
        with self.assertRaises(ValueError):
            ledger.update(self.scope, task_id, reason='')
        self.assertEqual(ledger.context_for(self.scope), '')

    def test_actual_filesystem_case_aliases_share_scope(self):
        directory = self.root / 'WorkspaceCase'
        directory.mkdir()
        alternate = self.root / 'workspacecase'
        if not alternate.exists() or not os.path.samefile(directory, alternate):
            self.skipTest('filesystem distinguishes case variants')
        created = ledger.add(directory, 'Same workspace', 'case-key')
        repeated = ledger.add(alternate, 'Same workspace', 'case-key')
        self.assertFalse(repeated['created'])
        self.assertEqual(created['task']['id'], repeated['task']['id'])
        self.assertEqual(ledger.context_for(directory), ledger.context_for(alternate))
        ledger.update(alternate, created['task']['id'], status='active')
        self.assertEqual(ledger.list_tasks(directory)[0]['status'], 'active')

    def test_case_sensitive_existing_names_remain_distinct(self):
        directory = self.root / 'DistinctCase'
        directory.mkdir()
        alternate = self.root / 'distinctcase'
        if alternate.exists():
            self.skipTest('filesystem aliases case variants')
        alternate.mkdir()
        self.assertNotEqual(ledger.scope_path(directory), ledger.scope_path(alternate))
        ledger.add(directory, 'First', 'key')
        ledger.add(alternate, 'Second', 'key')
        self.assertEqual(ledger.list_tasks(directory)[0]['title'], 'First')
        self.assertEqual(ledger.list_tasks(alternate)[0]['title'], 'Second')

    def test_cli_restart_persistence_and_mode(self):
        added = self.cli('add', '--title', 'Persistent task', '--source-key', 'restart')
        self.assertEqual(added.returncode, 0, added.stderr)
        task_id = json.loads(added.stdout)['task']['id']
        refused = self.cli('update', '--id', task_id, '--status', 'done')
        self.assertEqual(refused.returncode, 2)
        done = self.cli('update', '--id', task_id, '--status', 'done', '--evidence', 'verified output')
        self.assertEqual(done.returncode, 0, done.stderr)
        listed = json.loads(self.cli('list', '--all').stdout)
        self.assertEqual(listed[0]['status'], 'done')
        self.assertEqual(listed[0]['id'], task_id)
        self.assertEqual(stat.S_IMODE(ledger.database_path().stat().st_mode), 0o600)

    def test_simultaneous_cli_adds_preserve_all_tasks_and_deduplicate(self):
        command = [sys.executable, str(ROOT / 'bin/work-ledger'), 'add', '--scope', str(self.scope)]
        pairs = [(f'task-{i}', f'key-{i}') for i in range(8)] + [('same', 'shared')] * 4
        children = [subprocess.Popen(command + ['--title', title, '--source-key', key],
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                    for title, key in pairs]
        outputs = [child.communicate(timeout=15) for child in children]
        for child, (stdout, stderr) in zip(children, outputs):
            self.assertEqual(child.returncode, 0, stderr)
            self.assertIn('task', json.loads(stdout))
        self.assertEqual(len(ledger.list_tasks(self.scope)), 9)
        shared = [json.loads(stdout) for stdout, _ in outputs if json.loads(stdout)['task']['source_key'] == 'shared']
        self.assertEqual(sum(row['created'] for row in shared), 1)
        self.assertEqual(len({row['task']['id'] for row in shared}), 1)

    def test_context_is_bounded_and_excludes_private_fields(self):
        for i in range(15):
            task = ledger.add(self.scope, 'Title ' + str(i) + 'x' * 200, str(i), next_action='a' * 1000)['task']
            ledger.update(self.scope, task['id'], evidence='PRIVATE_EVIDENCE', reason='PRIVATE_REASON', owner='PRIVATE_OWNER')
        before = ledger.database_path().read_bytes()
        context = ledger.context_for(self.scope)
        self.assertLess(len(context), 5500)
        self.assertEqual(context.count('- [queued]'), 12)
        self.assertIn('3 more open tasks', context)
        for private in ('PRIVATE_EVIDENCE', 'PRIVATE_REASON', 'PRIVATE_OWNER'):
            self.assertNotIn(private, context)
        self.assertEqual(ledger.database_path().read_bytes(), before)

    def test_invalid_fields_rollback_and_unavailable_context_reports_gap(self):
        task = self.add()['task']
        for changes in ({'status': 'erased'}, {'next_action': 'x' * 1001}, {'title': 'rewrite'}):
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                ledger.update(self.scope, task['id'], **changes)
        self.assertEqual(ledger.list_tasks(self.scope)[0], task)
        with patch.object(ledger.sqlite3, 'connect', side_effect=sqlite3.OperationalError('unavailable')):
            self.assertIn('earlier commitments may be missing', ledger.context_for(self.scope))


if __name__ == '__main__':
    unittest.main()

"""Shared context and native entry events must load the correct workspace ledger."""
import contextlib
import io
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import agent_context
import codex_hooks
import work_ledger


class WorkLedgerContextTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.workspace = self.root / 'selected workspace'
        self.other = self.root / 'other workspace'
        self.brain = self.root / 'fixture brain'
        for path in (self.workspace, self.other, self.brain):
            path.mkdir()
        self.enterContext(patch.dict(os.environ, {
            'CHEWBACCA_HOME': str(self.root / 'shared'),
            'CODEX_HOME': str(self.root / 'codex'),
        }))
        self.enterContext(patch.object(agent_context, 'read_sources', return_value=0))
        self.enterContext(patch.object(codex_hooks.context, 'read_sources', return_value=0))
        self.enterContext(patch.object(codex_hooks.context, 'brain_root', return_value=self.brain))
        self.enterContext(patch.object(codex_hooks, 'turn_state', return_value={}))
        self.enterContext(patch.object(codex_hooks, 'prompt_context', return_value=''))
        self.enterContext(patch.object(codex_hooks, 'shared_hook', return_value=''))

    def seed(self):
        work_ledger.add(self.workspace, 'OPEN_SELECTED_CANARY', 'selected',
                        next_action='REMAINING_ACTION_CANARY')
        work_ledger.add(self.other, 'OTHER_WORKSPACE_CANARY', 'other')
        done = work_ledger.add(self.workspace, 'DONE_TASK_CANARY', 'done')['task']
        work_ledger.update(self.workspace, done['id'], status='done', evidence='fixture verified')

    def shared_read(self):
        output = io.StringIO()
        with patch.object(sys, 'argv', ['agent-context', 'read', '--brain-dir', str(self.brain)]), \
                patch.object(os, 'getcwd', return_value=str(self.workspace)), \
                contextlib.redirect_stdout(output):
            result = agent_context.main()
        self.assertEqual(result, 0)
        return output.getvalue()

    def hook_context(self, event):
        with patch.object(os, 'getcwd', return_value=str(self.other)):
            result = codex_hooks.dispatch({'hook_event_name': event, 'cwd': str(self.workspace)})
        return result.get('hookSpecificOutput', {}).get('additionalContext', '')

    def assert_selected(self, output):
        self.assertEqual(output.count('OPEN_SELECTED_CANARY'), 1)
        self.assertIn('REMAINING_ACTION_CANARY', output)
        self.assertNotIn('OTHER_WORKSPACE_CANARY', output)
        self.assertNotIn('DONE_TASK_CANARY', output)

    def test_shared_read_uses_process_workspace_and_keeps_open_tasks(self):
        self.seed()
        self.assert_selected(self.shared_read())

    def test_session_start_uses_payload_workspace_not_process_workspace(self):
        self.seed()
        self.assert_selected(self.hook_context('SessionStart'))

    def test_prompt_submit_refreshes_ledger_after_status_change(self):
        self.seed()
        self.assert_selected(self.hook_context('UserPromptSubmit'))
        current = work_ledger.list_tasks(self.workspace)[0]
        work_ledger.update(self.workspace, current['id'], status='done', evidence='fixture verified')
        output = self.hook_context('UserPromptSubmit')
        self.assertNotIn('OPEN_SELECTED_CANARY', output)
        self.assertNotIn('OTHER_WORKSPACE_CANARY', output)

    def test_context_reads_do_not_create_missing_ledger(self):
        self.shared_read()
        self.hook_context('SessionStart')
        self.hook_context('UserPromptSubmit')
        self.assertFalse(work_ledger.database_path().exists())

    def test_corrupt_ledger_reports_gap_without_breaking_context(self):
        database = work_ledger.database_path()
        database.parent.mkdir()
        database.write_bytes(b'not a sqlite database')
        for output in (self.shared_read(), self.hook_context('SessionStart'),
                       self.hook_context('UserPromptSubmit')):
            self.assertIn('Shared work ledger is unavailable', output)
        self.assertEqual(database.read_bytes(), b'not a sqlite database')


if __name__ == '__main__':
    unittest.main()

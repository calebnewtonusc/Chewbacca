"""Completed calls must not leave stale baselines for a later identical call."""
import sys
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import codex_hooks as hooks


class BaselineTests(unittest.TestCase):
    def test_completed_read_does_not_attribute_later_external_edit(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(
                hooks.context, 'codex_home', return_value=Path(directory)):
            base = {'session_id': 'repeated-read', 'tool_name': 'exec_command',
                    'tool_input': {'cmd': 'git status'}}
            with patch.object(hooks, 'review_snapshots', side_effect=[
                    {'/repo': 'a'}, {'/repo': 'a'}, {'/repo': 'b'}, {'/repo': 'b'}]):
                for event in ['PreToolUse', 'PostToolUse'] * 2:
                    state = hooks.turn_state(dict(base, hook_event_name=event))
            self.assertEqual(state['review_required'], [])
            self.assertEqual(state['review_before'], {})
            self.assertEqual(state['review_inflight'], {})

    def test_denied_call_releases_baseline_without_claiming_a_write(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(
                hooks.context, 'codex_home', return_value=Path(directory)):
            base = {'session_id': 'denied', 'tool_name': 'exec_command',
                    'cwd': directory, 'tool_input': {'cmd': 'blocked'}}
            with patch.object(hooks, 'review_snapshots', return_value={'/repo': 'a'}), \
                    patch.object(hooks, 'shared_hook', side_effect=hooks.HookDenied('Denied')):
                result = hooks.dispatch(dict(base, hook_event_name='PreToolUse'))
            self.assertEqual(result['hookSpecificOutput']['permissionDecision'], 'deny')
            state = hooks.turn_state(dict(base, hook_event_name='Stop'))
            self.assertEqual(state['review_before'], {})
            self.assertEqual(state['review_inflight'], {})
            self.assertEqual(state.get('review_required', []), [])

    def test_overlapping_calls_keep_baseline_until_last_completion(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(
                hooks.context, 'codex_home', return_value=Path(directory)):
            base = {'session_id': 'overlap', 'tool_name': 'exec_command',
                    'tool_input': {'cmd': 'same'}}
            with patch.object(hooks, 'review_snapshots', side_effect=[
                    {'/repo': 'a'}, {'/repo': 'b'}, {'/repo': 'b'}, {'/repo': 'b'}]):
                for event in ['PreToolUse', 'PreToolUse', 'PostToolUse', 'PostToolUse']:
                    state = hooks.turn_state(dict(base, hook_event_name=event))
            self.assertEqual(state['review_required'], ['/repo'])
            self.assertEqual(state['review_before'], {})


if __name__ == '__main__':
    unittest.main()

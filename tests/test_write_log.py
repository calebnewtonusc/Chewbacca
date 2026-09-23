"""Offline native-hook regression fixtures; no model calls or user state."""
import json
import shutil
import os
from pathlib import Path
import subprocess
import tempfile
import time
import sys
from unittest.mock import patch
import unittest

ROOT = Path(__file__).resolve().parents[1]


class WriteLogTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.folder = Path(self.temp.name).resolve()
        self.repo = self.folder / 'repository'
        self.repo.mkdir()
        self.outside = self.folder / 'projectless'
        self.outside.mkdir()
        self.env = dict(os.environ, HOME=str(self.folder / 'home'),
                        CHEWBACCA_HOME=str(self.folder / 'shared'),
                        CHEWBACCA_SESSION_STATE=str(self.folder / 'state'),
                        CHEWBACCA_WRITE_LOG=str(self.folder / 'custom.tsv'),
                        TMPDIR=str(self.folder))
        self.git('init')
        self.policy = self.repo / 'skills/example.md'
        self.policy.parent.mkdir()
        self.policy.write_text('original')
        self.git('add', '.')
        self.git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-m', 'fixture')

    def git(self, *args):
        return subprocess.run(['git', *args], cwd=self.repo, env=self.env,
                              capture_output=True, check=True)

    def hook(self, event, cwd=None, data=None, sid='fixture', call=None):
        payload = {'hook_event_name': event, 'session_id': sid,
                   'tool_name': 'functions.exec', 'cwd': str(cwd or self.repo),
                   'tool_input': data or {}}
        if call:
            payload['tool_call_id'] = call
        result = subprocess.run(['bash', str(ROOT / '.claude/hooks/write-log.sh')],
                                input=json.dumps(payload), text=True, capture_output=True,
                                cwd=cwd or self.repo, env=self.env, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('unavailable', result.stderr)

    def records(self):
        path = Path(self.env['CHEWBACCA_WRITE_LOG'])
        return path.read_text().splitlines() if path.exists() else []

    def test_dirty_file_content_change_is_logged_without_claiming_baseline(self):
        self.policy.write_text('already dirty')
        self.hook('PreToolUse')
        self.assertEqual(self.records(), [])
        self.policy.write_text('changed again')
        self.hook('PostToolUse')
        self.assertEqual(len(self.records()), 1)
        self.assertTrue(self.records()[0].endswith(str(self.policy)))
        self.hook('PreToolUse')
        self.hook('PostToolUse')
        self.assertEqual(len(self.records()), 1)

    def test_projectless_cwd_uses_explicit_workdir(self):
        data = {'workdir': str(self.repo)}
        self.hook('PreToolUse', self.outside, data)
        self.policy.write_text('actual write')
        self.hook('PostToolUse', self.outside, data)
        self.assertEqual(len(self.records()), 1)

    def test_patch_target_identifies_other_repository(self):
        data = {'input': f'*** Begin Patch\n*** Update File: {self.policy}\n@@\n-x\n+y\n*** End Patch'}
        self.hook('PreToolUse', self.outside, data)
        self.policy.write_text('patched')
        self.hook('PostToolUse', self.outside, data)
        self.assertEqual(len(self.records()), 1)

    def test_first_post_only_observation_claims_nothing(self):
        self.policy.write_text('preexisting')
        self.hook('PostToolUse')
        self.assertEqual(self.records(), [])
        self.policy.write_text('later change')
        self.hook('PostToolUse')
        self.assertEqual(len(self.records()), 1)

    def test_new_file_delete_and_revert_are_changes(self):
        self.hook('PreToolUse')
        new = self.repo / 'skills/new.md'
        new.write_text('new')
        self.hook('PostToolUse')
        self.hook('PreToolUse')
        new.unlink()
        self.policy.unlink()
        self.hook('PostToolUse')
        self.assertEqual(len(self.records()), 3)

    def test_actual_guard_uses_custom_log_and_filters_session(self):
        self.hook('PreToolUse')
        self.policy.write_text('durable')
        self.hook('PostToolUse')
        guard = ROOT / '.claude/hooks/durable-guard.sh'
        for sid, expected in [('fixture', 0), ('unrelated', 2)]:
            payload = {'hook_event_name': 'Stop', 'session_id': sid,
                       'prompt_id': sid, 'user_message': 'fix chewbacca'}
            result = subprocess.run(['bash', str(guard)], input=json.dumps(payload),
                                    text=True, capture_output=True, env=self.env, timeout=15)
            self.assertEqual(result.returncode, expected, result.stderr)

    def test_shared_home_default_agrees_between_writer_and_reader(self):
        del self.env['CHEWBACCA_WRITE_LOG']
        self.hook('PreToolUse')
        self.policy.write_text('shared home change')
        self.hook('PostToolUse')
        result = subprocess.run(['python3', str(ROOT / 'bin/durable-check'), '--session', 'fixture'],
                                input='fix chewbacca', text=True, capture_output=True, env=self.env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((Path(self.env['CHEWBACCA_HOME']) / 'write-log.tsv').is_file())

    def test_denied_call_does_not_reuse_stale_baseline(self):
        self.hook('PreToolUse')
        self.hook('ToolDenied')
        self.policy.write_text('external intervening edit')
        self.hook('PreToolUse')
        self.hook('PostToolUse')
        self.assertEqual(self.records(), [])

    def test_denied_overlap_keeps_other_pending_baseline(self):
        self.hook('PreToolUse')
        self.policy.write_text('real ongoing write')
        self.hook('PreToolUse')
        self.hook('ToolDenied')
        self.hook('PostToolUse')
        self.assertEqual(len(self.records()), 1)

    def test_overlapping_calls_preserve_earlier_write(self):
        for use_ids in (True, False):
            sid = str(use_ids)
            self.hook('PreToolUse', sid=sid, call='a' if use_ids else None)
            self.policy.write_text('changed ' + sid)
            self.hook('PreToolUse', sid=sid, call='b' if use_ids else None)
            self.hook('PostToolUse', sid=sid, call='b' if use_ids else None)
            self.hook('PostToolUse', sid=sid, call='a' if use_ids else None)
            self.assertTrue(any(line.split('\t')[1] == sid for line in self.records()))

    def test_copied_installed_hook_resolves_shared_checkout(self):
        home = Path(self.env['HOME'])
        hooks = home / '.claude/hooks'
        launchers = home / '.local/bin'
        hooks.mkdir(parents=True)
        launchers.mkdir(parents=True)
        (launchers / 'chewbacca').symlink_to(ROOT / 'bin/chewbacca')
        installed = hooks / 'write-log.sh'
        shutil.copyfile(ROOT / '.claude/hooks/write-log.sh', installed)
        env = dict(self.env)
        env.pop('CHEWBACCA_ROOT', None)
        for event in ('PreToolUse', 'PostToolUse'):
            if event == 'PostToolUse':
                self.policy.write_text('installed edit')
            payload = {'hook_event_name': event, 'session_id': 'installed', 'cwd': str(self.repo)}
            result = subprocess.run(['bash', str(installed)], input=json.dumps(payload),
                                    text=True, capture_output=True, cwd=self.outside, env=env, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotIn('unavailable', result.stderr)
        self.assertEqual(len(self.records()), 1)

    def test_edit_and_commit_within_tool_is_logged(self):
        self.hook('PreToolUse')
        self.policy.write_text('committed during tool')
        self.git('add', '.')
        self.git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-m', 'changed')
        self.hook('PostToolUse')
        self.assertEqual(len(self.records()), 1)
        self.hook('PostToolUse')
        self.assertEqual(len(self.records()), 1)

    def test_command_shaped_patch_has_repository(self):
        data = {'command': f'*** Begin Patch\n*** Update File: {self.policy}\n*** End Patch'}
        self.hook('PreToolUse', self.outside, data)
        self.policy.write_text('command patch')
        self.hook('PostToolUse', self.outside, data)
        self.assertEqual(len(self.records()), 1)

    def test_guard_rejects_earlier_turn_and_accepts_boundary(self):
        boundary = time.time()
        log = Path(self.env['CHEWBACCA_WRITE_LOG'])
        for offset, code in ((-10, 2), (0, 0), (10, 0)):
            log.write_text(f'{boundary + offset}\tfixture\t{self.policy}\n')
            payload = {'hook_event_name': 'Stop', 'session_id': 'fixture',
                       'prompt_id': 'time' + str(offset), 'durable_since': boundary,
                       'user_message': 'fix chewbacca'}
            result = subprocess.run(['bash', str(ROOT / '.claude/hooks/durable-guard.sh')],
                                    input=json.dumps(payload), text=True, capture_output=True,
                                    env=self.env, timeout=15)
            self.assertEqual(result.returncode, code, result.stderr)

    def test_tools_and_instructions_only_qualify_inside_kit(self):
        log = Path(self.env['CHEWBACCA_WRITE_LOG'])
        for name, code in ((ROOT / 'tools/runtime.py', 0), (ROOT / 'instructions/agent-neutral.md', 0),
                           (self.outside / 'tools/random.py', 1), (self.outside / 'instructions/note.md', 1)):
            log.write_text(f'{time.time()}\tfixture\t{name}\n')
            result = subprocess.run(['python3', str(ROOT / 'bin/durable-check'), '--session', 'fixture'],
                                    input='fix chewbacca', text=True, capture_output=True, env=self.env)
            self.assertEqual(result.returncode, code, result.stderr)

    def test_codex_prompt_timestamp_resets_and_reaches_guard(self):
        sys.path.insert(0, str(ROOT / 'tools'))
        import codex_hooks
        with patch.dict(os.environ, self.env | {'CODEX_HOME': str(self.folder / 'codex')}):
            for when in (100.25, 200.5):
                with patch.object(codex_hooks.time, 'time', return_value=when):
                    state = codex_hooks.turn_state({'session_id': 'fixture', 'hook_event_name': 'UserPromptSubmit', 'prompt': 'fix chewbacca'})
                self.assertEqual(state['prompt_started_at'], when)
                calls = []
                def capture(name, payload, cwd):
                    if name == 'durable-guard.sh':
                        calls.append(payload.get('durable_since'))
                    return ''
                with patch.object(codex_hooks, 'shared_hook', side_effect=capture), patch.object(codex_hooks, 'git_notice', return_value=''):
                    codex_hooks.dispatch({'session_id': 'fixture', 'turn_id': str(when), 'hook_event_name': 'Stop', 'cwd': str(self.outside)})
                self.assertEqual(calls, [when])


if __name__ == '__main__':
    unittest.main()

"""Codex's wire format must actually reach the shared checks."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import codex_hooks as hooks


class HookTests(unittest.TestCase):
    def setUp(self):
        self.state_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.state_directory.cleanup)
        private_review = patch.dict(os.environ, {'CHEWBACCA_HOME': str(Path(self.state_directory.name) / 'private')})
        private_review.start()
        self.addCleanup(private_review.stop)
        self.state_patch = patch.object(hooks.context, 'codex_home', return_value=Path(self.state_directory.name))
        self.state_patch.start()
        self.addCleanup(self.state_patch.stop)

    def test_removed_native_hook_does_not_dispatch_or_write_receipt(self):
        import io
        home = hooks.context.codex_home()
        (home / 'hooks.json').write_text(json.dumps({'hooks': {'Stop': [
            {'hooks': [{'type': 'command', 'command': 'other-hook'}]}]}}))
        with patch.object(sys, 'argv', ['codex_hooks.py', 'run']), \
             patch.object(sys, 'stdin', io.StringIO(json.dumps({'hook_event_name': 'Stop'}))), \
             patch.object(hooks, 'dispatch') as dispatch, \
             patch('sys.stdout', new_callable=io.StringIO) as output:
            hooks.main()
        dispatch.assert_not_called()
        self.assertEqual(output.getvalue(), '')
        self.assertFalse((home / 'chewbacca-hook-status.json').exists())

    def test_registration_is_specific_to_adapter_and_event(self):
        home = hooks.context.codex_home()
        self.assertFalse(hooks.registered_for_event(home, 'Stop'))
        hooks.install(home)
        self.assertTrue(hooks.registered_for_event(home, 'Stop'))
        data = json.loads((home / 'hooks.json').read_text())
        data['hooks']['Stop'] = []
        (home / 'hooks.json').write_text(json.dumps(data))
        self.assertFalse(hooks.registered_for_event(home, 'Stop'))
        self.assertTrue(hooks.registered_for_event(home, 'UserPromptSubmit'))

    def test_review_observes_real_repository_writes_across_tool_shapes(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp).resolve()
            repo, outside = root / 'repo with spaces', root / 'outside'
            repo.mkdir()
            outside.mkdir()
            subprocess.run(['git', 'init', '-q', str(repo)], check=True, capture_output=True)
            subprocess.run(['git', '-C', str(repo), '-c', 'user.name=Test',
                            '-c', 'user.email=test@example.invalid', 'commit',
                            '--allow-empty', '-qm', 'init'], check=True, capture_output=True)
            existing = repo / 'existing.py'
            existing.write_text('value = 0\n')
            new_file = repo / 'new directory' / 'new.py'
            cases = [
                ('workdir', 'exec_command', {'workdir': str(repo), 'cmd': 'write'}, existing),
                ('absolute_patch', 'apply_patch',
                 {'command': f'*** Update File: {existing}\n+value = 1'}, existing),
                ('new_directory', 'apply_patch',
                 {'command': f'*** Add File: {new_file}\n+value = 1'}, new_file),
                ('formatter', 'apply_patch',
                 {'command': f'*** Update File: {existing}\n+value = 1'}, existing),
                ('absolute_shell', 'exec_command',
                 {'cmd': f'echo changed > "{existing}"'}, existing),
                ('nested_exec', 'functions.exec', {'code':
                 'await tools.exec_command(' + json.dumps({'workdir': str(repo), 'cmd': 'write'}) + ')'}, existing),
            ]
            for index, (name, tool, tool_input, target) in enumerate(cases, 1):
                with self.subTest(name=name), patch.object(hooks, 'shared_hook', return_value=''), \
                        patch.object(hooks, 'invoke', return_value=''):
                    base = {'session_id': name, 'cwd': str(outside), 'tool_name': tool,
                            'tool_input': tool_input, 'tool_use_id': name}
                    hooks.dispatch(dict(base, hook_event_name='PreToolUse'))

                    def mutate(*_):
                        target.parent.mkdir(parents=True, exist_ok=True)
                        target.write_text(f'value = {index}\n')

                    if name != 'formatter':
                        mutate()
                    with patch.object(hooks, 'format_file', side_effect=mutate if name == 'formatter' else None):
                        hooks.dispatch(dict(base, hook_event_name='PostToolUse'))
                    state = hooks.turn_state(dict(base, hook_event_name='Stop'))
                    self.assertEqual(state['review_required'], [str(repo)])

    def test_post_failure_still_accounts_for_final_bytes_once(self):
        with tempfile.TemporaryDirectory() as temp:
            repo = Path(temp).resolve()
            subprocess.run(['git', 'init', '-q', str(repo)], check=True, capture_output=True)
            target = repo / 'code.py'
            target.write_text('original\n')
            for stage in ('formatter', 'post_hook'):
                with self.subTest(stage=stage):
                    base = {'session_id': stage, 'cwd': str(repo), 'tool_name': 'Edit',
                            'tool_use_id': stage, 'tool_input': {'file_path': str(target)}}
                    with patch.object(hooks, 'shared_hook', return_value=''):
                        hooks.dispatch(dict(base, hook_event_name='PreToolUse'))
                    target.write_text('tool changed ' + stage + '\n')
                    def formatter(*args):
                        if stage == 'formatter':
                            target.write_text('formatter changed bytes then failed\n')
                            raise ValueError('malformed formatter output')
                    def shared(name, *args):
                        if stage == 'post_hook':
                            raise RuntimeError('post hook failed')
                        return ''
                    with patch.object(hooks, 'format_file', side_effect=formatter), \
                            patch.object(hooks, 'shared_hook', side_effect=shared), \
                            patch.object(hooks, 'invoke', return_value=''):
                        with self.assertRaises((ValueError, RuntimeError)):
                            hooks.dispatch(dict(base, hook_event_name='PostToolUse'))
                    state = hooks.turn_state(dict(base, hook_event_name='Stop'))
                    self.assertEqual(state['sequence'], 1)
                    self.assertEqual(state['review_required'], [str(repo)])
                    self.assertEqual(state['review_before'], {})
                    self.assertEqual(state['review_inflight'], {})

    def test_repository_initialized_inside_tool_creates_review_obligation(self):
        with tempfile.TemporaryDirectory() as temp:
            repo = Path(temp).resolve()
            base = {'session_id': 'new-repo', 'cwd': str(repo), 'tool_name': 'exec_command',
                    'tool_use_id': 'init-and-write', 'tool_input': {'cmd': 'git init and write'}}
            with patch.object(hooks, 'shared_hook', return_value=''):
                hooks.dispatch(dict(base, hook_event_name='PreToolUse'))
                subprocess.run(['git', 'init', '-q', str(repo)], check=True, capture_output=True)
                (repo / 'new.py').write_text('new repository content\n')
                hooks.dispatch(dict(base, hook_event_name='PostToolUse'))
            state = hooks.turn_state(dict(base, hook_event_name='Stop'))
            self.assertEqual(state['review_required'], [str(repo)])
            self.assertEqual(state['sequence'], 1)
            import review_gate
            self.assertEqual(review_gate.current_scope(repo)['base'], 'UNBORN')

    def test_pre_scope_failure_keeps_obligation_and_allows_repair(self):
        import review_gate
        with tempfile.TemporaryDirectory() as temp:
            repo = Path(temp).resolve()
            subprocess.run(['git', 'init', '-q', str(repo)], check=True, capture_output=True)
            payload = {'session_id': 'scope-failure', 'hook_event_name': 'PreToolUse',
                       'cwd': str(repo), 'tool_name': 'exec_command', 'tool_use_id': 'scope',
                       'tool_input': {'cmd': 'write'}}
            with patch.object(review_gate, 'capture_scope', side_effect=OSError('disk full')), \
                    patch.object(hooks, 'shared_hook', return_value=''):
                result = hooks.dispatch(payload)
            self.assertNotEqual(result.get('hookSpecificOutput', {}).get('permissionDecision'), 'deny')
            state = hooks.turn_state(dict(payload, hook_event_name='Stop'))
            self.assertEqual(state['review_required'], [str(repo)])
            with patch.object(hooks, 'shared_hook', return_value=''):
                repair = dict(payload, tool_use_id='repair')
                result = hooks.dispatch(repair)
                self.assertNotEqual(result.get('hookSpecificOutput', {}).get('permissionDecision'), 'deny')
                self.assertEqual(review_gate.capture_scope(repo, base='UNBORN')['base'], 'UNBORN')
                hooks.dispatch(dict(repair, hook_event_name='PostToolUse'))
            self.assertEqual(hooks.turn_state(dict(payload, hook_event_name='Stop'))['review_required'], [str(repo)])

    def test_post_scope_failure_keeps_obligation_and_records_sentinel(self):
        import review_gate
        with tempfile.TemporaryDirectory() as temp:
            repo = Path(temp).resolve()
            base = {'session_id': 'post-scope-failure', 'cwd': str(repo),
                    'tool_name': 'exec_command', 'tool_use_id': 'init', 'tool_input': {'cmd': 'init'}}
            with patch.object(hooks, 'shared_hook', return_value=''):
                hooks.dispatch(dict(base, hook_event_name='PreToolUse'))
                subprocess.run(['git', 'init', '-q', str(repo)], check=True, capture_output=True)
                with patch.object(review_gate, 'capture_scope', side_effect=OSError('scope write failed')):
                    hooks.dispatch(dict(base, hook_event_name='PostToolUse'))
            state = hooks.turn_state(dict(base, hook_event_name='Stop'))
            self.assertEqual(state['review_required'], [str(repo)])
            with self.assertRaises(ValueError):
                review_gate.capture_scope(repo)
            self.assertEqual(review_gate.capture_scope(repo, base='UNBORN')['base'], 'UNBORN')

    def test_review_keeps_baseline_for_overlapping_identical_calls(self):
        for identity in ({}, {'tool_use_id': 'duplicate'}):
            with self.subTest(identity=identity):
                base = {'session_id': 'overlap-' + str(identity),
                        'cwd': self.state_directory.name, 'tool_name': 'exec_command',
                        'tool_input': {'cmd': 'same'}, **identity}
                observations = [{'/repo': 'before'}, {'/repo': 'before'},
                                {'/repo': 'before'}, {'/repo': 'after'}]
                with patch.object(hooks, 'review_snapshots', side_effect=observations):
                    for event in ('PreToolUse', 'PreToolUse', 'PostToolUse', 'PostToolUse'):
                        state = hooks.turn_state(dict(base, hook_event_name=event))
                self.assertEqual(state['review_required'], ['/repo'])

    def test_review_keeps_earliest_baseline_when_second_call_starts_after_write(self):
        base = {'session_id': 'overlap-after-write', 'cwd': self.state_directory.name,
                'tool_name': 'exec_command', 'tool_input': {'cmd': 'same'}}
        observations = [{'/repo': 'before'}, {'/repo': 'after'},
                        {'/repo': 'after'}, {'/repo': 'after'}]
        with patch.object(hooks, 'review_snapshots', side_effect=observations):
            for event in ('PreToolUse', 'PreToolUse', 'PostToolUse', 'PostToolUse'):
                state = hooks.turn_state(dict(base, hook_event_name=event))
        self.assertEqual(state['review_required'], ['/repo'])

    def test_unavailable_snapshot_preserves_guards_and_review_obligation(self):
        import review_gate
        with tempfile.TemporaryDirectory() as temp:
            repo = Path(temp).resolve()
            subprocess.run(['git', 'init', '-q', str(repo)], check=True, capture_output=True)
            base = {'session_id': 'unavailable', 'cwd': str(repo),
                    'tool_name': 'exec_command', 'tool_input': {'cmd': 'read'}}
            with patch.object(review_gate, 'snapshot', side_effect=ValueError('unmerged index')), \
                    patch.object(hooks, 'shared_hook', return_value='') as shared:
                hooks.dispatch(dict(base, hook_event_name='PreToolUse'))
                self.assertIn('submit-guard.sh', [call.args[0] for call in shared.call_args_list])
                hooks.dispatch(dict(base, hook_event_name='PostToolUse'))
            state = hooks.turn_state(dict(base, hook_event_name='UserPromptSubmit', prompt='Continue'))
            self.assertEqual(state['review_required'], [str(repo)])
            with patch.object(review_gate, 'check', return_value=(False, 'snapshot unavailable')):
                result = hooks.dispatch(dict(base, hook_event_name='Stop', stop_hook_active=True))
            self.assertEqual(result['decision'], 'block')
            self.assertIn('snapshot unavailable', result['reason'])

    def test_review_tracks_parallel_tools_and_survives_next_prompt(self):
        base = {'session_id': 'review-test', 'cwd': self.state_directory.name}
        hooks.turn_state(dict(base, hook_event_name='UserPromptSubmit', prompt='Fix it'))
        with patch.object(hooks, 'review_snapshots', return_value={'/repo-a': 'before-a'}):
            hooks.turn_state(dict(base, hook_event_name='PreToolUse', tool_use_id='a'))
        with patch.object(hooks, 'review_snapshots', return_value={'/repo-b': 'before-b'}):
            hooks.turn_state(dict(base, hook_event_name='PreToolUse', tool_use_id='b'))
        with patch.object(hooks, 'review_snapshots', return_value={'/repo-a': 'after-a'}):
            hooks.turn_state(dict(base, hook_event_name='PostToolUse', tool_use_id='a'))
        with patch.object(hooks, 'review_snapshots', return_value={'/repo-b': 'before-b'}):
            hooks.turn_state(dict(base, hook_event_name='PostToolUse', tool_use_id='b'))
        state = hooks.turn_state(dict(base, hook_event_name='UserPromptSubmit', prompt='Continue'))
        self.assertEqual(state['review_required'], ['/repo-a'])

    def test_stop_accepts_only_bound_incomplete_report_and_preserves_obligations(self):
        import review_gate
        with tempfile.TemporaryDirectory() as temp, \
                patch.dict(os.environ, {'CHEWBACCA_HOME': temp}), \
                patch.object(review_gate, 'snapshot', return_value='fixture-snapshot'), \
                patch.object(review_gate, 'check', return_value=(False, 'no clean review')), \
                patch.object(hooks, 'shared_hook', return_value=''), \
                patch.object(hooks, 'git_notice', return_value=''):
            repo = Path(temp).resolve() / 'repo'
            repo.mkdir()
            review_gate.failed_outcome(repo, 'fixture-snapshot', 'incomplete',
                                       {'status': 'incomplete', 'summary': 'Missing callers', 'findings': []})
            state = {'review_required': [str(repo)], 'sequence': 2}
            base = {'hook_event_name': 'Stop', 'session_id': 's', 'turn_id': 't',
                    'cwd': str(repo), 'stop_hook_active': True}
            with patch.object(hooks, 'turn_state', return_value=state):
                rejected = hooks.dispatch(dict(base, last_assistant_message='Complete and ready.'))
                self.assertEqual(rejected['decision'], 'block')
                prepared = json.loads(review_gate.disposition_path('s', 't').read_text())
                self.assertIn(prepared['report'], rejected['reason'])
                self.assertNotIn('decision', hooks.dispatch(dict(base, last_assistant_message=prepared['report'])))
                self.assertEqual(state['review_required'], [str(repo)])
                self.assertFalse(review_gate.receipt_path(repo).exists())
                self.assertEqual(hooks.dispatch(dict(base, turn_id='next', last_assistant_message=prepared['report']))['decision'], 'block')
                self.assertEqual(hooks.dispatch(dict(base, last_assistant_message='Incomplete. Everything passed.'))['decision'], 'block')

    def test_unavailable_snapshot_report_survives_reporting_tool_post_event(self):
        import review_gate
        with tempfile.TemporaryDirectory() as temp, \
                patch.dict(os.environ, {'CHEWBACCA_HOME': temp}), \
                patch.object(review_gate, 'snapshot', side_effect=ValueError('unmerged')), \
                patch.object(review_gate, 'check', return_value=(False, 'snapshot unavailable')), \
                patch.object(hooks, 'shared_hook', return_value=''), \
                patch.object(hooks, 'git_notice', return_value=''):
            repo = Path(temp).resolve() / 'repo'
            repo.mkdir()
            review_gate.failed_outcome(repo, None, 'snapshot_unavailable')
            prepared = review_gate.prepare_incomplete([repo], 's', 't', 4)
            state = {'review_required': [str(repo)], 'sequence': 5}
            payload = {'hook_event_name': 'Stop', 'session_id': 's', 'turn_id': 't',
                       'cwd': str(repo), 'stop_hook_active': True, 'last_assistant_message': prepared['report']}
            with patch.object(hooks, 'turn_state', return_value=state):
                self.assertEqual(hooks.dispatch(payload)['decision'], 'block')
                self.assertNotIn('decision', hooks.dispatch(payload))
                self.assertEqual(state['review_required'], [str(repo)])
                self.assertFalse(review_gate.receipt_path(repo).exists())

    def test_review_stop_is_not_skipped_on_retry(self):
        payload = {'hook_event_name': 'Stop', 'cwd': self.state_directory.name,
                   'stop_hook_active': True}
        with patch.object(hooks, 'review_stop', return_value='Independent review missing'):
            result = hooks.dispatch(payload)
        self.assertEqual(result['decision'], 'block')
        self.assertIn('Independent review missing', result['reason'])

    def test_verification_guard_uses_completed_success_after_patch(self):
        with tempfile.TemporaryDirectory() as temp, patch.dict(os.environ, {'HOME': temp, 'TMPDIR': temp}):
            base = {'session_id': 'evidence-test', 'cwd': temp}
            hooks.turn_state(dict(base, hook_event_name='UserPromptSubmit', prompt='Check the change'))
            hooks.turn_state(dict(base, hook_event_name='PostToolUse', tool_name='apply_patch'))
            hooks.turn_state(dict(base, hook_event_name='PostToolUse', tool_name='Bash',
                                  tool_response={'exit_code': 1}))
            stop = dict(base, hook_event_name='Stop', turn_id='failure', last_assistant_message='It works now')
            self.assertIn('vibe-guard', hooks.dispatch(stop)['reason'])
            hooks.turn_state(dict(base, hook_event_name='PostToolUse', tool_name='Bash',
                                  tool_response={'exit_code': 0}))
            self.assertEqual(hooks.dispatch(dict(stop, turn_id='success')), {})
            hooks.turn_state(dict(base, hook_event_name='PostToolUse', tool_name='apply_patch'))
            self.assertIn('vibe-guard', hooks.dispatch(dict(stop, turn_id='edited-again'))['reason'])

    def test_parallel_receipts_are_not_lost(self):
        with hooks.ThreadPoolExecutor(max_workers=4) as pool:
            list(pool.map(lambda _: hooks.turn_state({'session_id': 'parallel',
                          'hook_event_name': 'PostToolUse', 'tool_name': 'Bash',
                          'tool_response': {'exit_code': 0}}), range(12)))
        state = hooks.turn_state({'session_id': 'parallel', 'hook_event_name': 'Stop'})
        self.assertEqual(state['sequence'], 12)
        self.assertEqual(state['last_success'], 12)

    def test_prompt_routes_to_real_skill_in_fresh_install(self):
        with tempfile.TemporaryDirectory() as temp, patch.dict(os.environ, {'HOME': temp}):
            result = hooks.dispatch({'hook_event_name': 'UserPromptSubmit', 'cwd': temp,
                                     'prompt': 'Why is my build failing with a null pointer error?'})
            self.assertIn('debugging', result['hookSpecificOutput']['additionalContext'])

    def test_patch_content_reaches_both_prewrite_guards_after_rename(self):
        payload = {'hook_event_name': 'PreToolUse', 'cwd': '/tmp', 'tool_name': 'apply_patch',
                   'tool_input': {'command': '*** Begin Patch\n*** Update File: old.md\n'
                       '*** Move to: new name.md\n@@\n-old\n+New Person\n*** End Patch'}}
        with patch.object(hooks, 'shared_hook', return_value='') as run:
            hooks.dispatch(payload)
        calls = [c for c in run.call_args_list if c.args[0] in ('fusion-guard.sh', 'ux-guard.sh')]
        self.assertEqual(len(calls), 2)
        for call in calls:
            self.assertEqual(call.args[1]['tool_input']['new_string'], 'New Person')
            self.assertEqual(call.args[1]['tool_input']['file_path'], str(Path('/tmp/new name.md').resolve()))

    def test_write_log_records_real_change_from_shell(self):
        import subprocess
        with tempfile.TemporaryDirectory() as temp, patch.dict(os.environ, {
                'HOME': temp, 'CHEWBACCA_WRITE_LOG': temp + '/writes.tsv',
                'CHEWBACCA_SESSION_STATE': temp + '/state'}):
            repo = Path(temp).resolve() / 'repo'
            repo.mkdir()
            subprocess.run(['git', 'init', '-q', str(repo)], check=True)
            payload = {'hook_event_name': 'PreToolUse', 'tool_name': 'Bash',
                       'tool_input': {'command': 'a local file edit'},
                       'cwd': str(repo), 'session_id': 'writer-test'}
            hooks.dispatch(payload)
            (repo / 'new.txt').write_text('hello')
            hooks.dispatch(dict(payload, hook_event_name='PostToolUse'))
            self.assertIn('writer-test\t' + str((repo / 'new.txt').resolve()),
                          (Path(temp) / 'writes.tsv').read_text())

    def test_real_handoff_guard_blocks_manual_command_handoff(self):
        with tempfile.TemporaryDirectory() as temp, patch.dict(os.environ, {'HOME': temp, 'TMPDIR': temp}):
            payload = {'hook_event_name': 'Stop', 'cwd': temp, 'session_id': 'handoff-test',
                       'turn_id': 'one', 'last_assistant_message':
                       'Run this command in your terminal: npm test'}
            result = hooks.dispatch(payload)
            self.assertEqual(result['decision'], 'block')
            self.assertIn('handoff', result['reason'].lower())

    def test_shell_submission_is_denied_without_running_the_command(self):
        with tempfile.TemporaryDirectory() as temp, patch.dict(os.environ, {'HOME': temp}):
            for name in ('Bash', 'exec_command', 'functions.exec'):
                payload = {'hook_event_name': 'PreToolUse', 'cwd': temp,
                           'tool_name': name, 'tool_input': {
                               'command': 'curl -X POST https://brightspace.example.invalid/dropbox'}}
                result = hooks.dispatch(payload)['hookSpecificOutput']
                self.assertEqual(result['permissionDecision'], 'deny')
                self.assertIn('coursework submission', result['permissionDecisionReason'])
            payload['tool_input']['command'] = 'curl -f https://brightspace.example.invalid/status'
            self.assertEqual(hooks.dispatch(payload), {})

    def test_pretool_matcher_covers_shell_calls(self):
        with tempfile.TemporaryDirectory() as temp:
            path = hooks.install(Path(temp))
            group = json.loads(path.read_text())['hooks']['PreToolUse'][-1]
            self.assertNotIn('matcher', group)

    def test_structured_denial_survives_translation(self):
        from subprocess import CompletedProcess
        denied = {'hookSpecificOutput': {'permissionDecision': 'deny',
                                         'permissionDecisionReason': 'Test refusal'}}
        response = CompletedProcess([], 0, json.dumps(denied), '')
        with patch.object(hooks.subprocess, 'run', return_value=response):
            with self.assertRaises(hooks.HookDenied):
                hooks.invoke(['guard'], {'hook_event_name': 'PreToolUse'}, '/tmp')

    def test_fresh_install_reply_guard_uses_bundled_scanners(self):
        with tempfile.TemporaryDirectory() as temp, patch.dict(os.environ, {'HOME': temp}):
            payload = {'hook_event_name': 'Stop', 'cwd': temp, 'session_id': 'test',
                       'turn_id': 'test', 'last_assistant_message':
                       'In conclusion, let us delve into this robust tapestry. '
                       'It is not about X, it is about Y.'}
            result = hooks.dispatch(payload)
            self.assertEqual(result['decision'], 'block')
            payload['stop_hook_active'] = True
            self.assertEqual(hooks.dispatch(payload), {})

    def test_install_keeps_other_hooks_and_is_idempotent(self):
        with tempfile.TemporaryDirectory() as temp:
            home = Path(temp)
            path = home / 'hooks.json'
            other = {'type': 'command', 'command': 'existing-app-hook'}
            path.write_text(json.dumps({'hooks': {'Stop': [{'hooks': [other]}]}}))
            hooks.install(home)
            first = path.read_text()
            hooks.install(home)
            self.assertEqual(path.read_text(), first)
            self.assertEqual(json.loads(first)['hooks']['Stop'][0]['hooks'], [other])
            self.assertEqual(len(json.loads(first)['hooks']), 5)
            self.assertNotIn('PRIVATE_CANARY', first)
            self.assertTrue((home / 'hooks.json.before-chewbacca').is_file())

    def test_symlink_preserved(self):
        with tempfile.TemporaryDirectory() as temp:
            home = Path(temp)
            target = home / 'dotfiles.json'
            target.write_text('{}')
            (home / 'hooks.json').symlink_to(target)
            hooks.install(home)
            self.assertTrue((home / 'hooks.json').is_symlink())
            self.assertIn('SessionStart', target.read_text())

    def test_patch_all_files_including_rename_and_spaces(self):
        payload = {'cwd': '/tmp', 'tool_name': 'apply_patch', 'tool_input': {'command':
                   '*** Begin Patch\n*** Add File: one.md\n+x\n*** Update File: two.md\n'
                   '*** Move to: new name.md\n@@\n-x\n+y\n*** Delete File: old.md\n*** End Patch'}}
        paths = hooks.changed_paths(payload)
        self.assertEqual([Path(p).name for p in paths], ['one.md', 'two.md', 'new name.md', 'old.md'])
        payload['tool_name'] = 'Bash'
        self.assertEqual(hooks.changed_paths(payload), [])

    def test_post_checks_every_existing_file(self):
        with tempfile.TemporaryDirectory() as temp:
            for name in ('one.md', 'two.md'):
                (Path(temp) / name).write_text('hello')
            payload = {'cwd': temp, 'hook_event_name': 'PostToolUse', 'tool_name': 'apply_patch',
                       'tool_input': {'command': '*** Add File: one.md\n*** Add File: two.md\n*** Delete File: gone.md'}}
            with patch.object(hooks, 'format_file') as fmt, patch.object(hooks, 'shared_hook', return_value='checked') as run:
                out = hooks.dispatch(payload)
            self.assertEqual(fmt.call_count, 2)
            self.assertEqual(run.call_count, 2)
            self.assertEqual(out['hookSpecificOutput']['hookEventName'], 'PostToolUse')
            self.assertTrue(all('file_path' in call.args[1]['tool_input'] for call in run.call_args_list))

    def test_env_patch_reaches_guard_before_write(self):
        payload = {'cwd': '/tmp', 'hook_event_name': 'PreToolUse', 'tool_name': 'apply_patch',
                   'tool_input': {'command': '*** Add File: .env'}}
        with patch.object(hooks, 'shared_hook', return_value='check secrets') as run:
            self.assertIn('check secrets', hooks.dispatch(payload)['hookSpecificOutput']['additionalContext'])
            self.assertEqual(run.call_args_list[0].args[0], 'env-guard.sh')
            self.assertEqual(Path(run.call_args_list[0].args[1]['tool_input']['file_path']).name, '.env')

    def test_stop_feedback_uses_codex_contract_and_no_loop(self):
        payload = {'cwd': '/tmp', 'hook_event_name': 'Stop', 'session_id': 'session', 'turn_id': 'first'}
        with patch.object(hooks, 'shared_hook', side_effect=lambda name, *_: 'Rewrite plainly' if name == 'slop-guard.sh' else '') as run, patch.object(hooks, 'git_notice', return_value=''):
            self.assertEqual(hooks.dispatch(payload), {'decision': 'block', 'reason': 'Rewrite plainly'})
            first_id = run.call_args.args[1]['prompt_id']
            payload['turn_id'] = 'second'
            hooks.dispatch(payload)
            self.assertNotEqual(run.call_args.args[1]['prompt_id'], first_id)
            run.reset_mock()
            payload['stop_hook_active'] = True
            self.assertEqual(hooks.dispatch(payload), {})
            run.assert_not_called()

    def test_startup_fresh_context_on_compaction(self):
        with tempfile.TemporaryDirectory() as temp:
            brain = Path(temp)
            for name in hooks.context.SOURCES:
                path = brain / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('PRIVATE_CANARY')
            with patch.object(hooks.context, 'brain_root', return_value=brain):
                payload = {'hook_event_name': 'SessionStart', 'source': 'compact', 'cwd': temp}
                first = hooks.dispatch(payload)['hookSpecificOutput']['additionalContext']
                self.assertEqual(first.count('PRIVATE_CANARY'), 5)
                (brain / hooks.context.SOURCES[0]).write_text('UPDATED_CANARY')
                self.assertIn('UPDATED_CANARY', hooks.dispatch(payload)['hookSpecificOutput']['additionalContext'])

    def test_literal_prompt_only_never_executes_settings(self):
        import shlex
        with tempfile.TemporaryDirectory() as temp, patch.dict(os.environ, {'HOME': temp}):
            directory = Path(temp) / '.claude'
            directory.mkdir()
            literal = {'hookSpecificOutput': {'hookEventName': 'UserPromptSubmit', 'additionalContext': 'Personal opener'}}
            config = {'hooks': {'UserPromptSubmit': [{'hooks': [
                {'command': 'printf %s ' + shlex.quote(json.dumps(literal))},
                {'command': 'touch /tmp/MUST_NOT_RUN'},
            ]}]}}
            (directory / 'settings.json').write_text(json.dumps(config))
            with patch.object(hooks.subprocess, 'run') as run:
                self.assertEqual(hooks.prompt_context(), 'Personal opener')
                run.assert_not_called()

    def test_legacy_stop_json_is_translated(self):
        result = type('Result', (), {'returncode': 0, 'stderr': '', 'stdout': json.dumps({
            'hookSpecificOutput': {'hookEventName': 'Stop', 'continueLoop': True,
                                   'systemMessage': 'Rewrite reply'}})})()
        with patch.object(hooks.subprocess, 'run', return_value=result):
            self.assertEqual(hooks.invoke(['bash', 'guard.sh'], {}, '/tmp'), 'Rewrite reply')


if __name__ == '__main__':
    unittest.main()

"""Codex's wire format must actually reach the shared checks."""
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import codex_hooks as hooks


class HookTests(unittest.TestCase):
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
            self.assertEqual(run.call_count, 4)
            self.assertEqual(out['hookSpecificOutput']['hookEventName'], 'PostToolUse')
            self.assertTrue(all('file_path' in call.args[1]['tool_input'] for call in run.call_args_list))

    def test_env_patch_reaches_guard_before_write(self):
        payload = {'cwd': '/tmp', 'hook_event_name': 'PreToolUse', 'tool_name': 'apply_patch',
                   'tool_input': {'command': '*** Add File: .env'}}
        with patch.object(hooks, 'shared_hook', return_value='check secrets') as run:
            self.assertIn('check secrets', hooks.dispatch(payload)['hookSpecificOutput']['additionalContext'])
            self.assertEqual(run.call_args.args[0], 'env-guard.sh')
            self.assertEqual(Path(run.call_args.args[1]['tool_input']['file_path']).name, '.env')

    def test_stop_feedback_uses_codex_contract_and_no_loop(self):
        payload = {'cwd': '/tmp', 'hook_event_name': 'Stop', 'session_id': 'session', 'turn_id': 'first'}
        with patch.object(hooks, 'shared_hook', return_value='Rewrite plainly') as run, patch.object(hooks, 'git_notice', return_value=''):
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

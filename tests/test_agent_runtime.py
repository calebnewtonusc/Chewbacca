"""Fresh runtime installs must work without another agent's home or credentials."""
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
import agent_runtime as runtime
import agent_context as context


class RuntimeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.env = patch.dict(os.environ, {'HOME': str(self.home),
            'CODEX_HOME': str(self.home / 'codex custom'),
            'CLAUDE_CONFIG_DIR': str(self.home / '.claude'),
            'CHEWBACCA_HOME': str(self.home / '.chewbacca'),
            'CHEWBACCA_BRAIN_DIR': str(self.home / 'brain')})
        self.env.start()
        self.addCleanup(self.env.stop)

    def test_codex_install_needs_no_claude_and_preserves_configuration(self):
        home = context.codex_home()
        home.mkdir()
        config = home / 'config.toml'
        config.write_text('model = "my-model"\nmodel_provider = "local"\n')
        before = config.read_bytes()
        for _ in range(2):
            result = runtime.setup('codex')
            self.assertFalse(result['runtimes'][0]['skills']['conflicts'])
        self.assertFalse((self.home / '.claude').exists())
        self.assertEqual(config.read_bytes(), before)
        self.assertEqual((home / 'hooks.json').read_text().count('codex_hooks.py'), 5)
        self.assertEqual((home / 'AGENTS.md').read_text().count(runtime.BEGIN), 1)
        self.assertTrue((self.home / '.agents/skills/debugging/SKILL.md').is_file())
        self.assertEqual(context.brain_root(home), (self.home / 'brain').resolve())

    def test_claude_native_configuration_survives_and_every_handler_runs(self):
        home = self.home / '.claude'
        home.mkdir()
        path = home / 'settings.json'
        original = {'model': 'custom', 'permissions': {'deny': ['personal-rule']},
                    'hooks': {'Stop': [{'hooks': [{'type': 'command', 'command': 'user-hook'}]}]}}
        path.write_text(json.dumps(original))
        runtime.setup('claude-code')
        first = path.read_text()
        runtime.setup('claude-code')
        self.assertEqual(path.read_text(), first)
        data = json.loads(first)
        self.assertEqual(data['permissions'], original['permissions'])
        self.assertEqual(data['model'], 'custom')
        self.assertIn('user-hook', first)
        # Run an actual registered shared handler using Claude's wire format.
        command = next(h['command'] for g in data['hooks']['PreToolUse'] for h in g['hooks']
                       if 'submit-guard.sh' in h['command'])
        import shlex
        payload = {'hook_event_name': 'PreToolUse', 'cwd': str(self.home), 'tool_name': 'Bash',
                   'tool_input': {'command': 'curl -X POST https://school.brightspace.invalid/d2l/lms/dropbox/submit'}}
        blocked = subprocess.run(shlex.split(command), input=json.dumps(payload), text=True, capture_output=True)
        self.assertEqual(blocked.returncode, 2, blocked.stdout + blocked.stderr)
        payload['tool_input']['command'] = 'git status --short'
        allowed = subprocess.run(shlex.split(command), input=json.dumps(payload), text=True, capture_output=True)
        self.assertEqual(allowed.returncode, 0, allowed.stderr)
        self.assertFalse(context.codex_home().exists())

    def test_plan_and_status_do_not_write_or_call_models(self):
        with patch.object(runtime.shutil, 'which', return_value=None):
            runtime.plan('both')
            runtime.status('both')
        self.assertEqual(list(self.home.iterdir()), [])

    def test_windows_declines_shell_install_before_any_write(self):
        with patch.object(runtime.sys, 'platform', 'win32'), patch.object(runtime.shutil, 'which', return_value=None):
            with self.assertRaisesRegex(ValueError, 'export only'):
                runtime.setup('codex')
        self.assertEqual(list(self.home.iterdir()), [])

    def test_export_keeps_private_brain_out_and_preserves_user_content(self):
        output = self.home / 'export'
        output.mkdir()
        target = output / 'AGENTS.md'
        target.write_text('User-owned instruction\n')
        for _ in range(2):
            runtime.export('generic', output)
        text = target.read_text()
        self.assertTrue(text.startswith('User-owned instruction'))
        self.assertNotIn(str(self.home), text)
        self.assertEqual(text.count(runtime.BEGIN), 1)

    def test_all_declared_checks_exist(self):
        for scripts in runtime.CLAUDE_CHECKS.values():
            for name in scripts:
                self.assertTrue((ROOT / '.claude/hooks' / name).is_file(), name)

    def test_remove_restores_only_unchanged_owned_files_and_links(self):
        home = context.codex_home()
        home.mkdir()
        target = home / 'AGENTS.md'
        target.write_text('My original instructions')
        for _ in range(2):
            runtime.setup('codex')
        runtime.remove('codex')
        self.assertEqual(target.read_text(), 'My original instructions')
        self.assertFalse((home / 'hooks.json').exists())
        self.assertFalse((self.home / '.agents/skills/debugging').exists())
        self.assertTrue((runtime.shared_home() / 'skills/debugging').exists())
        runtime.setup('codex')
        target.write_text('My newer instructions')
        result = runtime.remove('codex')
        self.assertIn(str(target.resolve()), result[0]['preserved'])
        self.assertEqual(target.read_text(), 'My newer instructions')

    def test_formatter_skips_broken_path_node_and_executes_working_runtime(self):
        import shared_checks
        broken = self.home / 'bin'
        working = self.home / '.nvm/versions/node/v22/bin'
        broken.mkdir()
        working.mkdir(parents=True)
        (broken / 'node').write_text('#!/bin/sh\nexit 127\n')
        (working / 'node').write_text('#!/bin/sh\n[ "$1" = --version ] && exit 0\nprintf formatted > "$3"\n')
        (broken / 'prettier').write_text('#!/usr/bin/env node\n')
        for path in (broken / 'node', working / 'node', broken / 'prettier'):
            path.chmod(0o755)
        target = self.home / 'sample.json'
        target.write_text('{}')
        with patch.dict(os.environ, PATH=str(broken) + ':/usr/bin:/bin'):
            shared_checks.format_file(str(target), str(self.home))
        self.assertEqual(target.read_text(), 'formatted')

    def test_setup_cli_preview_does_not_bootstrap_claude(self):
        result = subprocess.run(['bash', str(ROOT / 'setup.sh'), '--runtime', 'codex', '--dry-run', '--json'],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)['runtimes'][0]['id'], 'codex')
        self.assertEqual(list(self.home.iterdir()), [])


if __name__ == '__main__':
    unittest.main()

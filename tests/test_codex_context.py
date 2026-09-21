"""Startup context stays private, current, and compatible with existing instructions."""
import contextlib
import importlib.util
import io
import json
import os
import subprocess
from unittest.mock import patch
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('codex_context', ROOT / 'tools/codex_context.py')
context = importlib.util.module_from_spec(spec)
spec.loader.exec_module(context)


class ContextTests(unittest.TestCase):
    def test_agent_only_setup_preserves_existing_configuration(self):
        with tempfile.TemporaryDirectory() as temp:
            home = Path(temp)
            codex = home / 'custom codex'
            codex.mkdir()
            brain = home / 'private brain'
            (brain / 'core').mkdir(parents=True)
            (brain / 'core/identity.md').write_text('PRIVATE_CANARY')
            (codex / 'chewbacca-context.json').write_text(json.dumps({'brain_dir': str(brain)}))
            (codex / 'config.toml').write_text('model = "existing-user-model"\n')
            (codex / 'hooks.json').write_text(json.dumps({'hooks': {'Stop': [{'hooks': [
                {'type': 'command', 'command': 'existing-app-hook'}]}]}}))
            env = dict(os.environ, HOME=temp, CODEX_HOME=str(codex))
            env.pop('CHEWBACCA_BRAIN_DIR', None)
            command = ['bash', str(ROOT / 'setup.sh'), '--only', 'agents']
            for _ in range(2):
                result = subprocess.run(command, env=env, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((brain / 'core/identity.md').read_text(), 'PRIVATE_CANARY')
            self.assertFalse((home / 'dev').exists())
            self.assertFalse((brain / 'YOU.md').exists())
            self.assertEqual((codex / 'config.toml').read_text(), 'model = "existing-user-model"\n')
            self.assertIn('existing-app-hook', (codex / 'hooks.json').read_text())
            self.assertNotIn('PRIVATE_CANARY', (codex / 'AGENTS.md').read_text())
            self.assertEqual((codex / 'hooks.json').read_text().count('codex_hooks.py'), 5)

    def test_install_preserves_user_instructions_and_is_idempotent(self):
        with tempfile.TemporaryDirectory() as temp:
            home = Path(temp)
            target = home / 'AGENTS.md'
            target.write_text('User instructions stay here.\n')
            context.install(home, home / 'brain')
            first = target.read_text()
            context.install(home, home / 'brain')
            self.assertEqual(target.read_text(), first)
            self.assertTrue(first.startswith('User instructions stay here.'))
            self.assertEqual(first.count(context.BEGIN), 1)
            self.assertIn('before answering', first)

    def test_installs_into_active_override_without_replacing_it(self):
        with tempfile.TemporaryDirectory() as temp:
            home = Path(temp)
            override = home / 'AGENTS.override.md'
            override.write_text('Override instructions\n')
            self.assertEqual(context.install(home, home / 'brain'), override)
            self.assertTrue(override.read_text().startswith('Override instructions'))
            self.assertFalse((home / 'AGENTS.md').exists())

    def test_private_content_is_read_live_never_copied_to_instructions(self):
        with tempfile.TemporaryDirectory() as temp:
            home = Path(temp) / 'codex'
            brain = Path(temp) / 'brain'
            for relative in context.SOURCES:
                path = brain / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('PRIVATE_CANARY')
            target = context.install(home, brain)
            self.assertNotIn('PRIVATE_CANARY', target.read_text())
            self.assertEqual(target.stat().st_mode & 0o777, 0o600)
            (brain / context.SOURCES[0]).write_text('UPDATED_CANARY')
            with contextlib.redirect_stdout(io.StringIO()) as out:
                self.assertEqual(context.read_sources(brain), 0)
            self.assertIn('UPDATED_CANARY', out.getvalue())
            self.assertEqual(out.getvalue().count('PRIVATE_CANARY'), 4)
            with contextlib.redirect_stdout(io.StringIO()) as out:
                self.assertEqual(context.read_sources(brain, manifest=True), 0)
            self.assertNotIn('PRIVATE_CANARY', out.getvalue())
            self.assertEqual(len(json.loads(out.getvalue())['sources']), 5)

    def test_fresh_setup_profiles_share_context_and_preserve_notes(self):
        for profile in ('personal', 'student', 'developer', 'portable'):
            with self.subTest(profile=profile), tempfile.TemporaryDirectory() as temp:
                home = Path(temp)
                env = dict(os.environ, HOME=temp, CODEX_HOME=str(home / 'custom codex'))
                env.pop('CHEWBACCA_BRAIN_DIR', None)
                env.pop('EDITOR', None)
                stub = home / 'bin'
                stub.mkdir()
                for tool in ('git', 'gh'):
                    path = stub / tool
                    path.write_text('#!/bin/sh\nexit 0\n')
                    path.chmod(0o755)
                env['PATH'] = str(stub) + ':' + env['PATH']
                (home / '.claude').mkdir()
                (home / '.claude/CLAUDE.md').write_text('Keep my Claude instructions.\n')
                command = ['bash', str(ROOT / 'setup.sh'), '--profile', profile,
                           '--name', 'Ada Test', '--repo-dir', str(home / 'work space'), '--no-github']
                for section in ('prereq', 'settings', 'editor', 'desktop', 'mcp', 'plugins', 'tools', 'plynn', 'verify'):
                    command += ['--skip', section]
                def run():
                    result = subprocess.run(command, env=env, capture_output=True, text=True)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                run()
                brain = (home / 'work space/ada-test-context').resolve()
                self.assertEqual(context.source_names(brain), context.FLAT_SOURCES)
                for name in context.FLAT_SOURCES:
                    self.assertTrue((brain / name).is_file(), name)
                codex = home / 'custom codex'
                self.assertEqual(json.loads((codex / 'chewbacca-context.json').read_text())['brain_dir'], str(brain))
                self.assertIn(str(brain), (codex / 'AGENTS.md').read_text())
                self.assertIn(str(brain), (home / '.claude/CLAUDE.md').read_text())
                (brain / 'YOU.md').write_text('PRIVATE_SETUP_CANARY')
                run()
                self.assertEqual((brain / 'YOU.md').read_text(), 'PRIVATE_SETUP_CANARY')
                for path in (codex / 'AGENTS.md', home / '.claude/CLAUDE.md'):
                    self.assertNotIn('PRIVATE_SETUP_CANARY', path.read_text())
                self.assertIn('Keep my Claude instructions.', (home / '.claude/CLAUDE.md').read_text())
                self.assertEqual((home / '.claude/CLAUDE.md').read_text().count(context.CLAUDE_BEGIN), 1)

    def test_discovers_existing_claude_flat_context_and_preserves_symlink(self):
        with tempfile.TemporaryDirectory() as temp, patch.dict(os.environ, {'HOME': temp}, clear=False):
            with patch.dict(os.environ):
                os.environ.pop('CHEWBACCA_BRAIN_DIR', None)
                home = Path(temp)
                brain = home / 'existing brain'
                brain.mkdir()
                (brain / 'YOU.md').write_text('Private identity')
                (home / '.claude').mkdir()
                target = home / 'dotfiles.md'
                target.write_text('@' + str(brain / 'YOU.md') + '\n')
                (home / '.claude/CLAUDE.md').symlink_to(target)
                self.assertEqual(context.brain_root(home / 'codex'), brain)
                context.install_claude(brain)
                self.assertTrue((home / '.claude/CLAUDE.md').is_symlink())
                self.assertIn(context.CLAUDE_BEGIN, target.read_text())
                self.assertNotIn('Private identity', target.read_text())

    def test_missing_context_is_reported_not_invented(self):
        with tempfile.TemporaryDirectory() as temp, contextlib.redirect_stdout(io.StringIO()) as out:
            self.assertEqual(context.read_sources(Path(temp), manifest=True), 1)
        self.assertEqual(len(json.loads(out.getvalue())['missing']), 5)

    def test_ambiguous_markers_do_not_overwrite_existing_file(self):
        with tempfile.TemporaryDirectory() as temp:
            home = Path(temp)
            target = home / 'AGENTS.md'
            target.write_text(context.BEGIN + '\nmissing close')
            before = target.read_text()
            with self.assertRaises(ValueError):
                context.install(home, home / 'brain')
            self.assertEqual(target.read_text(), before)


if __name__ == '__main__':
    unittest.main()

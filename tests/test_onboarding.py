"""Newcomers need blank private context, explicit identity, and predictable flags."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import tomllib
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import agent_context as context
import agent_runtime as runtime


class OnboardingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        env = patch.dict(os.environ, HOME=str(self.home), USER='UnrelatedAccountOwner',
            CODEX_HOME=str(self.home / '.codex'), CLAUDE_CONFIG_DIR=str(self.home / '.claude'),
            CHEWBACCA_HOME=str(self.home / '.chewbacca'), CHEWBACCA_BRAIN_DIR=str(self.home / 'brain'))
        env.start()
        self.addCleanup(env.stop)

    def test_empty_setup_has_complete_private_context_and_no_inferred_identity(self):
        result = runtime.setup('codex')
        brain = self.home / 'brain'
        self.assertEqual(result['created_context'], list(context.SOURCES))
        self.assertEqual(result['missing_context_sources'], [])
        self.assertEqual(brain.stat().st_mode & 0o777, 0o700)
        for name in context.SOURCES:
            target = brain / name
            self.assertEqual(target.stat().st_mode & 0o777, 0o600)
            self.assertNotIn('UnrelatedAccountOwner', target.read_text())
        self.assertFalse((self.home / '.claude').exists())
        config = tomllib.loads((self.home / '.codex/config.toml').read_text())
        self.assertEqual(config['agents'], {'enabled': True, 'max_concurrent_threads_per_session': 100})
        self.assertNotIn('model', config)
        self.assertNotIn('model_provider', config)
        self.assertFalse((self.home / '.chewbacca/people').exists())
        self.assertFalse((self.home / '.chewbacca/preferences.json').exists())

    def test_explicit_unicode_identity_is_private_and_reruns_preserve_notes(self):
        brain = self.home / 'brain'
        result = runtime.setup('codex', person_name='Zoë 山田')
        identity = brain / 'core/identity.md'
        self.assertIn('Zoë 山田', identity.read_text())
        identity.write_text('My own edited identity')
        result = runtime.setup('codex', person_name='Different name')
        self.assertEqual(result['created_context'], [])
        self.assertEqual(identity.read_text(), 'My own edited identity')
        self.assertNotIn('Zoë', (self.home / '.codex/AGENTS.md').read_text())

    def test_unknown_existing_directory_is_rejected_before_configuration_writes(self):
        brain = self.home / 'brain'
        brain.mkdir()
        (brain / 'important.txt').write_text('keep me')
        with self.assertRaisesRegex(ValueError, 'unrecognized layout'):
            runtime.setup('codex')
        self.assertEqual(list(brain.iterdir()), [brain / 'important.txt'])
        self.assertFalse((self.home / '.codex').exists())
        self.assertFalse((self.home / '.chewbacca').exists())

    def test_existing_flat_brain_is_completed_without_rewriting_identity(self):
        brain = self.home / 'brain'
        brain.mkdir()
        (brain / 'YOU.md').write_text('Existing identity')
        context.initialize(brain)
        self.assertEqual((brain / 'YOU.md').read_text(), 'Existing identity')
        self.assertFalse((brain / 'core').exists())
        for name in context.FLAT_SOURCES:
            self.assertTrue((brain / name).is_file())

    def test_preview_and_bad_flags_do_not_start_installation(self):
        for args in (['--pin'], ['--profile'], ['--name'], ['--nonsense'],
                     ['--profile', 'unknown'], ['--yolo'], ['--fullsend'], ['--full_send']):
            with self.subTest(args=args):
                result = subprocess.run(['bash', str(ROOT / 'start.sh'), *args],
                    text=True, capture_output=True, timeout=3)
                self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
                self.assertEqual(list(self.home.iterdir()), [])

    def test_personal_preview_needs_no_name_or_github(self):
        result = subprocess.run(['bash', str(ROOT / 'setup.sh'), '--profile', 'personal', '--dry-run'],
            text=True, capture_output=True, timeout=3)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('<unset>', result.stdout)
        self.assertNotIn('UnrelatedAccountOwner', result.stdout)
        self.assertEqual(list(self.home.iterdir()), [])

    def test_runtime_does_not_silently_ignore_a_permission_flag(self):
        result = subprocess.run(['bash', str(ROOT / 'setup.sh'), '--runtime', 'codex', '--full-send'],
            text=True, capture_output=True, timeout=3)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(list(self.home.iterdir()), [])

    def test_runtime_cli_passes_explicit_name_and_path_and_outputs_brief_result(self):
        brain = self.home / 'chosen brain'
        result = subprocess.run(['bash', str(ROOT / 'setup.sh'), '--runtime', 'codex',
            '--brain-dir', str(brain), '--name', 'Zoë'], text=True, capture_output=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Name: Zoë', (brain / 'core/identity.md').read_text())
        self.assertLess(len(result.stdout.splitlines()), 12)
        self.assertFalse((self.home / '.claude').exists())


if __name__ == '__main__':
    unittest.main()

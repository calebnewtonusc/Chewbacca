"""Hermetic integration boundaries for the optional Codex agent."""
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent.parent


def load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'tools' / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class IntegrationTests(unittest.TestCase):
    def test_export_is_shared_bounded_and_current(self):
        export = load('agents_md')
        text = export.render()
        self.assertLess(len(text.encode()), 24576)
        self.assertEqual((ROOT / 'AGENTS.md').read_text(), text)
        self.assertIn((ROOT / 'instructions/agent-neutral.md').read_text(), text)
        for forbidden in ('FIRST WORDS', 'Stop hook runs', 'CLAUDE_CODE_MAX_', '\n@', '\npaths:'):
            self.assertNotIn(forbidden, text)
        self.assertIn('The user chooses the model and host', text)
        self.assertIn('private', text)

    def test_export_freshness_detects_drift(self):
        with tempfile.TemporaryDirectory() as temp:
            script = str(ROOT / 'tools/agents_md.py')
            subprocess.run(['python3', script, temp], check=True, capture_output=True)
            self.assertEqual(subprocess.run(['python3', script, temp, '--check'], capture_output=True).returncode, 0)
            (Path(temp) / 'AGENTS.md').write_text('stale')
            self.assertEqual(subprocess.run(['python3', script, temp, '--check'], capture_output=True).returncode, 1)

    def test_optional_missing_codex_does_not_probe(self):
        health = load('backend_health')
        with patch.object(health.shutil, 'which', return_value=None), patch.object(health, 'run') as run:
            self.assertEqual(health.cli_health('codex', ['login', 'status'])['state'], 'missing')
            run.assert_not_called()

    def test_auth_states(self):
        health = load('backend_health')
        with patch.object(health.shutil, 'which', return_value='/bin/codex'):
            with patch.object(health, 'run', return_value=(0, 'Logged in')):
                self.assertEqual(health.cli_health('codex', ['login', 'status'])['state'], 'healthy')
            with patch.object(health, 'run', return_value=(1, '')):
                self.assertEqual(health.cli_health('codex', ['login', 'status'])['state'], 'unhealthy')

    def test_browser_health_requires_explicit_healthy_and_success(self):
        health = load('backend_health')
        with tempfile.TemporaryDirectory() as temp, patch.dict(os.environ, MACOS_USE_HOME=temp):
            with patch.object(health.shutil, 'which', return_value='/fake/tool'):
                for code, output, expected in (
                    (0, '{"healthy": true}', 'healthy'),
                    (0, '{"healthy": false}', 'unhealthy'),
                    (1, '{"healthy": true}', 'unhealthy'),
                    (0, '[]', 'unhealthy'),
                    (1, '', 'unhealthy'),
                ):
                    with self.subTest(output=output, code=code), patch.object(health, 'run', return_value=(code, output)):
                        self.assertEqual(health.health(True)['chatgpt_bridge']['state'], expected)

    def test_duplicate_runtime_shims_are_reported_without_modification(self):
        health = load('backend_health')
        with tempfile.TemporaryDirectory() as temp, patch.dict(os.environ, MACOS_USE_HOME=temp):
            shim = Path(temp) / 'mac_use_cli.py'
            shim.write_text('user work')
            with patch.object(health.shutil, 'which', return_value=None):
                self.assertEqual(health.health()['runtime_ownership']['state'], 'unhealthy')
            self.assertEqual(shim.read_text(), 'user work')

    def test_setup_refreshes_owned_launchers_without_runtime_writes(self):
        setup = (ROOT / 'setup.sh').read_text()
        self.assertNotRegex(setup, r'cp .*mac_use_.*\$MU_DIR')
        with tempfile.TemporaryDirectory() as temp:
            runtime = Path(temp) / 'runtime'
            runtime.mkdir()
            sentinel = runtime / 'sentinel'
            sentinel.write_text('unchanged upstream')
            # System PATH excludes the installed Codex and any package managers.
            env = dict(os.environ, HOME=temp, PATH='/usr/bin:/bin', MACOS_USE_HOME=str(runtime))
            for _ in range(2):
                result = subprocess.run(['bash', str(ROOT / 'setup.sh'), '--only', 'agents'], env=env, check=True, capture_output=True, text=True)
                self.assertIn('Codex absent (optional)', result.stdout)
            for name in ('mac-use', 'chatgpt-tab', 'chatgpt-gateway', 'chrome-js'):
                self.assertEqual((Path(temp) / '.local/bin' / name).resolve(), ROOT / 'bin' / name)
            # The installed rule is the source plus Claude-specific `paths:`
            # scoping. Without that frontmatter the rule is always-on, and it
            # is written for the other agent: its own text says the standards
            # "already load for the primary agent. Nothing here restates them."
            # 1,204 tokens of that landed in every Claude session. The source
            # stays clean because it is also what AGENTS.md is generated from,
            # where Claude frontmatter would be noise.
            installed = (Path(temp) / '.claude/rules/agent-neutral.md').read_text()
            source = (ROOT / 'instructions/agent-neutral.md').read_text()
            self.assertTrue(installed.startswith('---\n'), 'rule lost its scoping frontmatter')
            self.assertRegex(installed.split('\n---\n')[0], r'(?m)^paths:')
            self.assertTrue(installed.endswith(source), 'rule body drifted from the source')
            self.assertEqual(list(runtime.iterdir()), [sentinel])
            self.assertEqual(sentinel.read_text(), 'unchanged upstream')
            self.assertFalse((Path(temp) / 'dev').exists())



if __name__ == '__main__':
    unittest.main()

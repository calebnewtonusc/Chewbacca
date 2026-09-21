"""Provider policy and launcher ownership, without browser/model calls."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import types
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('mac_use_cli', ROOT / 'bin/mac_use_cli.py')
cli = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cli)


class Providers(unittest.TestCase):
    def setUp(self):
        self.env = patch.dict(os.environ, {}, clear=True)
        self.env.start()
        self.addCleanup(self.env.stop)

    def test_explicit_browser_wins_over_api_and_health(self):
        with patch.dict(os.environ, OPENAI_API_KEY='fake'), patch.object(cli.shutil, 'which', return_value='/bridge'), patch.object(cli, 'build_chatgpt_web', return_value='browser'), patch.object(cli, 'chatgpt_healthy', side_effect=AssertionError):
            self.assertEqual(cli.build_llm('chatgpt-web'), ('browser', 'chatgpt-web'))

    def test_explicit_claude_wins(self):
        with patch.dict(os.environ, OPENAI_API_KEY='fake'), patch.object(cli, 'build_claude_cli', return_value='claude'):
            self.assertEqual(cli.build_llm('claude-cli'), ('claude', 'claude-cli'))

    def test_missing_explicit_key_never_falls_back(self):
        with patch.object(cli, 'chatgpt_healthy', side_effect=AssertionError):
            self.assertEqual(cli.build_llm('openai'), (None, None))

    def test_api_order_and_explicit_selection(self):
        modules = {'pydantic': types.SimpleNamespace(SecretStr=lambda value: value)}
        for module, factory in [('langchain_google_genai', 'ChatGoogleGenerativeAI'), ('langchain_openai', 'ChatOpenAI'), ('langchain_anthropic', 'ChatAnthropic')]:
            modules[module] = types.SimpleNamespace(**{factory: lambda **kw: kw})
        with patch.dict(sys.modules, modules), patch.dict(os.environ, {env: 'key' for env, _, _ in cli.PROVIDERS}), patch.object(cli, 'chatgpt_healthy', side_effect=AssertionError):
            self.assertEqual(cli.build_llm()[1], 'google')
            for _, name, model in cli.PROVIDERS:
                result, provider = cli.build_llm(name)
                self.assertEqual(provider, name)
                self.assertEqual(result, {'model': model, 'api_key': 'key'})

    def test_fallback_order_and_no_codex(self):
        with patch.object(cli, 'build_chatgpt_web', return_value='browser'), patch.object(cli, 'build_claude_cli', return_value='claude'), patch.object(cli, 'chatgpt_healthy', return_value=True), patch.object(cli, 'claude_authenticated', side_effect=AssertionError):
            self.assertEqual(cli.build_llm()[1], 'chatgpt-web')
        with patch.object(cli, 'chatgpt_healthy', return_value=False), patch.object(cli, 'claude_authenticated', return_value=True), patch.object(cli, 'build_claude_cli', return_value='claude'):
            self.assertEqual(cli.build_llm()[1], 'claude-cli')
        with patch.object(cli, 'chatgpt_healthy', return_value=False), patch.object(cli, 'claude_authenticated', return_value=False):
            self.assertEqual(cli.build_llm(), (None, None))

    def test_health_requires_available_saved_conversation(self):
        saved = 'https://chatgpt.com/c/saved-conversation'
        cases = [
            (0, {'healthy': True, 'conversation_url': saved}, True),
            (0, {'healthy': False, 'conversation_url': saved}, False),
            (1, {'healthy': True, 'conversation_url': saved}, False),
            (0, {'healthy': True, 'conversation_url': 'https://chatgpt.com/'}, False),
            (0, {'healthy': True, 'conversation_url': 'https://example.com/c/saved'}, False),
            (0, {'healthy': True, 'conversation_url': saved + '?query=1'}, False),
            (0, {}, False),
        ]
        for code, state, expected in cases:
            with self.subTest(state=state), patch.object(cli.subprocess, 'run', return_value=subprocess.CompletedProcess([], code, json.dumps(state))):
                self.assertEqual(cli.chatgpt_healthy(), expected)
        with patch.object(cli.subprocess, 'run', side_effect=subprocess.TimeoutExpired('status', 15)):
            self.assertFalse(cli.chatgpt_healthy())
        with patch.object(cli.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, 'idle')):
            self.assertFalse(cli.chatgpt_healthy())

    def test_claude_auth_requires_login(self):
        for output, expected in [('{"loggedIn": true}', True), ('{"loggedIn": false}', False), ('{}', False), ('bad', False)]:
            with patch.object(cli.shutil, 'which', return_value='/claude'), patch.object(cli.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, output)):
                self.assertEqual(cli.claude_authenticated(), expected)

    def test_bridge_defaults_to_own_checkout(self):
        self.assertEqual(cli.chatgpt_binary(), str(ROOT / 'bin/chatgpt-tab'))

    def test_accessibility_denial_stops_before_agent_creation(self):
        from unittest.mock import Mock
        agent = Mock()
        modules = {
            'mlx_use': types.SimpleNamespace(Agent=agent),
            'mlx_use.controller.service': types.SimpleNamespace(Controller=Mock()),
            'ApplicationServices': types.SimpleNamespace(AXIsProcessTrusted=lambda: False),
        }
        with patch.dict(sys.modules, modules), patch.object(cli, 'build_llm', return_value=(object(), 'chatgpt-web')), patch.object(sys, 'argv', ['mac-use', 'test']):
            self.assertEqual(cli.main(), 2)
            agent.assert_not_called()

    def test_launcher_uses_own_cli_through_symlink(self):
        with tempfile.TemporaryDirectory() as temp:
            temp = Path(temp)
            runtime = temp / 'runtime'
            python = runtime / '.venv/bin/python'
            python.parent.mkdir(parents=True)
            python.write_text('#!/bin/sh\nprintf "%s\\n" "$@" "$PYTHONPATH"\n')
            python.chmod(0o755)
            launcher = temp / 'mac-use'
            launcher.symlink_to(ROOT / 'bin/mac-use')
            wrong = temp / 'chewbacca'
            wrong.write_text('#!/bin/sh\necho /wrong/checkout\n')
            wrong.chmod(0o755)
            result = subprocess.run([str(launcher), 'test task'], env={'PATH': str(temp) + ':/bin:/usr/bin', 'HOME': str(temp), 'MACOS_USE_HOME': str(runtime)}, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.splitlines(), [str(ROOT / 'bin/mac_use_cli.py'), 'test task', str(ROOT / 'bin')])


if __name__ == '__main__':
    unittest.main()

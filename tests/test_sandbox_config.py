#!/usr/bin/env python3
"""A sandboxed HOME never reaches the real Claude config.

2026-09-22: tests run from a second-account session (CLAUDE_CONFIG_DIR set to
~/.claude-2) inherited that variable while swapping HOME for a temp dir. Every
`claude` call in setup.sh then used the real account's config under a fake
HOME, which is what raised "A keychain cannot be found" over and over, and
tools/agent_context.py wrote a temp brain path into the real CLAUDE.md.
"""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import agent_context  # noqa: E402
import agent_runtime  # noqa: E402


class SandboxConfigTests(unittest.TestCase):
    def test_python_tools_keep_config_inside_a_sandboxed_home(self):
        with tempfile.TemporaryDirectory() as sandbox, tempfile.TemporaryDirectory() as real:
            with patch.dict(os.environ, HOME=sandbox, CLAUDE_CONFIG_DIR=real):
                for module in (agent_context, agent_runtime):
                    self.assertEqual(module.claude_home(), Path(sandbox) / '.claude')

    def test_config_inside_the_sandbox_is_honoured(self):
        with tempfile.TemporaryDirectory() as sandbox:
            inside = Path(sandbox) / 'second'
            with patch.dict(os.environ, HOME=sandbox, CLAUDE_CONFIG_DIR=str(inside)):
                self.assertEqual(agent_context.claude_home(), inside)

    def test_the_real_home_keeps_its_second_account(self):
        # Outside a sandbox the variable is the whole point of claude2.
        with tempfile.TemporaryDirectory() as elsewhere:
            with patch.dict(os.environ, CLAUDE_CONFIG_DIR=elsewhere):
                os.environ.pop('HOME', None)
                import pwd
                os.environ['HOME'] = pwd.getpwuid(os.getuid()).pw_dir
                self.assertEqual(agent_context.claude_home(), Path(elsewhere))

    def test_setup_in_a_sandbox_leaves_the_real_config_alone(self):
        with tempfile.TemporaryDirectory() as sandbox, tempfile.TemporaryDirectory() as real:
            canary = Path(real) / 'CLAUDE.md'
            canary.write_text('REAL_CONFIG_CANARY\n')
            # A `claude` that records being called with the real config,
            # so the test needs no network and cannot touch a keychain.
            stub = Path(sandbox) / 'bin'
            stub.mkdir()
            record = Path(sandbox) / 'claude-calls'
            (stub / 'claude').write_text(
                f'#!/bin/sh\necho "$CLAUDE_CONFIG_DIR" >> "{record}"\nexit 1\n')
            (stub / 'claude').chmod(0o755)
            env = dict(os.environ, HOME=sandbox, CLAUDE_CONFIG_DIR=real,
                       PATH=f'{stub}:{os.environ["PATH"]}')
            env.pop('CHEWBACCA_BRAIN_DIR', None)
            subprocess.run(['bash', str(ROOT / 'setup.sh'), '--only', 'agents'],
                           env=env, capture_output=True, text=True, timeout=300)
            self.assertEqual(canary.read_text(), 'REAL_CONFIG_CANARY\n')
            self.assertEqual(sorted(p.name for p in Path(real).iterdir()), ['CLAUDE.md'])
            if record.exists():
                for line in record.read_text().splitlines():
                    self.assertNotEqual(line, real, 'claude ran against the real config')


if __name__ == '__main__':
    unittest.main()

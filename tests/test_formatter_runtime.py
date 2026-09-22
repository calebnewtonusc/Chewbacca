"""A present but broken Node must not make formatting silently succeed."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class FormatterRuntimeTests(unittest.TestCase):
    def test_broken_path_node_uses_working_nvm_and_reports_formatter_errors(self):
        with tempfile.TemporaryDirectory() as temp:
            home = Path(temp)
            broken = home / 'broken'
            working = home / '.nvm/versions/node/v22.0.0/bin'
            broken.mkdir()
            working.mkdir(parents=True)
            for file, body in [(broken / 'node', '#!/bin/sh\nexit 1\n'),
                               (working / 'node', '#!/bin/sh\necho v22.0.0\n'),
                               (working / 'prettier', '#!/bin/sh\nnode --version >/dev/null || exit 1\necho formatted > "$2"\n')]:
                file.write_text(body)
                file.chmod(0o755)
            file = home / 'probe.json'
            file.write_text('{}')
            env = dict(os.environ, HOME=temp, NVM_DIR=str(working.parents[3]),
                       PATH=str(broken) + os.pathsep + os.environ['PATH'],
                       CHEWBACCA_LOG_DIR=str(home / 'logs'))
            args = ['bash', str(ROOT / '.claude/hooks/format-and-sync.sh')]
            payload = json.dumps({'tool_input': {'file_path': str(file)}})
            result = subprocess.run(args, input=payload, env=env, text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(file.read_text(), 'formatted\n')
            (working / 'prettier').write_text('#!/bin/sh\nexit 2\n')
            result = subprocess.run(args, input=payload, env=env, text=True, capture_output=True)
            self.assertEqual(result.returncode, 1)
            self.assertIn('Prettier failed', result.stderr)


if __name__ == '__main__':
    unittest.main()

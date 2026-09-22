"""Intentional guard refusals must not be reported as broken hooks."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class HookHealthTests(unittest.TestCase):
    def test_doctor_and_log_distinguish_refusals_from_failures(self):
        body = (ROOT / 'doctor.sh').read_text()
        function = body.split('  hook_failures() {', 1)[1].split('\n  }', 1)[0]
        with tempfile.TemporaryDirectory() as temp:
            log = Path(temp) / '.chewbacca/logs/hooks.log'
            log.parent.mkdir(parents=True)
            log.write_text('2026-01-01|slop-guard.sh|10|exit2|\n'
                           '2026-01-01|formatter.sh|10|exit2|\n'
                           '2026-01-01|submit-guard.sh|10|exit1|\n'
                           '2026-01-01|other.sh|10|timeout|\n'
                           '2026-01-01|good.sh|10|ok|\n')
            count = subprocess.check_output(
                ['bash', '-c', 'hook_failures() {' + function + '\n}\nhook_failures "$1"',
                 'test', str(log)], text=True)
            self.assertEqual(count.strip(), '3')
            errors = subprocess.check_output(
                ['bash', str(ROOT / 'bin/lib/log.sh'), 'errors'],
                env=dict(os.environ, HOME=temp), text=True)
            self.assertNotIn('slop-guard', errors)
            self.assertIn('formatter.sh', errors)
            self.assertIn('submit-guard.sh', errors)
            self.assertIn('timeout', errors)


if __name__ == '__main__':
    unittest.main()

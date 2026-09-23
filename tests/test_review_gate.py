"""Receipt and runner tests with mocked reviewers; no live model review."""
import importlib.util
from contextlib import closing
import json
import os
from pathlib import Path
import subprocess
import sqlite3
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("review_gate", ROOT / "tools/review_gate.py")
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)


class ReviewGateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name) / "repo"
        self.repo.mkdir()
        self.env = patch.dict(os.environ, {"CHEWBACCA_HOME": str(Path(self.temp.name) / "private")})
        self.env.start()
        self.addCleanup(self.env.stop)
        self.git("init", "-q")
        self.git("config", "user.email", "synthetic@example.invalid")
        self.git("config", "user.name", "Synthetic Fixture")
        (self.repo / "tracked.py").write_text("original\n")
        self.git("add", "tracked.py")
        self.git("commit", "-qm", "fixture")
        (self.repo / "tracked.py").write_text("changed\n")
        (self.repo / "new.py").write_text("new file\n")

    def git(self, *args):
        subprocess.run(["git", "-C", str(self.repo), *args], check=True, capture_output=True)

    def reviewer(self, report=None, mutate=None, exit_code=0):
        def complete(command, timeout):
            self.assertIn("read-only", command)
            self.assertIn("--ephemeral", command)
            self.assertNotIn("--ignore-user-config", command)
            self.assertNotIn("--dangerously-bypass-hook-trust", command)
            target = Path(command[command.index("--output-last-message") + 1])
            target.write_text(json.dumps(report or {"status": "reviewed", "summary": "No findings in synthetic review", "findings": []}))
            if mutate:
                mutate()
            return subprocess.CompletedProcess(command, exit_code, "", "")
        return complete

    def run_mock(self, **kwargs):
        with patch.object(gate.shutil, "which", return_value=sys.executable), patch.object(gate, "review_process", side_effect=self.reviewer(**kwargs)):
            return gate.run_review(self.repo, timeout=10)

    def test_committed_changes_remain_in_frozen_review_scope(self):
        scope = gate.capture_scope(self.repo)
        self.git('add', '.')
        self.git('commit', '-qm', 'agent change')
        self.assertEqual(gate.capture_scope(self.repo), scope)
        prompts = []
        reviewer = self.reviewer()
        def observe(command, timeout):
            prompts.append(command[-1])
            return reviewer(command, timeout)
        with patch.object(gate.shutil, 'which', return_value=sys.executable), patch.object(gate, 'review_process', side_effect=observe):
            self.assertTrue(gate.run_review(self.repo)['ok'])
        self.assertIn('git log --reverse -p ' + scope['base'] + '..HEAD', prompts[0])
        self.assertIn('individual commit patches', prompts[0])
        self.assertTrue(gate.check(self.repo)[0])
        changed = dict(scope, base=gate.git(self.repo, 'rev-parse', 'HEAD').decode().strip())
        gate.scope_path(self.repo).write_text(json.dumps(changed))
        self.assertFalse(gate.check(self.repo)[0])

    def test_explicit_base_is_resolved_and_cannot_replace_frozen_scope(self):
        base = gate.git(self.repo, 'rev-parse', 'HEAD').decode().strip()
        self.git('commit', '--allow-empty', '-qm', 'later')
        with patch.object(gate.shutil, 'which', return_value=sys.executable), patch.object(gate, 'review_process', side_effect=self.reviewer()):
            self.assertTrue(gate.run_review(self.repo, base='HEAD~1')['ok'])
        self.assertEqual(gate.current_scope(self.repo)['base'], base)
        with self.assertRaisesRegex(ValueError, 'cannot be replaced'):
            gate.capture_scope(self.repo, 'HEAD')
        self.assertEqual(gate.scope_path(self.repo).stat().st_mode & 0o777, 0o600)

    def test_scope_mutation_during_review_and_corruption_refuse(self):
        scope = gate.capture_scope(self.repo)
        with self.assertRaisesRegex(ValueError, 'changed during'):
            self.run_mock(mutate=lambda: gate.scope_path(self.repo).write_text(json.dumps(dict(scope, base='UNBORN'))))
        self.assertFalse(gate.check(self.repo)[0])
        gate.scope_path(self.repo).write_text('{}')
        with self.assertRaises(ValueError):
            self.run_mock()

    def test_failed_capture_requires_explicit_recovery_base(self):
        gate.mark_scope_failure(self.repo)
        with self.assertRaisesRegex(ValueError, 'explicit base'):
            self.run_mock()
        self.assertFalse(gate.check(self.repo)[0])
        outcome, _ = gate.read_failure(self.repo.resolve())
        self.assertEqual(outcome['scope'], {'capture_failed': True})
        report = gate.prepare_incomplete([self.repo], 'scope-session', 'scope-turn', 1)
        self.assertIn('Work remains incomplete', report['report'])
        self.assertEqual(gate.capture_scope(self.repo, base='UNBORN')['base'], 'UNBORN')
        self.assertFalse(gate.scope_failure_path(self.repo).exists())
        self.assertTrue(self.run_mock()['ok'])
        gate.mark_scope_failure(self.repo)
        self.assertFalse(gate.check(self.repo)[0])
        with self.assertRaises(ValueError):
            gate.capture_scope(self.repo, base='HEAD')
        self.assertTrue(gate.scope_failure_path(self.repo).exists())
        gate.capture_scope(self.repo, base='UNBORN')
        self.assertTrue(gate.check(self.repo)[0])

    def test_unborn_scope_survives_first_commit(self):
        fresh = Path(self.temp.name) / 'fresh-scope'
        fresh.mkdir()
        subprocess.run(['git', 'init', '-q', str(fresh)], check=True)
        self.assertEqual(gate.capture_scope(fresh)['base'], 'UNBORN')
        subprocess.run(['git', '-C', str(fresh), '-c', 'user.name=Synthetic', '-c', 'user.email=synthetic@example.invalid', 'commit', '--allow-empty', '-qm', 'first'], check=True)
        self.assertEqual(gate.capture_scope(fresh)['base'], 'UNBORN')

    def test_real_git_snapshot_binds_untracked_and_index(self):
        first = gate.snapshot(self.repo)
        self.git("add", "tracked.py")
        self.assertNotEqual(first, gate.snapshot(self.repo))
        staged = gate.snapshot(self.repo)
        (self.repo / "new.py").write_text("different\n")
        self.assertNotEqual(staged, gate.snapshot(self.repo))

    def test_pass_and_edits_invalidate_receipt(self):
        self.assertFalse(gate.check(self.repo)[0])
        self.assertTrue(self.run_mock()["ok"])
        self.assertTrue(gate.check(self.repo)[0])
        (self.repo / "new.py").write_text("after review\n")
        self.assertFalse(gate.check(self.repo)[0])
        self.assertTrue(self.run_mock()["ok"])
        (self.repo / "tracked.py").unlink()
        self.assertFalse(gate.check(self.repo)[0])

    def test_mode_symlink_and_head_changes_invalidate(self):
        for mutate in [lambda: (self.repo / "new.py").chmod(0o755),
                       lambda: (self.repo / "link").symlink_to("new.py"),
                       lambda: self.git("commit", "--allow-empty", "-qm", "new head")]:
            self.run_mock()
            mutate()
            self.assertFalse(gate.check(self.repo)[0])
        self.run_mock()
        (self.repo / "link").unlink()
        (self.repo / "link").symlink_to("tracked.py")
        self.assertFalse(gate.check(self.repo)[0])

    def test_findings_and_incomplete_invalidate_previous_pass(self):
        reports = [{"status": "incomplete", "summary": "Could not inspect all files", "findings": []},
                   {"status": "reviewed", "summary": "A defect", "findings": [
                       {"file": "new.py", "line": 1, "severity": "high", "message": "Wrong row", "scenario": "Duplicate ID replaces prior row"}]}]
        for report in reports:
            self.run_mock()
            self.assertFalse(self.run_mock(report=report)["ok"])
            self.assertFalse(gate.check(self.repo)[0])

    def test_failure_timeout_and_malformed_report(self):
        self.run_mock()
        with self.assertRaises(ValueError):
            self.run_mock(exit_code=1)
        self.assertFalse(gate.check(self.repo)[0])
        with patch.object(gate.shutil, "which", return_value=sys.executable), patch.object(gate, "review_process", side_effect=subprocess.TimeoutExpired("reviewer", 1)):
            with self.assertRaises(subprocess.TimeoutExpired):
                gate.run_review(self.repo, 1)
        self.assertFalse(gate.check(self.repo)[0])
        for report in [{"status": "reviewed"}, {"status": "reviewed", "summary": "x", "findings": "none"}]:
            with self.assertRaises(ValueError):
                self.run_mock(report=report)
            self.assertFalse(gate.check(self.repo)[0])

    def test_mutation_during_review_refuses(self):
        with self.assertRaisesRegex(ValueError, "changed during"):
            self.run_mock(mutate=lambda: (self.repo / "new.py").write_text("changed mid-review"))
        self.assertFalse(gate.check(self.repo)[0])

    def test_report_tampering_and_no_manual_import_command(self):
        self.run_mock()
        path = gate.receipt_path(self.repo)
        data = json.loads(path.read_text())
        data["report"]["summary"] = "changed report"
        path.write_text(json.dumps(data))
        self.assertFalse(gate.check(self.repo)[0])
        cli = subprocess.run([sys.executable, str(ROOT / "bin/review-gate"), "approve", "--repo", str(self.repo)], capture_output=True, text=True)
        self.assertNotEqual(cli.returncode, 0)
        cli = subprocess.run([sys.executable, str(ROOT / "bin/review-gate"), "check", "--repo", str(self.repo)], capture_output=True, text=True)
        self.assertEqual(cli.returncode, 1)
        self.assertFalse(json.loads(cli.stdout)["ok"])

    def test_receipts_private_and_outside_repo(self):
        self.run_mock()
        self.assertEqual(gate.receipt_path(self.repo).stat().st_mode & 0o777, 0o600)
        with patch.dict(os.environ, {"CHEWBACCA_HOME": str(self.repo / "private")}):
            with self.assertRaises(ValueError):
                gate.run_review(self.repo)

    def test_unborn_repository_snapshot(self):
        fresh = Path(self.temp.name) / "fresh"
        fresh.mkdir()
        subprocess.run(["git", "init", "-q", str(fresh)], check=True)
        before = gate.snapshot(fresh)
        (fresh / "first.py").write_text("first file")
        self.assertNotEqual(before, gate.snapshot(fresh))

    def test_failed_outcome_is_private_and_does_not_pass_clean_check(self):
        report = {"status": "incomplete", "summary": "Missing caller context", "findings": []}
        self.run_mock(report=report)
        outcome, sha = gate.read_failure(self.repo.resolve())
        self.assertEqual(outcome['kind'], 'incomplete')
        self.assertEqual(len(sha), 64)
        self.assertEqual(gate.failure_path(self.repo).stat().st_mode & 0o777, 0o600)
        self.assertFalse(gate.check(self.repo)[0])
        self.assertFalse(gate.receipt_path(self.repo).exists())

    def test_incomplete_report_requires_exact_final_scope_and_identity(self):
        self.run_mock(report={"status": "incomplete", "summary": "Missing context", "findings": []})
        prepared = gate.prepare_incomplete([self.repo], 'session', 'turn', 3)
        state = {'review_required': [str(self.repo)], 'sequence': 3}
        payload = {'session_id': 'session', 'turn_id': 'turn', 'last_assistant_message': prepared['report']}
        self.assertTrue(gate.allows_incomplete(state, payload))
        self.assertFalse(gate.check(self.repo)[0])
        for changed in ({'last_assistant_message': 'incomplete'},
                        {'last_assistant_message': prepared['report'] + '\nEverything is ready.'},
                        {'session_id': 'other'}, {'turn_id': 'next'}):
            self.assertFalse(gate.allows_incomplete(state, dict(payload, **changed)))
        self.assertFalse(gate.allows_incomplete(dict(state, review_required=[]), payload))
        (self.repo / 'new.py').write_text('later edit')
        self.assertFalse(gate.allows_incomplete(state, payload))

    def test_new_obligation_and_replaced_failed_outcome_invalidate_report(self):
        report = {"status": "incomplete", "summary": "Missing context", "findings": []}
        self.run_mock(report=report)
        prepared = gate.prepare_incomplete([self.repo], 's', 't', 0)
        state = {'review_required': [str(self.repo)], 'sequence': 0}
        payload = {'session_id': 's', 'turn_id': 't', 'last_assistant_message': prepared['report']}
        self.assertFalse(gate.allows_incomplete(dict(state, review_required=[str(self.repo), str(self.repo / 'other')]), payload))
        self.run_mock(report=report)
        self.assertFalse(gate.allows_incomplete(state, payload))
        self.run_mock()
        self.assertFalse(gate.failure_path(self.repo).exists())
        self.assertTrue(gate.check(self.repo)[0])

    def test_unavailable_reviewer_and_changed_review_have_reportable_outcomes(self):
        with patch.object(gate.shutil, 'which', return_value=None):
            with self.assertRaises(ValueError):
                gate.run_review(self.repo)
        self.assertEqual(gate.read_failure(self.repo.resolve())[0]['kind'], 'unavailable')
        with self.assertRaises(ValueError):
            self.run_mock(mutate=lambda: (self.repo / 'new.py').write_text('raced edit'))
        outcome, _ = gate.read_failure(self.repo.resolve())
        self.assertEqual(outcome['kind'], 'changed')
        self.assertEqual(outcome['snapshot'], gate.snapshot(self.repo))
        self.assertIsNone(outcome['report'])
        self.assertFalse(gate.check(self.repo)[0])

    def test_unavailable_snapshot_report_is_sequence_bound(self):
        with patch.object(gate, 'snapshot', side_effect=ValueError('unmerged')):
            with self.assertRaises(ValueError):
                self.run_mock()
            prepared = gate.prepare_incomplete([self.repo], 's', 't', 4)
            payload = {'session_id': 's', 'turn_id': 't', 'last_assistant_message': prepared['report']}
            self.assertIn('bytes could not be verified', prepared['report'])
            self.assertTrue(gate.allows_incomplete({'review_required': [str(self.repo)], 'sequence': 4}, payload))
            self.assertFalse(gate.allows_incomplete({'review_required': [str(self.repo)], 'sequence': 5}, payload))
        self.assertFalse(gate.allows_incomplete({'review_required': [str(self.repo)], 'sequence': 4}, payload))

    def test_cli_report_reads_native_obligations_and_returns_nonclean_disposition(self):
        self.run_mock(report={"status": "incomplete", "summary": "Missing context", "findings": []})
        home = Path(self.temp.name) / 'codex'
        directory = home / 'chewbacca-turn-state'
        directory.mkdir(parents=True)
        with closing(sqlite3.connect(directory / 'receipts.sqlite')) as db:
            db.execute('CREATE TABLE turns (session TEXT PRIMARY KEY, state TEXT NOT NULL)')
            db.execute('INSERT INTO turns VALUES (?, ?)', ('s', json.dumps(
                {'review_required': [str(self.repo)], 'sequence': 6})))
            db.commit()
        with patch.dict(os.environ, {'CODEX_HOME': str(home)}):
            result = subprocess.run([sys.executable, str(ROOT / 'bin/review-gate'),
                                     'report-incomplete', '--session-id', 's', '--turn-id', 't'],
                                    capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, 1)
        record = json.loads(result.stdout)
        self.assertFalse(record['ok'])
        self.assertEqual(record['disposition'], 'incomplete')
        self.assertTrue(Path(record['report_path']).is_file())
        self.assertTrue(gate.allows_incomplete({'review_required': [str(self.repo)], 'sequence': 7},
                                              {'session_id': 's', 'turn_id': 't',
                                               'last_assistant_message': record['report']}))
        self.assertFalse(gate.check(self.repo)[0])

    def test_failure_evidence_missing_or_corrupt_never_allows_report(self):
        with self.assertRaises(OSError):
            gate.prepare_incomplete([self.repo], 's', 't', 0)
        path = gate.failure_path(self.repo)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text('{"version":1}')
        with self.assertRaises(ValueError):
            gate.prepare_incomplete([self.repo], 's', 't', 0)

    def test_nonrepo_refused(self):
        self.assertIsNone(gate.repo_root(Path(self.temp.name)))
        self.assertFalse(gate.check(Path(self.temp.name))[0])
        with self.assertRaises(ValueError):
            gate.run_review(Path(self.temp.name))


if __name__ == "__main__":
    unittest.main()

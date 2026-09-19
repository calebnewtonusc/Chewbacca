"""Hermetic browser bridge regressions; never contacts Chrome."""
import importlib.machinery
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
loader = importlib.machinery.SourceFileLoader('chatgpt_tab', str(ROOT / 'bin/chatgpt-tab'))
spec = importlib.util.spec_from_loader(loader.name, loader)
bridge = importlib.util.module_from_spec(spec)
loader.exec_module(bridge)


def snap(count=1, text='old', identity='old', complete=True, busy=False):
    return dict(count=count, text=text, message_id=identity, complete=complete,
                busy=busy, composer=True, conversation_url='https://chatgpt.com/c/test')


class Clock:
    value = 0

    def now(self):
        return self.value

    def sleep(self, seconds):
        self.value += seconds


class BridgeTests(unittest.TestCase):
    def wait(self, states, timeout=12):
        clock = Clock()
        states = iter(states)
        latest = snap()

        def read(**kwargs):
            nonlocal latest
            latest = next(states, latest)
            return latest

        return bridge.wait_for_response(snap(), timeout, 'https://chatgpt.com/c/test',
                                        read, clock.now, clock.sleep)

    def test_new_response_waits_for_stability(self):
        self.assertEqual(self.wait([snap(), snap(2, 'partial', 'new', False),
                                    snap(2, 'full answer', 'new')]), 'full answer')

    def test_streaming_pause_longer_than_old_threshold_is_not_completion(self):
        states = [snap(2, 'partial', 'new', True, True)] * 12
        states += [snap(2, 'full', 'new')]
        self.assertEqual(self.wait(states, 20), 'full')

    def test_no_stop_button_does_not_prove_completion(self):
        with self.assertRaisesRegex(bridge.BridgeError, 'did not complete'):
            self.wait([snap(2, 'partial', 'new', False)], 10)

    def test_changed_old_message_is_not_new(self):
        with self.assertRaisesRegex(bridge.BridgeError, 'no new assistant'):
            self.wait([snap(text='old message changed')])

    def test_same_text_in_new_message_is_valid(self):
        self.assertEqual(self.wait([snap(2, 'old', 'new')]), 'old')

    def test_new_id_handles_virtualized_count(self):
        self.assertEqual(self.wait([snap(1, 'new answer', 'new')]), 'new answer')

    def test_response_keeps_full_long_text(self):
        result = 'result ' * 10000
        self.assertEqual(self.wait([snap(2, result, 'new')]), result)

    def test_stability_resets_when_text_changes(self):
        states = [snap(2, 'first', 'new')] * 4 + [snap(2, 'second', 'new')]
        self.assertEqual(self.wait(states), 'second')

    def test_missing_composer_and_navigation(self):
        for state, message in [(dict(snap(), composer=False), 'disappeared'),
                               (dict(snap(), conversation_url='https://chatgpt.com/c/other'), 'changed')]:
            with self.subTest(message=message), self.assertRaisesRegex(bridge.BridgeError, message):
                self.wait([state])

    def test_snapshot_validates_transport_result(self):
        with patch.object(bridge, 'run_js', return_value='missing value'):
            with self.assertRaisesRegex(bridge.BridgeError, 'DOM snapshot'):
                bridge.snapshot()
        with patch.object(bridge, 'run_js', return_value=json.dumps(snap())):
            self.assertEqual(bridge.snapshot(), snap())

    def test_snapshot_retries_only_a_bounded_read_timeout(self):
        with patch.object(bridge, 'run_js', side_effect=[bridge.BridgeError('timed out'), json.dumps(snap())]) as read:
            self.assertEqual(bridge.snapshot(), snap())
            self.assertEqual(read.call_count, 2)
        with patch.object(bridge, 'run_js', side_effect=bridge.BridgeError('timed out')) as read:
            with self.assertRaises(bridge.BridgeError):
                bridge.snapshot()
            self.assertEqual(read.call_count, 2)

    def test_send_refuses_draft_busy_missing_composer(self):
        for state, message in [('DRAFT', 'unsent draft'), ('BUSY', 'already generating'),
                               ('NO_COMPOSER', 'no ChatGPT composer')]:
            with self.subTest(state=state), patch.object(bridge, 'run_js', return_value=state):
                with self.assertRaisesRegex(bridge.BridgeError, message):
                    bridge.send('test')

    def test_send_checks_acknowledgement_without_resubmitting(self):
        with patch.object(bridge, 'run_js', side_effect=['queued', 'sent']) as js:
            bridge.send('test')
            self.assertEqual(js.call_count, 2)
            self.assertTrue(js.call_args_list[0].kwargs['activate'])
        with patch.object(bridge, 'run_js', side_effect=['queued', 'failed']):
            with self.assertRaisesRegex(bridge.BridgeError, 'Send control unavailable'):
                bridge.send('test')

    def test_wait_requires_baseline_and_submission_success(self):
        for result, message in [({}, 'no pending turn'),
                                ({'submission':'failed', 'before':snap()}, 'Send control')]:
            with patch.object(bridge, 'run_js', return_value=json.dumps(result)):
                with self.assertRaisesRegex(bridge.BridgeError, message):
                    bridge.read_pending(1, None)

    def test_missing_tab_diagnostic(self):
        with patch.object(bridge.subprocess, 'Popen') as popen:
            popen.return_value.communicate.return_value = ('NO_TAB_MATCHING: chatgpt.com', '')
            popen.return_value.returncode = 0
            with self.assertRaisesRegex(bridge.BridgeError, 'no ChatGPT tab'):
                bridge.run_js('1')

    def test_chrome_timeout_kills_process_group_no_retry(self):
        with patch.object(bridge.subprocess, 'Popen') as popen, patch.object(bridge.os, 'killpg') as kill:
            popen.return_value.pid = 123
            popen.return_value.communicate.side_effect = [subprocess.TimeoutExpired('chrome-js', 1), ('', '')]
            with self.assertRaisesRegex(bridge.BridgeError, 'not retried'):
                bridge.run_js('1', 1)
            kill.assert_called_once()
            popen.assert_called_once()

    def test_conversation_rejects_unsafe_or_foreign_urls(self):
        for url in ['https://evil.test/', 'https://chatgpt.com.evil.test/',
                    'https://chatgpt.com/c/a"', 'https://chatgpt.com/c/a?query=1']:
            with self.subTest(url=url), self.assertRaises(bridge.BridgeError):
                bridge.conversation_url(url)

    def test_status_errors_are_machine_readable(self):
        with patch.object(bridge, 'snapshot', side_effect=bridge.BridgeError('missing tab')), \
                patch('sys.stdout', new_callable=io.StringIO) as out, patch('sys.stderr', new_callable=io.StringIO):
            self.assertEqual(bridge.main(['status', '--json']), 1)
            self.assertFalse(json.loads(out.getvalue())['healthy'])

    def test_command_surface(self):
        for command in ('status', 'send', 'wait', 'last', 'ask'):
            proc = subprocess.run(['python3', str(ROOT / 'bin/chatgpt-tab'), command, '--help'], capture_output=True)
            self.assertEqual(proc.returncode, 0)

    def test_chrome_temp_template_has_no_suffix(self):
        # BSD mktemp treats trailing .js literally, so the second run failed.
        self.assertNotIn('XXXXXX.js', (ROOT / 'bin/chrome-js').read_text())


if __name__ == '__main__':
    unittest.main()

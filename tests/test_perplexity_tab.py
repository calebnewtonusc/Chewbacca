"""Hermetic Perplexity bridge and routing regressions; never contacts Chrome."""
import importlib.machinery
import importlib.util
import sys
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
loader = importlib.machinery.SourceFileLoader('perplexity_tab', str(ROOT / 'bin/perplexity-tab'))
spec = importlib.util.spec_from_loader(loader.name, loader)
bridge = importlib.util.module_from_spec(spec)
loader.exec_module(bridge)
sys.path.insert(0, str(ROOT / 'bin/lib'))
import route  # noqa: E402

TASK = 'https://www.perplexity.ai/computer/tasks/bbeee74c-0e4c-4fcb-a9f5-8fc757ddb13b'


def snap(count=0, text='', busy=False, url=TASK):
    return dict(count=count, text=text, busy=busy, composer=True, session_url=url)


class Clock:
    value = 0.0

    def now(self):
        return self.value

    def sleep(self, seconds):
        self.value += max(seconds, 0.5)


class WaitTests(unittest.TestCase):
    def run_wait(self, states, before=None, timeout=120):
        clock = Clock()
        states = list(states)

        def read(**kwargs):
            return states.pop(0) if len(states) > 1 else states[0]
        return bridge.wait_for_answer(before or snap(), timeout, None, read, clock.now, clock.sleep)

    def test_returns_new_answer_once_stable(self):
        state, text, session = self.run_wait([snap(busy=True), snap(busy=True), snap(1, 'PONG')])
        self.assertEqual((state, text, session), ('done', 'PONG', TASK))

    def test_old_answer_is_never_returned(self):
        with self.assertRaises(bridge.BridgeError):
            self.run_wait([snap(2, 'old')], before=snap(2, 'old'), timeout=10)

    def test_streaming_text_is_not_final_while_busy(self):
        with self.assertRaises(bridge.BridgeError):
            self.run_wait([snap(1, 'partial', busy=True)], timeout=10)

    def test_stopped_to_ask_is_waiting(self):
        state, text, _ = self.run_wait([snap(busy=True), snap(busy=False)])
        self.assertEqual((state, text), ('waiting', ''))

    def test_session_change_fails_closed(self):
        other = TASK[:-1] + '0'
        with self.assertRaises(bridge.BridgeError):
            bridge.wait_for_answer(snap(), 10, TASK, lambda **k: snap(busy=True, url=other),
                                   Clock().now, Clock().sleep)

    def test_task_url_is_validated(self):
        self.assertEqual(bridge.task_url(TASK + '/?x=1'), TASK)
        with self.assertRaises(bridge.BridgeError):
            bridge.task_url('https://evil.example/computer/tasks/abc')

    def test_cli_help(self):
        for command in ('status', 'new', 'send', 'wait', 'last', 'ask'):
            proc = subprocess.run(['python3', str(ROOT / 'bin/perplexity-tab'), command, '--help'],
                                  capture_output=True)
            self.assertEqual(proc.returncode, 0, command)


class RouteTests(unittest.TestCase):
    def dest(self, said, memory=None):
        return route.route(said, {}, memory or {}, classify=lambda s, m: None).dest

    def test_named_goes_to_perplexity(self):
        for said in ('ask Perplexity to research Clay pricing', 'Perplexity, find flights to Tokyo',
                     'tell perplexity to summarize my inbox', 'in Perplexity look up Clay waterfalls'):
            self.assertEqual(self.dest(said), 'perplexity', said)

    def test_never_guessed(self):
        for said in ('research Clay pricing', 'perplexity', 'what time is it'):
            self.assertNotEqual(self.dest(said), 'perplexity', said)

    def test_prefix_is_stripped(self):
        self.assertEqual(route.perplexity_prompt('Ask Perplexity to research Clay pricing'), 'research Clay pricing')
        self.assertEqual(route.perplexity_prompt('Perplexity, find flights'), 'find flights')

    def test_correction_reroutes(self):
        memory = {'last': {'t': '2999-01-01T00:00:00', 'dest': 'assistant', 'text': 'find flights'}}
        decision = route.route('no, perplexity', {}, memory, now=0, classify=lambda s, m: None)
        self.assertEqual((decision.dest, decision.reroute), ('perplexity', 'find flights'))

    def test_jev_cannot_choose_it(self):
        self.assertNotIn('perplexity', route.JEV_QUESTION['dest']['criteria'])


if __name__ == '__main__':
    unittest.main()

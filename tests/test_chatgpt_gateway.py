"""Hermetic reverse gateway framing, execution, and approval tests."""
import importlib.util
from importlib.machinery import SourceFileLoader
import contextlib
import io
import os
import pathlib
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
ROOT = pathlib.Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_loader('gateway', SourceFileLoader('gateway', str(ROOT / 'bin/chatgpt-gateway')))
gateway = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gateway)


def frame(command, timeout=120):
    return f'ACTION: shell\nREASON: inspect\nCWD: /tmp\nTIMEOUT: {timeout}\nCOMMAND:\n<<<CHEWBACCA_COMMAND\n{command}\nCHEWBACCA_COMMAND'


DONE = 'ACTION: done\nSUMMARY:\n<<<CHEWBACCA_SUMMARY\nFinished.\nCHEWBACCA_SUMMARY'


class GatewayTests(unittest.TestCase):
    def test_shell_is_preserved(self):
        for command in ['printf "%s\\n" \'quoted "text"\'', 'printf \'{"nested":{"value":"}"}}\'', "cat <<'EOF'\nquoted \\\" text\nEOF\nprintf done", 'echo one\necho two', 'echo CHEWBACCA_COMMAND_suffix']:
            with self.subTest(command=command):
                self.assertEqual(gateway.parse_action(frame(command))['command'], command)

    def test_incomplete_ambiguous_frames_fail_closed(self):
        valid = frame('echo one')
        for raw in [valid[:-1], valid+' trailing', 'prose\n'+valid, '```\n'+valid+'\n```', valid+'\n'+valid, valid.replace('TIMEOUT: 120', 'TIMEOUT: nope'), frame('echo ok', 601), frame(' '), DONE[:-1], 'ACTION: done\nSUMMARY: done', DONE+'\n'+DONE]:
            with self.subTest(raw=raw):
                with self.assertRaises(ValueError):
                    gateway.parse_action(raw)

    def test_done(self):
        self.assertEqual(gateway.parse_action(DONE), {'action': 'done', 'summary': 'Finished.'})

    def test_cwd(self):
        with tempfile.TemporaryDirectory() as directory:
            self.assertEqual(gateway.resolve_cwd(directory), pathlib.Path(directory).resolve())
            file = pathlib.Path(directory) / 'file'
            file.touch()
            for path in ['.', '$HOME', str(file), directory+'/missing']:
                with self.assertRaises((ValueError, OSError)):
                    gateway.resolve_cwd(path)

    def test_catastrophic_commands(self):
        for command in ['rm -rf /', 'rm -rf /tmp/../', "rm -fr '/'", '/bin/rm -r -f -- /', 'rm --recursive --force "$HOME"', 'rm -rf /*', 'rm -rf ~/', 'diskutil eraseDisk APFS x disk1', 'dd if=x of=/dev/disk0', ':(){ :|:& };:']:
            with self.subTest(command=command):
                self.assertTrue(gateway.blocked(command))
        self.assertFalse(gateway.blocked('git status --short'))
        self.assertFalse(gateway.blocked('rm -rf ./build'))

    def test_destructive_confirmation(self):
        for command in ['rm file', 'sudo echo hi', 'git reset --hard', 'git -C /tmp clean -fd', 'find . -delete', 'python3 -c "pass"']:
            self.assertTrue(gateway.needs_confirmation(command), command)
        self.assertFalse(gateway.needs_confirmation('git status --short'))
        with patch.object(gateway, 'confirm', return_value=False), patch.object(gateway.subprocess, 'Popen') as execute:
            result = gateway.run_shell('rm harmless', ROOT, 1)
            self.assertFalse(result['executed'])
            execute.assert_not_called()
        with patch.object(gateway, 'confirm') as confirm, patch.object(gateway.subprocess, 'Popen') as execute:
            self.assertFalse(gateway.run_shell('rm -rf /', ROOT, 1)['executed'])
            confirm.assert_not_called()
            execute.assert_not_called()
        with patch('builtins.input', side_effect=EOFError), contextlib.redirect_stdout(io.StringIO()):
            self.assertFalse(gateway.confirm('rm file'))

    def test_execution_and_output(self):
        result = gateway.run_shell("printf 'hello'; printf 'bad' >&2; exit 7", ROOT, 2)
        self.assertEqual((result['stdout'], result['stderr'], result['exit_code']), ('hello', 'bad', 7))
        buffer = gateway.OutputBuffer()
        for _ in range(200):
            buffer.add(b'a' * 1000)
        self.assertLessEqual(len(buffer.head)+len(buffer.tail), gateway.MAX_OUTPUT)
        self.assertIn('OUTPUT TRUNCATED', buffer.text())

    def test_heredoc_execution_with_unmatched_quote(self):
        result = gateway.run_shell("cat <<'EOF'\nIt's valid JSON: {\"key\": \"value\"}\nEOF", ROOT, 2)
        self.assertEqual(result['exit_code'], 0)
        self.assertIn("It's valid JSON", result['stdout'])

    def test_timeout_kills_children(self):
        # The margins here were 0.1s of timeout against a 0.4s child and a 0.5s
        # wait, which is 100ms of slack. That is enough on an idle machine and
        # not enough inside the full suite, where this runs alongside real
        # installs: the timeout fired before `printf started` had been read and
        # the assertion on stdout failed on a gateway that was working
        # correctly. The suite now gates an unattended push, so a test that
        # fails under load blocks real work. Same assertions, real slack.
        with tempfile.TemporaryDirectory() as directory:
            marker = pathlib.Path(directory) / 'escaped'
            command = f'(sleep 2; touch {marker}) & printf started; wait'
            result = gateway.run_shell(command, directory, .5)
            self.assertTrue(result['timeout'])
            self.assertEqual(result['stdout'], 'started')
            # Outlast the child: if the process group survived the timeout, the
            # marker appears within its 2 seconds and this catches it.
            time.sleep(2.5)
            self.assertFalse(marker.exists())

    def test_stop_process_never_signals_a_reaped_pid(self):
        """The pid belongs to the OS again the moment the child is reaped.

        run_shell calls stop_process from the timeout, except and finally
        paths, so it runs up to three times on one process. Every call after
        the first was doing killpg on a number that could already have been
        handed to an unrelated process. It surfaced as an intermittent
        PermissionError when the recycled pid landed on a process this user
        does not own; the same race on a pid this user does own sends SIGKILL
        to somebody else's process group.
        """
        process = subprocess.Popen(['/bin/sh', '-c', 'exit 0'], start_new_session=True)
        process.wait()
        self.assertIsNotNone(process.returncode)
        with patch.object(gateway.os, 'killpg') as killpg:
            gateway.stop_process(process)
            gateway.stop_process(process)
            killpg.assert_not_called()

    def test_interrupt_kills_children(self):
        with patch.object(gateway.selectors.DefaultSelector, 'select', side_effect=KeyboardInterrupt), patch.object(gateway, 'stop_process', wraps=gateway.stop_process) as stop:
            with self.assertRaises(KeyboardInterrupt):
                gateway.run_shell('sleep 10', ROOT, 20)
            self.assertGreaterEqual(stop.call_count, 1)
            self.assertIsNotNone(stop.call_args.args[0].poll())

    def test_repair_is_bounded(self):
        with patch.object(gateway, 'ask_chatgpt', side_effect=['bad', DONE]) as ask:
            self.assertEqual(gateway.request_action('initial', 10, 'url', 2)['action'], 'done')
            self.assertIn('FORMAT REPAIR', ask.call_args.args[0])
        with patch.object(gateway, 'ask_chatgpt', return_value='bad') as ask:
            with self.assertRaises(RuntimeError):
                gateway.request_action('initial', 10, 'url', 2)
            self.assertEqual(ask.call_count, 3)

    def test_pinned_conversation_and_stdin(self):
        url = 'https://chatgpt.com/c/abc-123'
        with patch.object(gateway, 'bridge', return_value='{"healthy":true,"conversation_url":"'+url+'"}'):
            self.assertEqual(gateway.pin_conversation(), url)
        with patch.object(gateway, 'bridge', return_value='ok') as bridge:
            gateway.ask_chatgpt('long prompt', 10, url)
            self.assertEqual(bridge.call_args.args, (['ask', '--stdin', '--timeout', '10', '--conversation', url], 40, 'long prompt'))
        with patch.object(gateway, 'bridge', return_value='{"healthy":true,"url":"https://chatgpt.com/"}'):
            with self.assertRaises(RuntimeError):
                gateway.pin_conversation()

    def test_main_ctrl_c(self):
        with patch.object(gateway, 'pin_conversation', side_effect=KeyboardInterrupt), contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(gateway.main(['harmless objective']), 130)


if __name__ == '__main__':
    unittest.main()

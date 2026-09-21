"""Real LangChain/Pydantic adapter tests. Run with the macOS-use venv."""
import importlib.util
import json
import subprocess
from pathlib import Path
import unittest
from unittest.mock import patch

try:
    from pydantic import BaseModel, ValidationError
    from langchain_core.messages import AIMessage
    spec = importlib.util.spec_from_file_location('mac_use_chatgpt', Path(__file__).resolve().parents[1] / 'bin/mac_use_chatgpt.py')
    adapter = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(adapter)
except ImportError:
    adapter = None
else:
    class Answer(BaseModel):
        value: int
        details: dict = {}


@unittest.skipIf(adapter is None, 'requires macOS-use venv LangChain/Pydantic dependencies')
class Structured(unittest.TestCase):
    def test_stdin_transport_full_response_and_pinned_turns(self):
        url = 'https://chatgpt.com/c/saved-conversation'
        status = subprocess.CompletedProcess([], 0, json.dumps({
            'healthy': True, 'conversation_url': url,
        }), '')
        text = 'sent\n' + ('full response ' * 100000)
        response = subprocess.CompletedProcess([], 0, text, '')
        prompt = 'long context ' * 100000
        model = adapter.ChatGPTWebChatModel()
        with patch.object(adapter.subprocess, 'run', side_effect=[status, response, response]) as run:
            self.assertEqual(model._call_web(prompt), text.strip())
            self.assertEqual(model._call_web('next step'), text.strip())
        self.assertEqual(run.call_count, 3)
        first, second = run.call_args_list[1:]
        self.assertEqual(first.kwargs['input'], prompt)
        self.assertNotIn(prompt, first.args[0])
        self.assertIn('--stdin', first.args[0])
        self.assertEqual(first.args[0], second.args[0])
        self.assertIn(url, first.args[0])

    def test_missing_saved_conversation_never_sends(self):
        for state in [
            {'healthy': False, 'conversation_url': 'https://chatgpt.com/c/saved'},
            {'healthy': True, 'conversation_url': 'https://chatgpt.com/'},
            {'healthy': True, 'conversation_url': 'https://example.com/c/saved'},
        ]:
            with self.subTest(state=state):
                response = subprocess.CompletedProcess([], 0, json.dumps(state), '')
                with patch.object(adapter.subprocess, 'run', return_value=response) as run:
                    with self.assertRaises(RuntimeError):
                        adapter.ChatGPTWebChatModel()._call_web('task')
                self.assertEqual(run.call_count, 1)

    def test_json_candidates(self):
        cases = [
            '{"value": 56}',
            'Here is the result: {"value": 56} done.',
            '```json\n{"value": 56}\n```',
            '{"value":56,"details":{"nested":{"text":"braces } { and \\\" quote"}}}',
            '{not json} then {"value":56}',
            '{broken "unclosed then {"value":56}',
            'stray } or "prose quotation {"value":56}',
            '{"value":"wrong"} then {"value":56}',
        ]
        for text in cases:
            with self.subTest(text=text):
                self.assertEqual(adapter.validate_response(text, Answer).value, 56)

    def test_validation_failure(self):
        with self.assertRaises(ValidationError):
            adapter.validate_response('{"value":"wrong"}', Answer)

    def test_repair_success_and_raw(self):
        model = adapter.ChatGPTWebChatModel()
        with patch.object(adapter.ChatGPTWebChatModel, '_call_web', side_effect=['bad', '{"value":56}']) as web:
            result = model.with_structured_output(Answer, include_raw=True).invoke('calculate')
        self.assertEqual(web.call_count, 2)
        self.assertEqual(result['parsed'].value, 56)
        self.assertIsNone(result['parsing_error'])
        self.assertEqual(result['raw'].content, '{"value":56}')
        self.assertIn('Validation error', web.call_args.args[0])

    def test_schema_repair_bounded(self):
        model = adapter.ChatGPTWebChatModel(repair_attempts=2)
        with patch.object(adapter.ChatGPTWebChatModel, '_call_web', return_value='{"value":"bad"}') as web:
            result = model.with_structured_output(Answer, include_raw=True).invoke('calculate')
        self.assertEqual(web.call_count, 3)
        self.assertIsNone(result['parsed'])
        self.assertIsInstance(result['parsing_error'], ValidationError)
        self.assertIsInstance(result['raw'], AIMessage)

    def test_failure_without_raw_raises(self):
        with patch.object(adapter.ChatGPTWebChatModel, '_call_web', return_value='bad') as web:
            with self.assertRaises(ValueError):
                adapter.ChatGPTWebChatModel().with_structured_output(Answer).invoke('calculate')
        self.assertEqual(web.call_count, 2)

    def test_valid_response_needs_one_turn(self):
        with patch.object(adapter.ChatGPTWebChatModel, '_call_web', return_value='{"value":56}') as web:
            self.assertEqual(adapter.ChatGPTWebChatModel().with_structured_output(Answer).invoke('calculate').value, 56)
        self.assertEqual(web.call_count, 1)


if __name__ == '__main__':
    unittest.main()

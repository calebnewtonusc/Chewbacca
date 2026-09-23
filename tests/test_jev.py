#!/usr/bin/env python3
"""Offline boundary tests; never read real credentials or call TypeSafe."""
import copy
import io
import importlib.util
import json
import os
import tempfile
from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import patch
import urllib.error

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
spec = importlib.util.spec_from_file_location("chewbacca_jev_cli", ROOT / "tools/jev.py")
jev = importlib.util.module_from_spec(spec)
spec.loader.exec_module(jev)
shared_allowed = jev.allowed


REQUEST = {"model": jev.MODEL, "state": "a", "questions": {
    "pick": {"type": "choice", "instructions": "Choose", "criteria": {"a": None, "b": None}},
    "yes": {"type": "noul", "instructions": "Is it a?"},
    "level": {"type": "score", "instructions": "Degree", "criteria": ["none", "some"]}}}
RESPONSE = {"model": jev.MODEL, "answers": {
    "pick": {"type": "choice", "choice": "a", "confidence": 1, "probabilities": {"a": 1, "b": 0}},
    "yes": {"type": "noul", "noul": 1},
    "level": {"type": "score", "score": 1, "confidence": 1, "probabilities": {"0": 0, "1": 1}, "legend": {"0": "none", "1": "some"}}},
    "usage": {"input_tokens": 100, "output_tokens": 30}}


class JevTests(unittest.TestCase):
    def setUp(self):
        # Transport tests remain hermetic even inside an Amber user root.
        gate = patch.object(jev, "allowed", return_value=True)
        gate.start()
        self.addCleanup(gate.stop)

    def test_valid_contract(self):
        jev.validate_request(REQUEST)
        jev.validate_response(RESPONSE, REQUEST)

    def test_invalid_request_never_reads_key(self):
        for payload in [None, {}, {**REQUEST, "questions": {}}, {**REQUEST, "state": "x" * jev.MAX_BYTES}]:
            with patch.object(jev, "api_key") as key, self.assertRaises(jev.JevError):
                jev.evaluate(payload)
            key.assert_not_called()

    def test_invalid_answers_fail_closed(self):
        mutations = [lambda r: r["answers"].pop("yes"),
                     lambda r: r["answers"]["pick"].update(choice=[]),
                     lambda r: r["answers"]["pick"].update(choice="injected-command"),
                     lambda r: r["answers"]["yes"].update(noul=float("nan")),
                     lambda r: r["answers"]["pick"].update(confidence=True),
                     lambda r: r["answers"]["pick"].update(probabilities={"a": 0, "b": 0}),
                     lambda r: r["answers"]["level"].update(score=2),
                     lambda r: r["usage"].update(input_tokens=-1)]
        for mutation in mutations:
            result = copy.deepcopy(RESPONSE)
            mutation(result)
            with self.assertRaises(jev.JevError):
                jev.validate_response(result, REQUEST)

    def test_huge_numeric_answers_reject_without_overflow(self):
        self.assertFalse(jev.probability(10**400))
        for key, field in [("yes", "noul"), ("pick", "confidence"), ("level", "score")]:
            response = copy.deepcopy(RESPONSE)
            response["answers"][key][field] = 10**400
            with self.assertRaises(jev.JevError):
                jev.validate_response(response, REQUEST)
        response = copy.deepcopy(RESPONSE)
        response["answers"]["pick"]["probabilities"] = {"a": 10**400, "b": 0}
        with self.assertRaises(jev.JevError):
            jev.validate_response(response, REQUEST)

    def test_nonmax_choice_rejected_but_tie_preserved(self):
        response = copy.deepcopy(RESPONSE)
        response["answers"]["pick"]["probabilities"] = {"a": 0.1, "b": 0.9}
        with self.assertRaises(jev.JevError):
            jev.validate_response(response, REQUEST)
        response["answers"]["pick"]["probabilities"] = {"a": 0.5, "b": 0.5}
        jev.validate_response(response, REQUEST)

    def test_api_transport_and_usage(self):
        with patch.object(jev, "api_key", return_value="test-key"), patch.object(jev.urllib.request, "build_opener") as build:
            build.return_value.open.return_value = io.BytesIO(json.dumps(RESPONSE).encode())
            result = jev.evaluate(REQUEST)
            request = build.return_value.open.call_args.args[0]
            self.assertEqual(request.full_url, jev.ENDPOINT)
            self.assertEqual(result["usage"]["input_tokens"], 100)
            self.assertNotIn("state", result)
            self.assertIn("latency_ms", result)

    def test_http_error_does_not_echo_input_or_retry(self):
        with patch.object(jev, "api_key", return_value="secret"), patch.object(jev.urllib.request, "build_opener") as build:
            build.return_value.open.side_effect = urllib.error.HTTPError(jev.ENDPOINT, 429, "secret", {}, io.BytesIO(b"private request"))
            with self.assertRaises(jev.JevError) as caught:
                jev.evaluate(REQUEST)
            self.assertNotIn("secret", str(caught.exception))
            self.assertNotIn("private", str(caught.exception))
            self.assertEqual(build.return_value.open.call_count, 1)

    def test_redirect_cannot_forward_credentials(self):
        self.assertIsNone(jev.NoRedirect().redirect_request(None, None, 302, "", {}, "https://example.org"))

    def test_unknown_response_fields_are_not_returned(self):
        response = copy.deepcopy(RESPONSE)
        response["usage"]["private"] = "never print"
        response["answers"]["yes"]["private"] = "never print"
        with patch.object(jev, "api_key", return_value="key"), patch.object(jev.urllib.request, "build_opener") as build:
            build.return_value.open.return_value = io.BytesIO(json.dumps(response).encode())
            self.assertNotIn("never print", json.dumps(jev.evaluate(REQUEST)))

    def test_route_uses_allowlisted_paths_and_none(self):
        for choice in ["s0", "none"]:
            with patch("skill_match.load_skills", return_value=[("example", "Example skill", "/local/skill")]), patch.object(jev, "evaluate", return_value={"answers": {"skill": {"choice": choice}}}) as evaluate:
                result = jev.route("Do an example")
                self.assertNotIn("/local/skill", json.dumps(evaluate.call_args.args[0]))
                self.assertTrue(result["advisory_only"])
                self.assertEqual(result["suggestion"], None if choice == "none" else {"name": "example", "path": "/local/skill"})

    def test_pinned_transport_and_local_budgets_preserved(self):
        self.assertEqual(jev.MODEL, "jev-1.13.0")
        self.assertEqual(jev.MAX_BYTES, 100_000)
        self.assertEqual(jev.TIMEOUT, 15)
        with patch.object(jev, "api_key", return_value="test-key"), patch.object(jev.urllib.request, "build_opener") as build:
            build.return_value.open.return_value = io.BytesIO(json.dumps(RESPONSE).encode())
            jev.evaluate(REQUEST)
            self.assertEqual(build.return_value.open.call_args.kwargs["timeout"], 15)
            self.assertEqual(build.call_args.args, (jev.NoRedirect,))

    def test_response_size_cap_preserved(self):
        with patch.object(jev, "api_key", return_value="test-key"), patch.object(jev.urllib.request, "build_opener") as build:
            build.return_value.open.return_value = io.BytesIO(b"x" * (jev.MAX_BYTES + 1))
            with self.assertRaises(jev.JevError):
                jev.evaluate(REQUEST)

    def test_shared_consent_without_credentials(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"AMBER_ROOT": directory}):
            self.assertFalse(shared_allowed())
            Path(directory, "consent.json").write_text('{"jev": true}')
            self.assertTrue(shared_allowed())
            Path(directory, "consent.json").write_text('{"jev": "yes"}')
            self.assertFalse(shared_allowed())

    def test_denied_consent_prevents_key_and_network(self):
        with patch.object(jev, "allowed", return_value=False), patch.object(jev, "api_key") as key, patch.object(jev.urllib.request, "build_opener") as network:
            with self.assertRaises(jev.JevError):
                jev.evaluate(REQUEST)
            key.assert_not_called()
            network.assert_not_called()

    def test_both_keychain_names_without_real_credentials(self):
        responses = [subprocess.CompletedProcess([], 1, "", ""), subprocess.CompletedProcess([], 0, "fake-test-key\n", "")]
        with patch.dict(os.environ, {"TYPESAFE_API_KEY": ""}), patch.object(jev.sys, "platform", "darwin"), patch.object(jev.subprocess, "run", side_effect=responses) as run:
            self.assertEqual(jev.api_key(), "fake-test-key")
            self.assertIn("typesafe-ai", run.call_args_list[0].args[0])
            self.assertIn("TYPESAFE_API_KEY", run.call_args_list[1].args[0])

    def test_auth_keeps_key_out_of_argv_and_verifies_storage(self):
        responses = [subprocess.CompletedProcess([], 0, "", ""), subprocess.CompletedProcess([], 0, "fake-test-key\n", "")]
        with patch.object(jev.sys, "platform", "darwin"), patch.object(jev.subprocess, "run", side_effect=responses) as run:
            jev.save_key("fake-test-key")
            for call in run.call_args_list:
                self.assertNotIn("fake-test-key", " ".join(call.args[0]))
            self.assertIn("fake-test-key", run.call_args_list[0].kwargs["input"])

    def test_status_is_local_only(self):
        with patch.object(sys, "argv", ["jev", "status"]), patch.object(jev, "api_key", return_value="fake"), patch.object(jev, "evaluate") as evaluate, patch("sys.stdout", new_callable=io.StringIO) as output:
            self.assertEqual(jev.main(), 0)
            self.assertFalse(json.loads(output.getvalue())["network_checked"])
            evaluate.assert_not_called()

    def test_evaluate_default_and_explicit_model(self):
        for selected in [None, "jev-custom-pinned"]:
            request = copy.deepcopy(REQUEST)
            if selected is None:
                request.pop("model")
            else:
                request["model"] = selected
            with patch.object(sys, "argv", ["jev", "evaluate", "-"]), patch.object(jev, "read_input", return_value=json.dumps(request)), patch.object(jev, "evaluate", return_value=RESPONSE) as evaluate, patch("sys.stdout", new_callable=io.StringIO):
                self.assertEqual(jev.main(), 0)
                self.assertEqual(evaluate.call_args.args[0]["model"], selected or jev.MODEL)

    def test_smoke_is_one_explicit_call_all_primitives(self):
        result = {"answers": {"number": {"choice": "7"}, "seven": {"noul": 1}, "match": {"score": 1}}}
        with patch.object(sys, "argv", ["jev", "smoke"]), patch.object(jev, "evaluate", return_value=result) as evaluate, patch("sys.stdout", new_callable=io.StringIO):
            self.assertEqual(jev.main(), 0)
            self.assertEqual(evaluate.call_count, 1)
            self.assertEqual({q["type"] for q in evaluate.call_args.args[0]["questions"].values()}, {"choice", "score", "noul"})

    def test_cli_registered(self):
        result = subprocess.run(["bash", str(ROOT / "bin/chewbacca"), "jev", "--help"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("evaluate", result.stdout)


if __name__ == "__main__":
    unittest.main()

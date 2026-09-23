#!/usr/bin/env python3
"""Offline content oracle tests; no application or browser claims."""
import copy
import csv
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("checker", ROOT / "tools/clay_fixture_check.py")
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


def fixture():
    return {"schema_version": 1, "columns": {"stable_id": "fixture_id", "name": "Name", "email": "Email", "status": "Status"},
            "null_encoding": {"mode": "token", "token": "\\N"},
            "records": [{"stable_id": "r1", "expected": {"name": 'Beta, "quoted"\nFixture', "email": None, "status": "HOLD"}},
                        {"stable_id": "r2", "expected": {"name": " Same name ", "email": "", "status": "READY"}}]}


def export(rows=None, headers=None):
    stream = io.StringIO(newline="")
    writer = csv.writer(stream)
    writer.writerow(headers or ["fixture_id", "Name", "Email", "Status"])
    writer.writerows(rows if rows is not None else [["r2", " Same name ", "", "READY"], ["r1", 'Beta, "quoted"\nFixture', "\\N", "HOLD"]])
    return stream.getvalue()


class FixtureTests(unittest.TestCase):
    def codes(self, document, text):
        return {error["code"] for error in checker.check(document, text)["errors"]}

    def test_exact_with_quoted_multiline_and_reordered_rows(self):
        self.assertTrue(checker.check(fixture(), export())["ok"])

    def test_duplicate_missing_unexpected_no_fuzzy_join(self):
        codes = self.codes(fixture(), export([["r1", "x", "", "HOLD"], ["r1", "x", "", "HOLD"], ["R2", " Same name ", "", "READY"]]))
        self.assertTrue({"duplicate_id", "missing_ids", "unexpected_id"} <= codes)

    def test_mapping_and_hold_change(self):
        codes = self.codes(fixture(), export([["r2", "", " Same name ", "READY"], ["r1", 'Beta, "quoted"\nFixture', "\\N", "READY"]]))
        self.assertEqual(codes, {"field_mismatch", "hold_status_changed"})

    def test_null_blank_are_distinct_unless_explicit(self):
        rows = [["r2", " Same name ", "", "READY"], ["r1", 'Beta, "quoted"\nFixture', "", "HOLD"]]
        self.assertIn("field_mismatch", self.codes(fixture(), export(rows)))
        document = fixture()
        document["null_encoding"] = {"mode": "blank_equivalent"}
        self.assertTrue(checker.check(document, export(rows))["ok"])
        rows[1][2] = " "
        self.assertFalse(checker.check(document, export(rows))["ok"])

    def test_bad_headers_and_width(self):
        for headers in [["fixture_id", "Name", "Email", "Email"], ["fixture_id", "Name", "Email"], ["fixture_id", "Name", "Email", "Status", "Extra"]]:
            self.assertEqual(self.codes(fixture(), export([], headers)), {"headers_mismatch"})
        self.assertIn("row_width_mismatch", self.codes(fixture(), export([["r1", "x"]])))
        self.assertIn("missing_ids", self.codes(fixture(), export([])))

    def test_reordered_headers_follow_mapping(self):
        text = export([["HOLD", "r1", "\\N", 'Beta, "quoted"\nFixture'],
                       ["READY", "r2", "", " Same name "]],
                      ["Status", "fixture_id", "Email", "Name"])
        self.assertTrue(checker.check(fixture(), text)["ok"])

    def test_blank_or_padded_id_not_inferred(self):
        for identity, code in [("", "blank_id"), (" ", "blank_id"), ("r1 ", "unexpected_id")]:
            with self.subTest(identity=identity):
                codes = self.codes(fixture(), export([[identity, "x", "", "HOLD"]]))
                self.assertIn(code, codes)
                self.assertIn("missing_ids", codes)

    def test_invalid_fixture(self):
        documents = [[], {}, fixture(), fixture(), fixture(), fixture(), fixture()]
        documents[2]["records"] = []
        documents[3]["records"].append(copy.deepcopy(documents[3]["records"][0]))
        documents[4]["records"][0]["expected"]["email"] = "\\N"
        documents[5]["records"][0]["expected"]["email"] = False
        documents[6]["columns"]["email"] = "Name"
        for document in documents:
            with self.subTest(document=document), self.assertRaises(ValueError):
                checker.check(document, export())

    def test_cli_positive_refusal_and_malformed(self):
        with tempfile.TemporaryDirectory() as directory:
            expected = Path(directory) / "expected.json"
            actual = Path(directory) / "actual.csv"
            expected.write_text(json.dumps(fixture()))
            actual.write_text(export(), newline="")
            command = [sys.executable, str(ROOT / "bin/clay-fixture-check"), "--fixture", str(expected), "--actual", str(actual)]
            success = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(success.returncode, 0, success.stderr)
            verdict = json.loads(success.stdout)
            self.assertTrue(verdict["ok"])
            self.assertEqual(len(verdict["sha256"]["actual"]), 64)
            actual.write_text(export([["r1", "private-sentinel-name", "", "SEND"]]), newline="")
            failure = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(failure.returncode, 1)
            self.assertFalse(json.loads(failure.stdout)["ok"])
            self.assertNotIn("private-sentinel-name", failure.stdout)
            for invalid in ['{"records":[],"records":[]}', '[]', 'not JSON']:
                expected.write_text(invalid)
                failure = subprocess.run(command, capture_output=True, text=True)
                self.assertEqual(failure.returncode, 2)
                self.assertEqual(json.loads(failure.stdout)["errors"][0]["code"], "invalid_input")
                self.assertEqual(failure.stderr, "")
            expected.write_text(json.dumps(fixture()))
            actual.write_text('fixture_id,Name,Email,Status\nr1,"unterminated')
            failure = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(failure.returncode, 2)
            self.assertEqual(json.loads(failure.stdout)["errors"][0]["kind"], "Error")


if __name__ == "__main__":
    unittest.main()

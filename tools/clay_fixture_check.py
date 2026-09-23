#!/usr/bin/env python3
"""Compare an independently prepared destination oracle with an exported CSV.

Schema v1: columns maps expected field names (including stable_id) to exact CSV
headers. records contain stable_id and expected, with every mapped non-ID field.
Expected cells must be strings or null; numeric/boolean rendering is explicit.
null_encoding is {"mode":"token","token":"\\N"} or {"mode":"blank_equivalent"}.
The latter cannot distinguish a null from an empty CSV cell. No normalization,
fuzzy joins, network, writes, or claims about hidden application state.
"""
import argparse
import csv
import hashlib
import io
import json
from pathlib import Path
import sys


SCOPE = "export_content_only"


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate JSON key")
        result[key] = value
    return result


def fixture_schema(document):
    if not isinstance(document, dict) or set(document) != {
        "schema_version", "columns", "null_encoding", "records"
    } or type(document["schema_version"]) is not int or document["schema_version"] != 1:
        raise ValueError("expected fixture schema_version 1 and exact schema keys")
    columns = document["columns"]
    if not isinstance(columns, dict) or "stable_id" not in columns or len(columns) < 2:
        raise ValueError("columns must map stable_id and at least one expected field")
    if any(not isinstance(item, str) or not item.strip()
           for pair in columns.items() for item in pair):
        raise ValueError("column names and headers must be nonempty strings")
    if len(set(columns.values())) != len(columns):
        raise ValueError("column mappings must be one to one")
    encoding = document["null_encoding"]
    if not isinstance(encoding, dict):
        raise ValueError("explicit null_encoding required")
    if encoding == {"mode": "blank_equivalent"}:
        null_token = ""
    elif set(encoding) == {"mode", "token"} and encoding["mode"] == "token" and isinstance(encoding["token"], str) and encoding["token"]:
        null_token = encoding["token"]
    else:
        raise ValueError("null_encoding must be token with nonempty token or blank_equivalent")
    rows = document["records"]
    if not isinstance(rows, list) or not rows:
        raise ValueError("records must be a nonempty list")
    expected = {}
    fields = set(columns) - {"stable_id"}
    for row in rows:
        if not isinstance(row, dict) or set(row) != {"stable_id", "expected"}:
            raise ValueError("each record requires stable_id and expected only")
        identity = row["stable_id"]
        if not isinstance(identity, str) or not identity.strip() or identity == null_token:
            raise ValueError("stable_id must be a nonempty string distinct from null token")
        if identity in expected:
            raise ValueError("duplicate fixture stable_id")
        values = row["expected"]
        if not isinstance(values, dict) or set(values) != fields:
            raise ValueError("every record must specify every mapped expected field")
        for value in values.values():
            if value is not None and not isinstance(value, str):
                raise ValueError("expected cells must be strings or null")
            if encoding["mode"] == "token" and value == null_token:
                raise ValueError("literal expected string collides with null token")
        expected[identity] = values
    return columns, null_token, expected


def check(document, csv_text):
    columns, null_token, expected = fixture_schema(document)
    reader = csv.reader(io.StringIO(csv_text, newline=""), strict=True)
    headers = next(reader, None)
    errors = []
    if headers is None or len(headers) != len(set(headers)) or set(headers) != set(columns.values()):
        return {"ok": False, "scope": SCOPE, "errors": [{"code": "headers_mismatch"}]}
    positions = {field: headers.index(header) for field, header in columns.items()}
    seen = set()
    actual_count = 0
    for row_number, row in enumerate(reader, start=2):
        actual_count += 1
        if len(row) != len(headers):
            errors.append({"code": "row_width_mismatch", "row": row_number})
            continue
        identity = row[positions["stable_id"]]
        if not identity.strip() or identity == null_token:
            errors.append({"code": "blank_id", "row": row_number})
            continue
        if identity in seen:
            errors.append({"code": "duplicate_id", "row": row_number})
        seen.add(identity)
        if identity not in expected:
            errors.append({"code": "unexpected_id", "row": row_number})
            continue
        for field, value in expected[identity].items():
            actual = row[positions[field]]
            wanted = null_token if value is None else value
            if actual != wanted:
                code = "hold_status_changed" if field == "status" and value == "HOLD" else "field_mismatch"
                errors.append({"code": code, "row": row_number, "field": field})
    missing_count = len(set(expected) - seen)
    if missing_count:
        errors.append({"code": "missing_ids", "count": missing_count})
    return {"ok": not errors, "scope": SCOPE, "errors": errors,
            "expected_records": len(expected), "actual_records": actual_count,
            "null_semantics": document["null_encoding"]["mode"]}


class Parser(argparse.ArgumentParser):
    def error(self, message):
        raise ValueError("invalid CLI arguments; use --help")


def main(argv=None):
    try:
        parser = Parser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
        parser.add_argument("--fixture", required=True, help="Independent expected JSON fixture")
        parser.add_argument("--actual", required=True, help="Actual UTF-8 CSV export")
        args = parser.parse_args(argv)
        fixture_bytes = Path(args.fixture).read_bytes()
        actual_bytes = Path(args.actual).read_bytes()
        document = json.loads(fixture_bytes.decode("utf-8-sig"), object_pairs_hook=unique_object)
        verdict = check(document, actual_bytes.decode("utf-8-sig"))
        verdict["sha256"] = {"fixture": hashlib.sha256(fixture_bytes).hexdigest(),
                             "actual": hashlib.sha256(actual_bytes).hexdigest()}
        exit_code = 0 if verdict["ok"] else 1
    except (ValueError, OSError, csv.Error) as error:
        # Never echo source values, file paths, or malformed CSV contents.
        verdict = {"ok": False, "scope": SCOPE,
                   "errors": [{"code": "invalid_input", "kind": type(error).__name__}]}
        exit_code = 2
    print(json.dumps(verdict, ensure_ascii=True, allow_nan=False))
    return exit_code


if __name__ == "__main__":
    sys.exit(main())

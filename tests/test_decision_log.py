"""decision_log: a named Jev call leaves one row, an unnamed one none, an
outcome joins its decision by id, stats bucket right and wrong by confidence,
and a correction in the voice marks only a route Jev made. Jev is stubbed at
the HTTP layer; the log goes to a temp file."""
import io
import json
import os
import sys
import tempfile
from pathlib import Path

os.environ["BOB_DECISIONS"] = os.path.join(tempfile.mkdtemp(), "decisions.jsonl")
os.environ.pop("AMBER_ROOT", None)
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "bin" / "lib"))
import decision_log  # noqa: E402
import jev  # noqa: E402

failed = 0


def check(name, ok):
    global failed
    print(("ok   " if ok else "FAIL ") + name)
    failed += not ok


class Reply(io.BytesIO):
    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False


def main() -> int:
    jev._key = "test-key"
    answer = {"dest": {"choice": "assistant", "probabilities": {"assistant": 0.83, "terminal": 0.17}}}
    jev.urllib.request.urlopen = lambda req, timeout: Reply(json.dumps({"answers": answer}).encode())

    jev.ask({"spoken": "what's the weather"}, {}, decision="route")
    jev.ask({"spoken": "bulk row"}, {})
    rows = decision_log.rows()
    check("a named call leaves one row, an unnamed one none", len(rows) == 1 and rows[0]["decision"] == "route")
    check("the row keeps the choice and its probability", rows[0]["answers"]["dest"] == {"choice": "assistant", "p": 0.83})
    check("the state is kept as a short excerpt", "weather" in rows[0]["state"] and len(rows[0]["state"]) <= 300)

    def down(req, timeout):
        raise OSError("offline")
    jev.urllib.request.urlopen = down
    check("Jev down still answers None", jev.ask("x", {}, decision="route") is None)
    check("and the failure is logged", decision_log.rows()[-1]["error"] == "OSError")

    first = rows[0]["id"]
    check("an outcome must be right, wrong or unknown", not decision_log.outcome(first, "great"))
    decision_log.outcome(first, "wrong", "corrected to terminal")
    joined = {d["id"]: d for d in decision_log.joined()}
    check("an outcome joins its decision by id", joined[first]["outcome"] == "wrong")
    s = decision_log.stats()["route"]
    check("stats count calls and errors", s["calls"] == 2 and s["errors"] == 1)
    check("stats bucket by confidence", s["buckets"] == {"0.8": {"right": 0, "wrong": 1}})

    listen = (Path(__file__).resolve().parent.parent / "bin" / "hud-listen").read_text()
    check("the voice marks a correction only against a Jev route",
          'decision.reason == "correction" and (memory["last"] or {}).get("reason") == "classifier"' in listen)
    print("all passed" if not failed else f"{failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())

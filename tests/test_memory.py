#!/usr/bin/env python3
"""~/.bob/memory, against a temp dir.

    python3 tests/test_memory.py
"""
import importlib.util
import json
import os
import pathlib
import sys
import tempfile
import time
from datetime import datetime, timedelta, timezone
from importlib.machinery import SourceFileLoader

sys.dont_write_bytecode = True
# Set before import, and kept at module level rather than inside main():
# voice_memory.py reads BOB_MEMORY_DIR once at import to build its MEMORY
# constant, so this has to run during pytest collection too, or a collecting
# run reads and writes the developer's real ~/.bob/memory.
mem = pathlib.Path(tempfile.mkdtemp())
os.environ["BOB_MEMORY_DIR"] = str(mem)
ROOT = pathlib.Path(__file__).resolve().parent.parent
_src = ROOT / "bin" / "lib" / "voice_memory.py"
spec = importlib.util.spec_from_loader("voice_memory", SourceFileLoader("voice_memory", str(_src)))
vm = importlib.util.module_from_spec(spec)
spec.loader.exec_module(vm)

PASSED = FAILED = 0


def check(name, cond, detail=""):
    global PASSED, FAILED
    if cond:
        PASSED += 1
        print(f"  pass  {name}")
    else:
        FAILED += 1
        print(f"  FAIL  {name}  {detail}")


def iso(seconds_ago=0):
    return (datetime.now(timezone.utc) - timedelta(seconds=seconds_ago)).isoformat(timespec="seconds")


def main() -> int:
    check("memory dir is the env override", vm.MEMORY == mem)
    check("empty memory has no last", vm.last() is None)
    check("empty memory has no warm dest", vm.warm(time.time()) is None)
    check("empty project is a dict", vm.project() == {})

    vm.append({"t": iso(700), "via": "voice", "text": "look up rust traits", "dest": "browser"})
    vm.append({"t": iso(30), "via": "voice", "text": "add tests", "dest": "terminal"})
    check("last is the newest line", vm.last()["text"] == "add tests")
    check("recent returns newest last", [e["text"] for e in vm.recent(5)] == ["look up rust traits", "add tests"])
    check("recent filters by dest", [e["text"] for e in vm.recent(5, "browser")] == ["look up rust traits"])
    check("terminal is warm 30 s later", vm.warm(time.time()) == "terminal")
    check("nothing is warm 11 minutes later", vm.warm(time.time() + 660) is None)
    check("terminal_count counts terminal lines", vm.terminal_count() == 1)

    check("update_project merges", vm.update_project({"tty": "/dev/ttys002"})["tty"] == "/dev/ttys002")
    check("a second patch keeps the first", vm.update_project({"summary": "a signaler"})["tty"] == "/dev/ttys002")
    check("project reads back", vm.project()["summary"] == "a signaler")

    check("no draft file is None", vm.draft(time.time()) is None)
    (mem / "draft.json").write_text(json.dumps({"tty": "/dev/ttys002", "text": "hi", "t": iso(10)}))
    check("a young draft is returned", vm.draft(time.time())["text"] == "hi")
    check("an old draft is None", vm.draft(time.time() + 400) is None)
    (mem / "draft.json").write_text("not json")
    check("a corrupt draft is None", vm.draft(time.time()) is None)

    vm.CAP = 5
    for i in range(8):
        vm.append({"t": iso(), "via": "voice", "text": f"line {i}", "dest": "assistant"})
    lines = (mem / "transcript.jsonl").read_text().splitlines()
    check("rotation keeps the newest CAP lines", len(lines) == 5 and json.loads(lines[-1])["text"] == "line 7", str(lines))

    print(f"\n{PASSED} passed, {FAILED} failed")
    return 1 if FAILED else 0


if __name__ == "__main__":
    sys.exit(main())

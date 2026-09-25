"""web-record: ids in a URL become {id}, a click shortly before a page counts
as the step that led there, and the JavaScript never reads a field's value.
Fixture recording; no Chrome."""
import json
import os
import subprocess
import sys
import tempfile
import time
from importlib.machinery import SourceFileLoader
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
failed = 0


def check(name, ok, got=None):
    global failed
    print(("ok   " if ok else "FAIL ") + name + ("" if ok else f"  got {got!r}"))
    failed += not ok


def main() -> int:
    tmp = tempfile.mkdtemp()
    os.environ["WEB_RECORD_DIR"] = tmp
    m = SourceFileLoader("web_record", str(ROOT / "bin" / "web-record")).load_module()
    check("course ids become {id}", m.template("https://h.edu/ultra/courses/_974077_1/cl/outline#x") ==
          "/ultra/courses/{id}/cl/outline")
    check("the page script never reads a value", ".value" not in m.JS)
    check("the page script skips inputs and passwords", "input" not in m.JS)
    d = Path(tmp) / "h.edu"
    d.mkdir()
    t = time.time()
    rows = [{"t": t, "kind": "page", "url": "https://h.edu/ultra/stream", "title": "Activity"},
            {"t": t + 5, "kind": "click", "label": "Grades", "role": "a", "href": None, "from": "/ultra/stream"},
            {"t": t + 6, "kind": "page", "url": "https://h.edu/ultra/grades", "title": "Grades"},
            {"t": t + 60, "kind": "click", "label": "Old click", "role": "a", "href": None, "from": "/ultra/grades"},
            {"t": t + 90, "kind": "page", "url": "https://h.edu/ultra/courses/_1_1/cl/outline", "title": "C"}]
    (d / "2026-09-25.jsonl").write_text("\n".join(json.dumps(r) for r in rows) + "\n")
    out = subprocess.run([sys.executable, str(ROOT / "bin" / "web-record"), "show", "h.edu"],
                         capture_output=True, text=True, env={**os.environ}).stdout
    check("pages are listed by shape", "/ultra/courses/{id}/cl/outline" in out, out)
    check("a click right before a page is the step to it", "[Grades]" in out and "-> /ultra/grades" in out, out)
    check("a stale click is not credited", "Old click" not in out, out)
    st = subprocess.run([sys.executable, str(ROOT / "bin" / "web-record"), "status"], capture_output=True,
                        text=True, env={**os.environ}).stdout
    check("status with nothing running says so", "not recording" in st, st)
    print("all passed" if not failed else f"{failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())

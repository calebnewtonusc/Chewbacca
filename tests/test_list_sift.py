"""list-sift: --where runs before any call, contact channels are never sent,
scores above the line are kept, Jev errors are counted not kept, and a rerun
retries only what has no score. Offline: Jev is a stub."""
import csv
import importlib.machinery
import importlib.util
import io
import sys
import tempfile
from contextlib import redirect_stdout
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
loader = importlib.machinery.SourceFileLoader("list_sift", str(ROOT / "bin/list-sift"))
spec = importlib.util.spec_from_loader("list_sift", loader)
sift = importlib.util.module_from_spec(spec)
loader.exec_module(sift)


def main():
    failures = 0

    def check(name, cond):
        nonlocal failures
        print(("  ok    " if cond else "  FAIL  ") + name)
        failures += 0 if cond else 1

    with tempfile.TemporaryDirectory() as t:
        src = Path(t) / "list.csv"
        with src.open("w", newline="") as f:
            w = csv.writer(f)
            w.writerow(["full_name", "title", "state", "Email", "phone_number", "LinkedIn URL"])
            for i in range(10):
                w.writerow([f"P{i}", "Associate" if i == 6 else "Partner" if i % 2 else "Analyst", "TX" if i < 8 else "NY",
                            f"p{i}@x.example", "555", "li/p"])
        seen = []

        def ask(state, questions):
            seen.append(state["contact"])
            if state["contact"]["title"] == "Associate":
                return None
            return {"fit": {"noul": 0.9 if state["contact"]["title"] == "Partner" else 0.1}}

        out = Path(t) / "out.csv"
        with redirect_stdout(io.StringIO()):
            code = sift.main([str(src), "--keep", "partners", "--where", "state=tx", "--out", str(out)], ask=ask)
        rows = list(csv.DictReader(out.open()))
        check("--where drops rows before any call", len(seen) == 8 and all(c["state"] == "TX" for c in seen))
        check("names, email, phone and LinkedIn are never sent",
              all(set(c) == {"title", "state"} for c in seen))
        check("scores above the line are kept", {r["full_name"] for r in rows if r["sift_keep"] == "1"} == {"P1", "P3", "P5", "P7"})
        check("a Jev error is counted, not written, and fails the run", "P6" not in {r["full_name"] for r in rows} and code == 1)

        seen.clear()
        with redirect_stdout(io.StringIO()):
            sift.main([str(src), "--keep", "partners", "--where", "state=TX", "--out", str(out)], ask=ask)
        check("a rerun judges only the row Jev failed on", [c["title"] for c in seen] == ["Associate"])

        buf = io.StringIO()
        with redirect_stdout(buf):
            sift.main([str(src), "--keep", "x", "--where", "state=TX", "--estimate"], ask=lambda s, q: 1 / 0)
        check("--estimate counts and calls nothing", '"rows": 8' in buf.getvalue())
        with redirect_stdout(io.StringIO()):
            code = sift.main([str(src), "--keep", "x", "--where", "nope=1", "--estimate"])
        check("an unknown --where column is refused", code == 2)
        check("the input is untouched", src.read_text().count("\n") == 11)
    print()
    print("list-sift judges only what survives the facts" if not failures else f"{failures} failed")
    return failures


if __name__ == "__main__":
    sys.exit(main())

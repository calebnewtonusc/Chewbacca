"""bb: course and page words build a read address, an item's own name opens
the item, an ambiguous ask is offered not opened, and Jev is only asked when
the words leave it open. Fixture coursework; Jev is a stub."""
import json
import os
import sys
import tempfile
from pathlib import Path

tmp = Path(tempfile.mkdtemp())
os.environ["COURSEWORK_DIR"] = str(tmp)
os.environ["BOB_DECISIONS"] = str(tmp / "d.jsonl")
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "bin" / "lib"))
import bb  # noqa: E402

failed = 0


def check(name, ok, got=None):
    global failed
    print(("ok   " if ok else "FAIL ") + name + ("" if ok else f"  got {got!r}"))
    failed += not ok


def build():
    (tmp / "courses").mkdir()
    (tmp / "courses" / "anth-2351.yml").write_text(
        'code: ANTH 2351\ntitle: Cultural Anthropology\nblackboard_id: "X-ANTH"\nblackboard_internal_id: "_1_1"\n')
    (tmp / "courses" / "span-1412.yml").write_text(
        'code: SPAN 1412\ntitle: Spanish II\nblackboard_id: "X-SPAN"\nblackboard_internal_id: "_2_1"\n')
    raw = tmp / ".ingest" / "acc" / "raw"
    raw.mkdir(parents=True)
    anth = [{"id": "_10_1", "title": "Homework 2-Ethnocentrism", "contentHandler": {"id": "resource/x-bb-asmt-test-link"}},
            {"id": "_11_1", "title": "Final Paper", "contentHandler": {"id": "resource/x-bb-asmt-test-link"}},
            {"id": "_12_1", "title": "Discussion 1~Introductions", "contentHandler": {"id": "resource/x-bb-courselink"}},
            {"id": "_13_1", "title": "Online Tutoring", "contentHandler": {"id": "resource/x-bb-externallink"}}]
    span = [{"id": "_20_1", "title": "Week 3 folder", "contentHandler": {"id": "resource/x-bb-folder"}}]
    for name, rows in (("X-ANTH", anth), ("X-SPAN", span)):
        (raw / f"course-{name}.json").write_text(json.dumps({"contents": {"json": {"results": rows}}}))


def main() -> int:
    build()
    never = lambda s, q: (_ for _ in ()).throw(AssertionError("Jev asked"))  # noqa: E731
    base = "https://acconline.austincc.edu/ultra"
    cases = [
        ("anth discussions", f"{base}/courses/_1_1/engagement"),
        ("spanish grades", f"{base}/courses/_2_1/grades"),
        ("anthropology content", f"{base}/courses/_1_1/outline"),
        ("homework 2", f"{base}/courses/_1_1/assessment/_10_1/overview?courseId=_1_1"),
        ("open the anth final paper", f"{base}/courses/_1_1/assessment/_11_1/overview?courseId=_1_1"),
        ("discussion 1", f"{base}/courses/_1_1/engagement"),
        ("spanish week 3", f"{base}/courses/_2_1/document/_20_1?view=content&state=view"),
        ("blackboard calendar", f"{base}/calendar"),
    ]
    for said, want in cases:
        got = bb.resolve(said, ask=never).get("url")
        check(f"{said!r}", got == want, got)
    got = bb.resolve("grades", ask=never)
    check("no course named: asks which class", "which class" in got.get("why", ""), got)
    check("noise items are dropped", all(i["title"] != "Online Tutoring" for i in bb.items(bb.courses()[0])))

    def jev(choice_title, p):
        def ask(state, questions):
            crit = questions["where"]["criteria"]
            key = next(k for k, v in crit.items() if choice_title in v)
            other = next(k for k in crit if k != key)
            return {"where": {"choice": key, "probabilities": {key: p, other: 1 - p}}}
        return ask

    got = bb.resolve("where do I turn in my anthropology paper", ask=jev("Final Paper", 0.9))
    check("loose words: Jev picks the item", got.get("url", "").endswith("/assessment/_11_1/overview?courseId=_1_1"), got)
    got = bb.resolve("that anthropology thing", ask=jev("Final Paper", 0.4))
    check("a weak Jev answer is offered, not opened", "ask" in got, got)
    got = bb.resolve("anthropology stuff", ask=lambda s, q: None)
    check("Jev down: the course's content page", got.get("url") == f"{base}/courses/_1_1/outline", got)
    print("all passed" if not failed else f"{failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())

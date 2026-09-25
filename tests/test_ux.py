"""ux-do: only named controls reach Jev, it acts at the floor and asks below
it, a send is found and never pressed, and with Jev down only a unique exact
label acts. Fixture snapshot; Jev and agent-desktop are stubs."""
import json
import os
import sys
import tempfile
from pathlib import Path

sys.dont_write_bytecode = True
os.environ["BOB_DECISIONS"] = os.path.join(tempfile.mkdtemp(), "d.jsonl")
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "bin" / "lib"))
import ux  # noqa: E402

SNAP = {"ok": True, "data": {"tree": {"role": "window", "name": "Site", "children": [
    {"ref_id": "@s:e1", "role": "button", "name": "Back"},
    {"ref_id": "@s:e2", "role": "statictext", "name": "Welcome"},
    {"role": "navigation", "name": "Menu bar", "children": [
        {"ref_id": "@s:e3", "role": "link", "name": "About me"},
        {"ref_id": "@s:e4", "role": "link", "name": "Contact"}]},
    {"ref_id": "@s:e5", "role": "textfield", "name": "Search", "value": ""},
    {"ref_id": "@s:e6", "role": "button", "name": "Send message"},
    {"ref_id": "@s:e7", "role": "checkbox", "name": "Dark mode"},
    {"ref_id": "@s:e8", "role": "button", "name": ""},
    {"ref_id": "@s:e9", "role": "button", "name": "Back"},
]}}}
failed = 0


def check(name, ok):
    global failed
    print(("ok   " if ok else "FAIL ") + name)
    failed += not ok


def jev_picks(label_part, p):
    def ask(state, questions):
        crit = questions["control"]["criteria"]
        key = next(k for k, v in crit.items() if label_part in v)
        return {"control": {"choice": key, "probabilities": {key: p, "none": 1 - p}}}
    return ask


def main() -> int:
    found = ux.controls(SNAP["data"]["tree"])
    names = [c["name"] for c in found]
    check("static text, unnamed and duplicate controls are dropped", names ==
          ["Back", "About me", "Contact", "Search", "Send message", "Dark mode"])
    check("a control carries the region it sits in", found[1]["in"] == "Menu bar")

    r = ux.do("go to the about section", app="Site", dry=True, ask=jev_picks("About me", 0.9), snapshot=SNAP)
    check("confident: would act on the chosen control", r["status"] == "would act" and "About me" in r["control"])

    r = ux.do("where can I reach him", app="Site", dry=True, ask=jev_picks("Contact", 0.55), snapshot=SNAP)
    check("between the floors: asks, never acts", r["status"] == "ask")

    r = ux.do("print this", app="Site", dry=True, ask=jev_picks("Back", 0.1), snapshot=SNAP)
    check("below the ask floor: not found", r["status"] == "not found")

    r = ux.do("send it", app="Site", ask=jev_picks("Send message", 0.99), snapshot=SNAP)
    check("a send is found and left to the person", r["status"] == "yours to press")

    def none_ask(state, questions):
        return {"control": {"choice": "none", "probabilities": {"none": 0.9, "c0": 0.1}}}

    r = ux.do("open settings", app="Site", dry=True, ask=none_ask, snapshot=SNAP)
    check("jev choosing none acts on nothing", r["status"] == "not found")

    r = ux.do("contact", app="Site", dry=True, ask=lambda s, q: {}, snapshot=SNAP)
    check("Jev down: a unique exact label still acts", r["status"] == "would act" and r["via"].startswith("exact"))
    r = ux.do("get in touch", app="Site", dry=True, ask=lambda s, q: {}, snapshot=SNAP)
    check("Jev down: anything else acts on nothing", r["status"] == "not found")

    calls = []
    ux.run = lambda args: calls.append(args) or {"ok": True}
    ux.VERIFY_S, ux.VERIFY_EVERY_S = 0.05, 0.01
    unchanged = lambda: SNAP  # noqa: E731
    ux.do("dark mode on", app="Site", ask=jev_picks("Dark mode", 0.95), snapshot=SNAP, observe=unchanged)
    ux.do("search box", app="Site", text="flights", ask=jev_picks("Search", 0.95), snapshot=SNAP, observe=unchanged)
    ux.do("about", app="Site", ask=jev_picks("About me", 0.95), snapshot=SNAP, observe=unchanged)
    check("checkbox toggles, field types, link clicks, all by ref",
          calls == [["toggle", "@s:e7"], ["type", "@s:e5", "flights"], ["click", "@s:e3"]])

    def after(change):
        tree = json.loads(json.dumps(SNAP))
        change(tree["data"]["tree"]["children"])
        return lambda: tree

    r = ux.do("about", app="Site", ask=jev_picks("About me", 0.95), snapshot=SNAP, observe=unchanged)
    check("a press that changes nothing is not done", r["status"] == "no change")
    r = ux.do("about", app="Site", ask=jev_picks("About me", 0.95), snapshot=SNAP,
              observe=after(lambda kids: kids.append({"ref_id": "@t:e1", "role": "link", "name": "Home"})))
    check("a press the window shows is done", r["status"] == "done" and r["why"] == "the window changed")
    r = ux.do("dark mode", app="Site", ask=jev_picks("Dark mode", 0.95), snapshot=SNAP,
              observe=after(lambda kids: kids[5].update(states=["checked"])))
    check("a toggle is done only when its state flips", r["status"] == "done" and "flipped" in r["why"])
    r = ux.do("search", app="Site", text="flights", ask=jev_picks("Search", 0.95), snapshot=SNAP,
              observe=after(lambda kids: kids[3].update(value="flights")))
    check("typing is done only when the text is in the field", r["status"] == "done")
    r = ux.do("about", app="Site", text="x", ask=jev_picks("About me", 0.95), snapshot=SNAP)
    check("text into a link is refused", r["status"] == "error")

    r = ux.do("x", app="Site", snapshot={"ok": False, "error": {"message": "WINDOW_NOT_FOUND"}})
    check("no window says so", r["status"] == "error" and "WINDOW" in r["why"])

    print("all passed" if not failed else f"{failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())

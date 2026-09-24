"""Do what the person meant in any app window, by Jev, without the mouse.

The pieces existed apart. agent-desktop reads any window's accessibility tree
with stable refs and presses a control by accessibility action, so the real
cursor and the focused window never move. tests/eval_ground_jev.py showed Jev
picking the right control from how a person says it ("I want to rent out my
place" for "Become a host"), and that a confidence line separates acting from
asking. Nothing joined them, so the voice fell back to label matching, which
needs the person to say the button's exact words.

The shape is the grounding eval's: one Choice over the window's controls,
act at ACT_FLOOR or above, offer the top two between ASK_FLOOR and it, and
say nothing matched below. Jev down: an exact, unique label match still acts,
because that one is a fact.

A send, a payment, a delete or a submit is never pressed here. It is found
and handed back, and the person presses it.
"""
from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import jev  # noqa: E402

AGENT_DESKTOP = "agent-desktop"
# Roles a person can act on. Static text, groups and web areas are what made
# a Chrome window 439 elements on 2026-09-24; these leave the controls.
ACTIONABLE = {
    "button", "link", "textfield", "textarea", "searchfield", "combobox", "checkbox",
    "radiobutton", "radio", "menuitem", "menubutton", "popupbutton", "tab", "switch",
    "slider", "cell", "row", "disclosuretriangle", "incrementor", "togglebutton",
}
MAX_OPTIONS = 255  # the API's ceiling on choices
# From tests/eval_ground_jev.py, 2026-09-23 (results kept private under
# TypeSafe's agreement 2.3(f)): acting at 0.7 never pressed a wrong control on
# that set. ASK_FLOOR is guessed, never measured.
ACT_FLOOR = 0.7
ASK_FLOOR = 0.3
# Words on a control that make pressing it the person's decision, never ours.
IRREVERSIBLE = re.compile(
    r"\b(send|submit|pay|purchase|buy|order|place order|checkout|check out|delete|remove|"
    r"unsubscribe|confirm|transfer|post|publish|sign out|log out|cancel subscription)\b", re.I)
TIMEOUT_S = 20


def run(args: list[str]) -> dict:
    out = subprocess.run([AGENT_DESKTOP, *args], capture_output=True, text=True, timeout=TIMEOUT_S)
    try:
        return json.loads(out.stdout)
    except ValueError:
        return {"ok": False, "error": {"message": (out.stderr or out.stdout).strip()[:300]}}


def front_app() -> str | None:
    out = subprocess.run(["osascript", "-e", 'tell application "System Events" to get name of '
                          'first application process whose frontmost is true'],
                         capture_output=True, text=True, timeout=5)
    return out.stdout.strip() or None


def controls(tree: dict) -> list[dict]:
    """Actionable, named, de-duplicated, in reading order."""
    found, seen = [], set()

    def walk(node: dict, context: str):
        role = (node.get("role") or "").lower()
        name = " ".join((node.get("name") or "").split())[:80]
        value = " ".join(str(node.get("value") or "").split())[:60]
        ref = node.get("ref_id")
        if ref and role in ACTIONABLE and (name or value):
            key = (role, name, value)
            if key not in seen:
                seen.add(key)
                found.append({"ref": ref, "role": role, "name": name, "value": value, "in": context,
                              "states": node.get("states") or []})
        here = name if role in {"navigation", "dialog", "sheet", "toolbar", "menu", "list", "table",
                                "form", "banner", "tabgroup"} and name else context
        for child in node.get("children") or []:
            walk(child, here)

    walk(tree, "")
    return found


def label(c: dict) -> str:
    parts = [f"{c['role']}: {c['name'] or c['value']}"]
    if c["value"] and c["name"]:
        parts.append(f"(value {c['value']})")
    if c["in"]:
        parts.append(f"in {c['in']}")
    return " ".join(parts)


def choose(intent: str, app: str, found: list[dict], ask=None) -> dict:
    """{"pick": control|None, "p": float, "alternatives": [...], "via": str}."""
    menu = found[:MAX_OPTIONS]
    exact = [c for c in menu if intent.strip().lower() in {c["name"].lower(), c["value"].lower()}]
    if ask is None:
        if not (jev.api_key() and jev.allowed()):
            if len(exact) == 1:
                return {"pick": exact[0], "p": 1.0, "alternatives": [], "via": "exact label"}
            return {"pick": None, "p": 0.0, "alternatives": [], "via": "no Jev and no unique label"}

        def ask(state, questions):
            return jev.ask(state, questions, timeout=5.0)
    criteria = {f"c{i}": label(c) for i, c in enumerate(menu)}
    criteria["none"] = "none of these controls does what the person asked"
    answers = ask({"asked": intent, "app": app}, {"control": {"type": "choice", "instructions": {
        "question": f"The person asked, about the {app} window in front of them: `asked`. "
                    "Which one control should be used to do it?",
        "note": "People describe what they want, not the words on the button. Judge by what the control "
                "does. If the request needs a control that is not listed, choose none."},
        "criteria": criteria}})
    answer = (answers or {}).get("control") or {}
    probs = answer.get("probabilities") or {}
    if not answer:
        if len(exact) == 1:
            return {"pick": exact[0], "p": 1.0, "alternatives": [], "via": "exact label, Jev down"}
        return {"pick": None, "p": 0.0, "alternatives": [], "via": "Jev down"}
    ranked = sorted(((k, float(v)) for k, v in probs.items() if k != "none"), key=lambda kv: -kv[1])
    alts = [{**menu[int(k[1:])], "p": round(v, 3)} for k, v in ranked[:2] if k[1:].isdigit()]
    choice = answer.get("choice")
    p = float(probs.get(choice, 0.0))
    if choice == "none" or not (choice or "").startswith("c"):
        return {"pick": None, "p": p, "alternatives": alts, "via": "jev chose none"}
    return {"pick": menu[int(choice[1:])], "p": p, "alternatives": alts, "via": "jev"}


def act(control: dict, text: str | None) -> dict:
    role, ref = control["role"], control["ref"]
    if text is not None:
        if role not in {"textfield", "textarea", "searchfield", "combobox"}:
            return {"ok": False, "error": {"message": f"{role} does not take text"}}
        return run(["type", ref, text])
    if role in {"checkbox", "switch", "togglebutton"}:
        return run(["toggle", ref])
    if role in {"textfield", "textarea", "searchfield"}:
        return run(["focus", ref])
    return run(["click", ref])


def do(intent: str, app: str | None = None, text: str | None = None, dry: bool = False, ask=None,
       snapshot=None) -> dict:
    app = app or front_app()
    if not app:
        return {"status": "error", "why": "no app in front"}
    snap = snapshot if snapshot is not None else run(["snapshot", "--app", app, "-i", "--compact"])
    if not snap.get("ok"):
        return {"status": "error", "why": (snap.get("error") or {}).get("message", "snapshot failed")}
    found = controls((snap.get("data") or {}).get("tree") or {})
    if not found:
        return {"status": "error", "why": f"no controls readable in {app}"}
    c = choose(intent, app, found, ask=ask)
    pick, p = c["pick"], c["p"]
    base = {"app": app, "controls": len(found), "p": round(p, 3), "via": c["via"],
            "alternatives": [label(a) + f" [{a['p']}]" for a in c["alternatives"]]}
    if pick is None or p < ASK_FLOOR:
        return {**base, "status": "not found"}
    base["control"] = label(pick)
    if p < ACT_FLOOR:
        return {**base, "status": "ask"}
    if IRREVERSIBLE.search(f"{pick['name']} {pick['value']}"):
        return {**base, "status": "yours to press", "why": "a send, payment, delete or submit"}
    if dry:
        return {**base, "status": "would act"}
    result = act(pick, text)
    if not result.get("ok"):
        return {**base, "status": "error", "why": (result.get("error") or {}).get("message", "action failed")}
    return {**base, "status": "done"}

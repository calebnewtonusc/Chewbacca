"""Run one jev-ultrafast goal in the user's Chrome, with Chewbacca's floor on top.

Executed by `bin/jev-browse` with the jev-ultrafast environment's Python, so
`jev_ultrafast` imports from its own checkout. Reads one JSON request on stdin,
writes progress lines to stderr and one JSON result to stdout.

THE FLOOR. jev-ultrafast will press whatever Jev picks. A send, a pay, a delete
or a submit stays the person's in this kit (hud-agent.md, "a send ... stays
theirs: get to the button, then ask"), so the executor is wrapped: a click whose
label reads like one of those is not executed, and the run stops with
`yours_to_press` naming the control. This is code, not a sentence in the goal,
because a model can ignore a sentence. `allow_commit` lifts it for one run.
"""
import json
import re
import sys
import time

COMMIT = re.compile(
    r"\b(send|submit|post|publish|pay|purchase|buy|checkout|check out|place order|order now|book|reserve|"
    r"delete|remove|archive|unsubscribe|cancel (my )?(subscription|plan|account)|sign in|log in|login|"
    r"sign up|confirm|apply|transfer|withdraw|donate|invite|share|merge|deploy|run workflow|run all|"
    r"run column|run rows?|enrich)\b",
    re.I,
)


QUOTED = re.compile(r'"([^"\n]{1,500})"|\u201c([^\u201d\n]{1,500})\u201d')


def quoted(goal: str) -> list[str]:
    """Every literal string in the goal, in order, deduplicated."""
    out = []
    for a, b in QUOTED.findall(goal or ""):
        value = a or b
        if value not in out:
            out.append(value)
    return out


def jev_pick_value(context, candidates, post_json, validate_choice, api_key):
    """Which quoted string goes in this field: a choice, so Jev answers it. No text model."""
    ids = [str(i) for i in range(len(candidates))]
    body = {
        "model": "jev-latest",
        "state": {"field": context.get("field"), "page": {"title": (context.get("page") or {}).get("title", "")},
                  "recent_actions": context.get("recent_actions", [])},
        "questions": {"value": {
            "type": "choice",
            "criteria": {i: {"text": c} for i, c in zip(ids, candidates)},
            "instructions": {"goal": context.get("goal", ""),
                             "rule": "Pick the quoted value the goal means for THIS field, by its label."},
        }},
    }
    started = time.perf_counter()
    result = post_json("https://api.typesafe.ai/v1/systemone", api_key, body)
    answer = validate_choice(result["answers"].get("value", {}), ids)
    return candidates[int(answer["choice"])], {
        "model": "jev-pick-from-goal", "latency_ms": round((time.perf_counter() - started) * 1000),
        "confidence": answer["confidence"], "usage": result.get("usage", {}),
    }


def field_value(context, pick):
    """The text for a field comes from the goal, never from a generator.

    One quoted string: typed as written, zero calls. Several: Jev picks which
    one belongs in this field. None: stop and say so, because the agent that
    wrote the goal already knows the text and should have quoted it.
    """
    candidates = quoted(context.get("goal", ""))
    if not candidates:
        raise ValueError('This step types into a field; put the exact text in quotes in the goal, e.g. search for "Series A".')
    if len(candidates) == 1:
        return candidates[0], {"model": "literal-from-goal", "latency_ms": 0, "usage": {}}
    return pick(context, candidates)


class YoursToPress(Exception):
    def __init__(self, label):
        super().__init__(label)
        self.label = label


def committing(action) -> bool:
    kind = (action or {}).get("kind")
    if kind not in ("click", "select"):
        return False
    return bool(COMMIT.search(str(action.get("label") or "")))


def main() -> int:
    request = json.loads(sys.stdin.read())
    from jev_ultrafast import Agent
    from jev_ultrafast import browser as jb

    if not request.get("allow_commit"):
        original = jb.Browser.act

        def guarded(self, action, page, text=None):
            if committing(action):
                raise YoursToPress(str(action.get("label") or ""))
            return original(self, action, page, text)

        jb.Browser.act = guarded

    import os
    from jev_ultrafast import agent as ja
    from jev_ultrafast import model as jm

    def pick(context, candidates):
        return jev_pick_value(context, candidates, jm.post_json, jm.validate_choice, os.environ["TYPESAFE_API_KEY"])

    ja.field_text = lambda context: field_value(context, pick)

    started = time.perf_counter()
    deadline = started + float(request.get("max_seconds") or 180)
    result = {"status": "failed", "url": request["url"], "actions": [], "decisions": 0}
    agent = None
    try:
        agent = Agent(request["url"], request["goals"])
        state = None
        for state in agent.run():
            line = f"{state['elapsed_ms']:>6} ms  {len(state['history'])} actions  {state['status']}"
            print(line, file=sys.stderr, flush=True)
            if time.perf_counter() > deadline:
                result["status"] = "timeout"
                break
        if state:
            result.update(
                status=result["status"] if result["status"] == "timeout" else state["status"],
                url=state["page"]["url"], title=state["page"].get("title", ""),
                actions=[{k: h.get(k) for k in ("action", "kind", "text")} for h in state["history"]],
                decisions=len(state["decisions"]), elapsed_ms=state["elapsed_ms"],
            )
    except YoursToPress as stop:
        state = agent.state if agent else {}
        result.update(
            status="yours_to_press", control=stop.label,
            url=(state.get("page") or {}).get("url", request["url"]),
            actions=[{k: h.get(k) for k in ("action", "kind", "text")} for h in state.get("history", [])],
            decisions=len(state.get("decisions", [])),
        )
    except Exception as err:  # noqa: BLE001
        result.update(status="failed", error=f"{type(err).__name__}: {err}"[:400])
    finally:
        if agent and not request.get("keep_open"):
            try:
                agent.close()
            except Exception:  # noqa: BLE001
                pass
    result["elapsed_ms"] = result.get("elapsed_ms") or round((time.perf_counter() - started) * 1000)
    # DONE is Jev's claim, not proof (jev-ultrafast's own AGENTS.md). Say so.
    if result["status"] == "done":
        result["verify"] = "Jev chose DONE; read the page before reporting success"
    print(json.dumps(result))
    return 0 if result["status"] in ("done", "yours_to_press") else 1


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""The agent board without Claude Code or Jev: dict events in, an injected
`ask` in place of the network. Run: python3 tests/test_agent_board.py"""
import json
import sys
import tempfile
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "bin" / "lib"))
import agent_board as ab  # noqa: E402

PASSED = 0
FAILED = 0


def check(name: str, cond: bool, detail: str = "") -> None:
    global PASSED, FAILED
    if cond:
        PASSED += 1
        print(f"  pass  {name}")
    else:
        FAILED += 1
        print(f"  FAIL  {name}  {detail}")


def ev(name: str, session: str, cwd: str, t: float, **extra) -> dict:
    return {"event": name, "session": session, "cwd": cwd, "t": t, **extra}


def main() -> int:
    print("fold")
    b = {}
    b = ab.fold(b, ev("PreToolUse", "s1", "/code/chewbacca", 100, summary="npm test"))
    b = ab.fold(b, ev("PreToolUse", "s2", "/code/clay-map", 101, summary="Edit MAP.md"))
    b = ab.fold(b, ev("PermissionRequest", "s2", "/code/clay-map", 102, summary="git push"))
    check("two sessions, one per id", set(b) == {"s1", "s2"})
    check("folder comes from cwd", b["s1"]["folder"] == "chewbacca")
    check("a permission prompt is waiting with its summary",
          b["s2"]["state"] == "waiting" and b["s2"]["text"] == "git push")
    b = ab.fold(b, ev("Stop", "s1", "/code/chewbacca", 103, summary="Tests pass."))
    check("stop is done with its sentence", b["s1"]["state"] == "done" and b["s1"]["text"] == "Tests pass.")
    b = ab.fold(b, ev("SessionEnd", "s1", "/code/chewbacca", 104))
    check("session end removes it", set(b) == {"s2"})
    check("an entry with no session is ignored", ab.fold(b, ev("Stop", "", "/x", 105)) == b)

    print("expire and order")
    b = {}
    b = ab.fold(b, ev("PreToolUse", "old", "/code/old", 0, summary="ls"))
    b = ab.fold(b, ev("Stop", "a", "/code/a", 9000, summary="Done."))
    b = ab.fold(b, ev("PreToolUse", "r", "/code/r", 9001, summary="pytest"))
    b = ab.fold(b, ev("PermissionRequest", "w", "/code/w", 8000, summary="rm build"))
    live = ab.expire(b, 9100)
    check("two hours of silence drops a session", "old" not in live and len(live) == 3)
    check("waiting first, then running, then done", [s["session"] for s in ab.ordered(live)] == ["w", "r", "a"])
    check("the summary leads with who is blocked on you",
          ab.summary(live) == "3 agents. w is waiting on you to rm build. r is working. a is done: Done.",
          ab.summary(live))
    check("no agents says so", ab.summary({}) == "No agents are running.")

    print("load")
    tmp = Path(tempfile.mkdtemp()) / "agent-events.jsonl"
    tmp.write_text("\n".join([
        json.dumps(ev("PreToolUse", "s1", "/code/x", 100, summary="ls")),
        "not json",
        json.dumps(ev("Stop", "s1", "/code/x", 101, summary="Done.")),
    ]) + "\n")
    loaded = ab.load(tmp, now=200)
    check("load folds the file and skips a bad line", loaded["s1"]["state"] == "done")
    check("a missing file is an empty board", ab.load(Path("/nonexistent/x.jsonl"), now=0) == {})

    print("pick")
    calls = []

    def fake(answer):
        def ask(state, questions):
            calls.append((state, questions))
            return answer
        return ask

    check("no agents: nobody, and Jev is not called",
          ab.pick("run the tests", {}, ask=fake(None))["session"] is None and not calls)
    one = ab.fold({}, ev("PreToolUse", "s1", "/code/x", 1, summary="ls"))
    check("one agent: that one, and Jev is not called",
          ab.pick("run the tests", one, ask=fake(None))["session"] == "s1" and not calls)
    two = ab.fold(one, ev("PermissionRequest", "s2", "/code/clay-map", 2, summary="git push"))
    got = ab.pick("tell the clay one to push", two,
                  ask=fake({"agent": {"choice": "agent_1", "probabilities": {"agent_1": 0.92, "agent_2": 0.04, "none": 0.04}}}))
    check("a confident choice maps back to its session", got["session"] == "s2", str(got))
    criteria = calls[-1][1]["agent"]["criteria"]
    check("the menu is built from the live board plus none",
          set(criteria) == {"agent_1", "agent_2", "none"} and "clay-map" in criteria["agent_1"], str(criteria))
    check("only the sentence is sent as state", calls[-1][0] == {"spoken": "tell the clay one to push"})
    low = ab.pick("do it", two, ask=fake({"agent": {"choice": "agent_1", "probabilities": {"agent_1": 0.5, "agent_2": 0.3, "none": 0.2}}}))
    check("under the floor: nobody", low["session"] is None and low["confidence"] == 0.5, str(low))
    check("none: nobody", ab.pick("hi", two, ask=fake({"agent": {"choice": "none", "probabilities": {"none": 0.9, "agent_1": 0.05, "agent_2": 0.05}}}))["session"] is None)
    check("Jev down: nobody", ab.pick("hi", two, ask=fake(None))["session"] is None)
    check("an option Jev invented: nobody",
          ab.pick("hi", two, ask=fake({"agent": {"choice": "agent_9", "probabilities": {"agent_9": 1.0}}}))["session"] is None)

    for malformed in (float('nan'), float('inf'), True, '0.99'):
        result = ab.pick("ambiguous", two, ask=fake({"agent": {"choice": "agent_1", "probabilities": {
            "agent_1": malformed, "agent_2": 0.005, "none": 0.005}}}))
        check("invalid confidence never chooses an agent", result["session"] is None)
    from unittest.mock import patch
    with patch.object(ab.jev, "ask", return_value={"agent": {"choice": "agent_1", "probabilities": {
            "agent_1": .92, "agent_2": .04, "none": .04}}}) as provider:
        result = ab.pick("the clay one", two)
        check("native board pick keeps the upstream timeout", provider.call_args.kwargs["timeout"] == ab.PICK_TIMEOUT_S)
        check("native board pick retains strict validated selection", result["session"] == "s2")

    print("tabs and topics")
    with tempfile.TemporaryDirectory() as tmp:
        transcript = Path(tmp) / "s1.jsonl"
        transcript.write_text("\n".join([
            json.dumps({"type": "ai-title", "aiTitle": "Old title"}),
            json.dumps({"type": "user", "message": {"content": "the ai-title word in a prompt"}}),
            json.dumps({"type": "ai-title", "aiTitle": "Kyber voice wiring"}),
            json.dumps({"type": "assistant", "message": {"content": "ok"}}),
        ]) + "\n")
        check("the newest title wins", ab.topic_of(str(transcript)) == "Kyber voice wiring")
        check("no transcript, no topic", ab.topic_of("") == "" and ab.topic_of("/nope/x.jsonl") == "")
        check("only a .jsonl is read", ab.topic_of(str(Path(tmp))) == "")
        b = {}
        b = ab.fold(b, ev("PreToolUse", "s1", "/code/chewbacca", 100, tty="/dev/ttys002",
                          transcript=str(transcript), summary="npm test"))
        b = ab.fold(b, ev("PostToolUse", "s1", "/code/chewbacca", 101))
        b = ab.fold(b, ev("PreToolUse", "hud", "/code/chewbacca", 102, summary="Read x"))
        b = ab.fold(b, ev("PermissionRequest", "s3", "/code/rig", 103, tty="/dev/ttys004", summary="git push"))
        check("a later line without a tty keeps the session's tty", b["s1"]["tty"] == "/dev/ttys002")
        b = ab.with_topics(b)
        check("the topic is the transcript's title", b["s1"]["topic"] == "Kyber voice wiring")
        check("the voice names a session by its topic, else its folder",
              ab.name(b["s1"]) == "Kyber voice wiring" and ab.name(b["s3"]) == "rig")
        criteria, _ = ab.menu(b)
        check("the menu carries the topic", any("Kyber voice wiring" in c for c in criteria.values()))
        check("a session with no tab cannot be typed into", set(ab.typeable(b)) == {"s1", "s3"})
        check("the caller's own session is left out", set(ab.typeable(b, exclude="s1")) == {"s3"})
        check("a fresh prompt in a tab is answerable",
              [s["session"] for s in ab.answerable(b, now=110)] == ["s3"])
        check("an old prompt is not", ab.answerable(b, now=103 + ab.ANSWERABLE_S + 1) == [])
        check("the spoken summary leaves out raw commands",
              "npm test" not in ab.summary(b) and "waiting on you to git push" in ab.summary(b), ab.summary(b))

    print(f"\n{PASSED} passed, {FAILED} failed")
    return 1 if FAILED else 0


if __name__ == "__main__":
    sys.exit(main())

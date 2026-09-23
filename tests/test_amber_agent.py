"""One person's Amber, through the MCP tools a chat app calls: hello, remember, recall.

Karthik's first deliverable, at the level he will see it: two people, each
agent greets its own person by name, a fact told in one conversation comes back
in a later one, and neither agent can reach the other's. Every conversation is
a fresh server process, so anything recalled came off disk.

Also checks the Jev opt-in: inside a user's root, jev.allowed() is false until
`amber-user consent <user> jev on`, so a new user's data never reaches Jev by
default. No test here touches the network.

    python3 tests/test_amber_agent.py
"""

import json
import os
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SERVER = ROOT / "mcp" / "amber" / "amber-mcp"
AMBER_USER = ROOT / "bin" / "amber-user"
SECRET = "is quietly interviewing at Stripe"
PASSED = FAILED = 0


def check(name, condition, detail=""):
    global PASSED, FAILED
    if condition:
        PASSED += 1
        print(f"  pass  {name}")
    else:
        FAILED += 1
        print(f"  FAIL  {name}  {detail}")


def conversation(env, user, *calls):
    """One chat session: a fresh server, initialize, then each tool call."""
    msgs = [{"jsonrpc": "2.0", "id": 0, "method": "initialize", "params": {}}]
    for i, (tool, args) in enumerate(calls, 1):
        msgs.append({"jsonrpc": "2.0", "id": i, "method": "tools/call",
                     "params": {"name": tool, "arguments": args}})
    p = subprocess.run(["node", str(SERVER)], input="\n".join(json.dumps(m) for m in msgs) + "\n",
                       capture_output=True, text=True, env={**env, "AMBER_USER": user}, timeout=120)
    out = {}
    for line in p.stdout.splitlines():
        r = json.loads(line)
        if r.get("id"):
            res = r.get("result", {})
            out[r["id"]] = ("ERR " if res.get("isError") else "") + res.get("content", [{}])[0].get("text", "")
    return [out.get(i, f"no reply ({p.stderr.strip()[:300]})") for i in range(1, len(calls) + 1)]


def main():
    with tempfile.TemporaryDirectory() as tmp:
        base = {k: v for k, v in os.environ.items() if k not in (
            "AMBER_USER", "AMBER_ROOT", "PEOPLE_DIR", "SUPERASSISTANT_DIR", "CHEWBACCA_LOG_DIR")}
        # PEOPLE_JEV=off on top of the consent gate: no test reaches the network.
        env = {**base, "HOME": tmp, "AMBER_HOME": f"{tmp}/users", "PEOPLE_JEV": "off"}
        for user, name in (("alice", "Alice Park"), ("bob", "Bob Diaz")):
            subprocess.run([str(AMBER_USER), "init", user, "--name", name], env=env,
                           capture_output=True, check=True)

        # Identity: each agent knows whose it is.
        a_hello, = conversation(env, "alice", ("hello", {}))
        b_hello, = conversation(env, "bob", ("hello", {}))
        try:
            a, b = json.loads(a_hello), json.loads(b_hello)
        except ValueError:
            a, b = {}, {}
        check("identity: alice's agent knows it is Alice's", a.get("you", {}).get("name") == "Alice Park", a_hello[:300])
        check("identity: bob's agent knows it is Bob's", b.get("you", {}).get("name") == "Bob Diaz", b_hello[:300])

        # Durable recall: told in one conversation, recalled in the next.
        told = conversation(env, "alice",
                            ("remember", {"about": "Sam Lee", "fact": SECRET}),
                            ("remember", {"about": "me", "fact": "likes short answers, no small talk"}),
                            ("remember", {"about": "Sam Lee", "fact": "owes me the Dune book"}))
        check("remember: a new person is added and noted", not any(t.startswith("ERR") for t in told), told)
        later = conversation(env, "alice",
                             ("recall", {"about": "Sam Lee"}),
                             ("recall", {"query": "interviewing Stripe"}),
                             ("hello", {}))
        check("durable recall: a later conversation recalls the note about Sam", SECRET in later[0], later[0][:300])
        check("durable recall: keyword recall finds it across everyone", SECRET in later[1], later[1][:300])
        check("adaptation: hello carries how Alice likes to be talked to",
              "likes short answers" in later[2], later[2][:400])

        # Isolation: bob's agent, asked every way, never sees alice's fact.
        probes = conversation(env, "bob",
                              ("recall", {"about": "Sam Lee"}),
                              ("recall", {"query": "interviewing Stripe"}),
                              ("hello", {}),
                              ("remember", {"about": "Sam Lee", "fact": "plays pickup on Sundays"}),
                              ("recall", {"about": "Sam Lee"}))
        check("isolation: bob cannot recall alice's person", SECRET not in probes[0], probes[0][:300])
        check("isolation: bob's keyword recall finds nothing of alice's", SECRET not in probes[1], probes[1][:300])
        check("isolation: bob's hello carries none of alice's facts",
              "likes short answers" not in probes[2] and SECRET not in probes[2], probes[2][:300])
        check("isolation: a person both know carries only bob's notes",
              "pickup" in probes[4] and SECRET not in probes[4], probes[4][:300])

        # Control: the same keyword probe as alice must find it, or the
        # isolation checks above could be passing because recall is broken.
        control, = conversation(env, "alice", ("recall", {"query": "Stripe"}))
        check("control: the probe does find the fact for its owner", SECRET in control, control[:300])

        # Jev opt-in: off inside a user's root until that user says yes.
        probe = ("import sys; sys.path.insert(0, sys.argv[1]); import jev; "
                 "print('on' if jev.allowed() else 'off')")
        lib = str(ROOT / "bin" / "lib")
        root = f"{tmp}/users/alice"
        allowed = lambda: subprocess.run([sys.executable, "-c", probe, lib], capture_output=True, text=True,
                                         env={**env, "AMBER_ROOT": root}).stdout.strip()
        check("jev: off for a new user", allowed() == "off")
        subprocess.run([str(AMBER_USER), "consent", "alice", "jev", "on"], env=env, capture_output=True, check=True)
        check("jev: on once the user opts in", allowed() == "on")
        mode = oct(os.stat(f"{root}/consent.json").st_mode & 0o777)
        check("jev: the consent file is private to the account", mode == "0o600", mode)
        subprocess.run([str(AMBER_USER), "consent", "alice", "jev", "off"], env=env, capture_output=True, check=True)
        check("jev: off again when the user says so", allowed() == "off")
        bob_says = subprocess.run([str(AMBER_USER), "consent", "bob"], env=env, capture_output=True, text=True).stdout
        check("jev: one user's yes is not another's", bob_says.strip() == "jev\toff", bob_says)
        outside = subprocess.run([sys.executable, "-c", probe, lib], capture_output=True, text=True,
                                 env=base).stdout.strip()
        check("jev: the owner's own install, outside any root, is unchanged", outside == "on")

    print(f"\n{PASSED} passed, {FAILED} failed")
    return 1 if FAILED else 0


if __name__ == "__main__":
    sys.exit(main())

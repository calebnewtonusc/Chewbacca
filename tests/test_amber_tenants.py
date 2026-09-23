"""Two people on one machine, through bin/amber-user.

The multi-tenancy acceptance tests, at the storage layer: Identity, Durable
recall and Isolation. Adaptation is a model behaviour and is not tested here. Every call is a fresh process, so anything recalled
came off disk, not out of memory.

The control runs the isolation probe with both people pointed at one store, and
expects it to leak. Without it, an isolation check that could never fail (a typo
in the probe, a store that never wrote) would pass forever.

    python3 tests/test_amber_tenants.py
"""

import os
import pathlib
import stat
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
AMBER_USER = ROOT / "bin" / "amber-user"
PEOPLE = ROOT / "bin" / "people"
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


def run(env, *args):
    return subprocess.run(
        [str(a) for a in args], env=env, capture_output=True, text=True, timeout=60
    )


def as_user(env, user, *args):
    return run(env, AMBER_USER, "run", user, "--", *args)


def main():
    with tempfile.TemporaryDirectory() as tmp:
        base = {k: v for k, v in os.environ.items() if k not in (
            "AMBER_USER", "PEOPLE_DIR", "SUPERASSISTANT_DIR", "CHEWBACCA_LOG_DIR")}
        env = {**base, "HOME": tmp, "AMBER_HOME": f"{tmp}/users"}

        run(env, AMBER_USER, "init", "alice", "--name", "Alice Park")
        run(env, AMBER_USER, "init", "bob", "--name", "Bob Diaz")

        # Identity: each process knows whose it is, from its environment alone.
        check("identity: alice", as_user(env, "alice", AMBER_USER, "whoami").stdout.strip()
              == "alice\tAlice Park")
        check("identity: bob", as_user(env, "bob", AMBER_USER, "whoami").stdout.strip()
              == "bob\tBob Diaz")

        # Durable recall: told in one process, read back in another.
        as_user(env, "alice", PEOPLE, "add", "Sam Lee")
        as_user(env, "alice", PEOPLE, "note", "sam", SECRET)
        recalled = as_user(env, "alice", PEOPLE, "show", "sam")
        check("durable recall: a later process reads the note", SECRET in recalled.stdout,
              recalled.stdout[-300:] + recalled.stderr)

        # Isolation: bob asks directly, lists, and asks about a person both know.
        direct = as_user(env, "bob", PEOPLE, "show", "sam")
        check("isolation: bob cannot open alice's person",
              direct.returncode != 0 and SECRET not in direct.stdout + direct.stderr)
        listed = as_user(env, "bob", PEOPLE, "list")
        check("isolation: alice's person is not in bob's list", "Sam Lee" not in listed.stdout)
        as_user(env, "bob", PEOPLE, "add", "Sam Lee")
        shared = as_user(env, "bob", PEOPLE, "show", "sam")
        check("isolation: a person both know carries only bob's notes",
              shared.returncode == 0 and SECRET not in shared.stdout, shared.stdout[-300:])

        # The roots are private to the account, not just separate.
        for user in ("alice", "bob"):
            mode = stat.S_IMODE(os.stat(f"{tmp}/users/{user}").st_mode)
            check(f"{user}'s root is 0700", mode == 0o700, oct(mode))

        # An id that climbs out of the users directory is refused, not rewritten.
        for bad in ("..", "../alice", ".hidden", "Alice"):
            refused = run(env, AMBER_USER, "init", bad)
            check(f"refuses user id {bad!r}", refused.returncode != 0)
        check("nothing was made outside the users directory",
              sorted(os.listdir(f"{tmp}/users")) == ["alice", "bob"],
              os.listdir(f"{tmp}/users"))

        # Control: one shared store, so the same probe must see the secret.
        shared_env = {**base, "HOME": tmp, "PEOPLE_DIR": f"{tmp}/users/alice/people"}
        leaked = run(shared_env, PEOPLE, "show", "sam")
        check("control: the probe does see the secret when the store is shared",
              SECRET in leaked.stdout, leaked.stdout[-300:])

    print(f"\n{PASSED} passed, {FAILED} failed")
    return 1 if FAILED else 0


if __name__ == "__main__":
    sys.exit(main())

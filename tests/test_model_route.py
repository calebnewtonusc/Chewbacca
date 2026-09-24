"""model-route: Jev's choice maps to the router's own targets, a weak or
non-task choice abstains, and hook mode stays silent where it should.
Offline: Jev is a stub, and the hook runs with no key."""
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "bin" / "lib"))
import model_route  # noqa: E402


def stub(choice, p):
    return lambda state, questions: {"task": {"choice": choice, "probabilities": {choice: p}}}


def main():
    failures = 0

    def check(name, cond):
        nonlocal failures
        print(("  ok    " if cond else "  FAIL  ") + name)
        failures += 0 if cond else 1

    r = model_route.classify("the test fails on CI", ask=stub("debugging", 0.98))
    check("debugging maps to opus at high", (r["model"], r["effort"]) == ("opus", "high"))
    r = model_route.classify("rename it", ask=stub("mechanical", 0.9))
    check("mechanical maps to haiku with no effort", (r["model"], r["effort"]) == ("haiku", None))
    check("none abstains", model_route.classify("hi", ask=stub("none", 1.0))["class"] is None)
    check("a weak choice abstains", model_route.classify("x y", ask=stub("architecture", 0.4))["class"] is None)
    check("Jev down abstains", model_route.classify("fix it", ask=lambda s, q: None)["class"] is None)
    check("targets cover exactly the router's classes",
          set(model_route.TARGETS) == set(model_route.CRITERIA) - {"none"})

    with tempfile.TemporaryDirectory() as home:
        env = dict(os.environ, CLAUDE_CONFIG_DIR=home, TYPESAFE_API_KEY="", HOME=home)
        env.pop("CLAUDE_MODEL_ROUTER_CHILD", None)

        def hook(prompt, **extra):
            return subprocess.run([str(ROOT / "bin/model-route"), "--hook"], text=True,
                                  input=json.dumps({"prompt": prompt}), capture_output=True,
                                  env=dict(env, **extra), timeout=20)
        out = hook("why does it go deaf")
        check("no key: silent and exit 0", out.returncode == 0 and out.stdout == "")
        check("a slash command is never judged", hook("/compact").stdout == "")
        check("the router's own child call is skipped",
              hook("fix it", CLAUDE_MODEL_ROUTER_CHILD="1").stdout == "")
    print()
    print("model-route holds the router's table" if not failures else f"{failures} failed")
    return failures


if __name__ == "__main__":
    sys.exit(main())

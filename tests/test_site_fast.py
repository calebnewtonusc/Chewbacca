"""site_fast's text helper must honour jev-ultrafast's field_text contract:
a non-empty string of at most 2000 characters, or ValueError so nothing is
typed. Runs offline: the claude call is replaced by a shell stub and
jev_ultrafast.model by a fake module."""
import os
import shlex
import sys
import types
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "bin" / "lib"))

fake_pkg = types.ModuleType("jev_ultrafast")
fake_model = types.ModuleType("jev_ultrafast.model")
fake_model.TEXT_VALUE = "Return {\"text\": value}."
fake_pkg.model = fake_model
sys.modules["jev_ultrafast"] = fake_pkg
sys.modules["jev_ultrafast.model"] = fake_model


def run_with(stdout: str):
    import importlib
    # The helper appends --system-prompt and its text; the stub ignores them.
    os.environ["SITE_FAST_TEXT_CMD"] = "python3 -c 'import sys; print(sys.argv[1])' " + shlex.quote(stdout)
    import site_fast
    importlib.reload(site_fast)
    return site_fast.claude_field_text({"goal": "search", "field": "q"})


def main():
    failures = 0

    def check(name, fn):
        nonlocal failures
        try:
            fn()
            print(f"  ok    {name}")
        except AssertionError as err:
            failures += 1
            print(f"  FAIL  {name}: {err}")

    def good():
        value, meta = run_with('{"result": "{\\"text\\": \\"Godel\\"}", "total_cost_usd": 0.001}')
        assert value == "Godel", value
        assert meta["usage"]["cost_usd"] == 0.001

    def raises(stdout):
        def inner():
            try:
                run_with(stdout)
            except ValueError:
                return
            raise AssertionError("expected ValueError")
        return inner

    check("a valid reply types the value", good)
    check("an empty value types nothing", raises('{"result": "{\\"text\\": \\"  \\"}"}'))
    check("prose with no JSON types nothing", raises('{"result": "I cannot help"}'))
    check("a non-JSON envelope types nothing", raises("claude: not logged in"))
    check("an over-long value types nothing",
          raises('{"result": "{\\"text\\": \\"' + "x" * 2001 + '\\"}"}'))
    print()
    print("site-fast text helper holds its contract" if not failures else f"{failures} failed")
    return failures


if __name__ == "__main__":
    sys.exit(main())

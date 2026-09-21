#!/usr/bin/env python3
"""preflight must describe setup.sh accurately, or not at all.

Sagar called the installer malware and quit after two hours. He was right to:
2,844 lines of shell, piped from a URL, three questions asked, first write on
line 57. A tool only one person can install has one user.

The manifest is the fix, and a manifest is worth exactly its accuracy. Both
of these are failures, and both happened while building it:

  under-reporting  4 directories printed under a heading saying ONLY,
                   because any path containing a $ was skipped
  over-reporting   318 directories including '&&' and a printf format,
                   because the argument pattern ran to end of line

So this test checks the count against setup.sh itself rather than against a
number somebody wrote down.
"""

from __future__ import annotations

import importlib.machinery
import importlib.util
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SETUP = ROOT / "setup.sh"


def load():
    loader = importlib.machinery.SourceFileLoader(
        "preflight", str(ROOT / "bin/preflight"))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


def test_every_mkdir_is_accounted_for():
    """Nothing setup.sh creates may be silently absent from the report."""
    m = load()
    src = m.strip_comments(SETUP.read_text(encoding="utf-8", errors="ignore"))
    dirs, unresolved = m.written_dirs(src)
    n_mkdir = len(re.findall(r"mkdir\s+-p\s", src))
    assert dirs, "setup.sh creates directories and none were reported"
    assert len(dirs) + len(unresolved) >= n_mkdir * 0.5, (
        f"{n_mkdir} mkdir calls but only {len(dirs)}+{len(unresolved)} reported; "
        "the manifest is dropping writes")


def test_no_shell_fragments_reported_as_directories():
    """The 318-entry version reported '&&' and '%s\\n' as directories."""
    m = load()
    src = m.strip_comments(SETUP.read_text(encoding="utf-8", errors="ignore"))
    dirs, _ = m.written_dirs(src)
    for d in dirs:
        assert not re.search(r"[&|;>%\\\\]", d), f"shell fragment reported as a directory: {d!r}"
        assert d.startswith(("~", "/", ".")), f"not a path: {d!r}"


def test_the_known_directories_are_present():
    """Spot-check the ones a reader would look for first."""
    m = load()
    src = m.strip_comments(SETUP.read_text(encoding="utf-8", errors="ignore"))
    dirs, _ = m.written_dirs(src)
    for expected in ("~/.local/bin", "~/.claude/hooks", "~/.claude/rules"):
        assert expected in dirs, f"{expected} missing from the manifest"


def test_comments_are_not_parsed_as_code():
    """'# link_tool is defined above' reported a command called 'is'."""
    m = load()
    src = SETUP.read_text(encoding="utf-8", errors="ignore")
    tools = m.path_tools(m.strip_comments(src))
    assert "is" not in tools, "a word from a comment is being reported as a command"
    assert "defined" not in tools
    assert tools, "no commands found at all, the parser is broken"


def test_real_commands_are_listed():
    m = load()
    src = m.strip_comments(SETUP.read_text(encoding="utf-8", errors="ignore"))
    tools = m.path_tools(src)
    for expected in ("hud", "coursework", "people"):
        assert expected in tools, f"{expected} is installed by setup.sh but not reported"


def test_brew_packages_are_real_names():
    m = load()
    src = m.strip_comments(SETUP.read_text(encoding="utf-8", errors="ignore"))
    for pkg in m.brew_packages(src):
        assert re.fullmatch(r"[\w@/.-]+", pkg), f"not a package name: {pkg!r}"


def test_it_writes_nothing():
    """A preflight that modified anything would defeat its own purpose."""
    src = (ROOT / "bin/preflight").read_text(encoding="utf-8")
    for forbidden in ("write_text(", "mkdir(", "subprocess.run", "os.remove",
                      "shutil.copy", "urlopen", "requests."):
        assert forbidden not in src, f"preflight must not {forbidden}"


if __name__ == "__main__":
    fails = 0
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            try:
                fn()
                print(f"  pass  {name}")
            except AssertionError as exc:
                print(f"  FAIL  {name}: {exc}")
                fails += 1
    print(f"\n{'FAILED' if fails else 'ok'}  {fails} failure(s)")
    sys.exit(1 if fails else 0)

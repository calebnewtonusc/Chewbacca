#!/bin/bash
# Every hook in .claude/hooks must be registered by setup.sh.
#
# WHY THIS EXISTS. setup.sh copies .claude/hooks/*.sh to ~/.claude/hooks
# unconditionally, so a hook that nothing registers still lands on disk, still
# reports executable, and still answers `command -v`. It just never runs.
#
# On 2026-09-22 a sweep found SIX of them. ux-guard, skill-route, ask-capture,
# kit-autopush and kit-debt were all live on the author's machine only because
# they had been hand-added to settings.json; youtube-transcript-ready had never
# been registered anywhere at all. kit-debt is the sharpest case: it was built
# so Caleb would stop having to ask whether the kit learned anything, its tool
# was installed and covered by tests, and the hook had not fired once.
#
# A file-exists check cannot see this and neither can a passing test suite, so
# the only thing that catches it is comparing the two lists.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

exec python3 - "$ROOT" <<'PY'
import pathlib, re, sys

root = pathlib.Path(sys.argv[1])
setup = (root / "setup.sh").read_text()

# Not hooks: lib.sh is sourced by the others, statusline.sh is the status line.
NOT_HOOKS = {"lib.sh", "statusline.sh"}

registered = set(re.findall(r'hooks_dir \+ "/([\w.-]+\.sh)"', setup))
registered |= set(re.findall(r'hooks/([\w.-]+\.sh)', setup))

hooks = sorted(p.name for p in (root / ".claude/hooks").glob("*.sh"))
dead = [h for h in hooks if h not in registered and h not in NOT_HOOKS]

if dead:
    print("FAIL: in .claude/hooks and never registered by setup.sh:")
    for d in dead:
        print("  ", d)
    print("\nAdd a _register(...) call, or add it to NOT_HOOKS here and say why.")
    raise SystemExit(1)

print(f"ok    all {len(hooks) - len(NOT_HOOKS & set(hooks))} hooks are registered by setup.sh")
PY

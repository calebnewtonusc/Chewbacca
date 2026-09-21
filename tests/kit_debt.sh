#!/bin/bash
# kit-debt must fire when work happened elsewhere and the kit learned nothing,
# and stay quiet otherwise. A gate that never fires is decoration.
set -uo pipefail
TOOL="$(dirname "$0")/../bin/kit-debt"
pass=0; fail=0
ok(){ printf '  \033[0;32mpass\033[0m  %s\n' "$1"; pass=$((pass+1)); }
no(){ printf '  \033[0;31mfail\033[0m  %s\n' "$1"; fail=$((fail+1)); }

python3 - "$TOOL" <<'PY'
import importlib.util, sys, types
spec = importlib.util.spec_from_loader("kd", loader=None)
kd = types.ModuleType("kd")
kd.__dict__["__file__"] = sys.argv[1]
exec(open(sys.argv[1]).read().split('if __name__')[0], kd.__dict__)
# owing: busy projects, zero kit commits
kd.kit_commits = lambda h: []
kd.work_dirs  = lambda h: {"someproject": 12}
sys.argv = ["kit-debt", "--terse"]
assert kd.main() == 1, "should owe when projects moved and the kit did not"
# clear: kit learned something
kd.kit_commits = lambda h: ["abc feat: a lesson"]
assert kd.main() == 0, "should be clear when the kit has commits"
# clear: nothing happened anywhere
kd.kit_commits = lambda h: []
kd.work_dirs  = lambda h: {}
assert kd.main() == 0, "should be clear when there was no project work"
print("LOGIC_OK")
PY
if [ $? -eq 0 ]; then ok "fires when owed, quiet when clear"; else no "logic wrong"; fi
"$TOOL" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] || [ "$rc" -eq 1 ] && ok "runs against the real tree" || no "crashed on the real tree"
echo "  ${pass} passed, ${fail} failed"
[ "$fail" -eq 0 ]

#!/usr/bin/env bash
# Every hook setup.sh registers must exist in the kit, and every hook in the
# kit that is a guard must be registered.
#
# THE FAILURE THIS EXISTS FOR, 2026-09-21. Two guards were written straight
# into ~/.claude/hooks, tested, and committed to the repo as TESTS ONLY. The
# hooks themselves never left the machine they were written on, so every other
# install had the tests and not the thing being tested.
#
# Caleb, the same night: "Fix chewbacca so everything goated abt my setup is
# the case for everyone." This is that, as a check rather than a good
# intention. It is the same class as the three fixes on 2026-09-20 that were
# made in one home directory and left out of the installer.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0

# 1. Anything setup.sh names must be in the repo.
while IFS= read -r name; do
  [ -n "$name" ] || continue
  if [ ! -f "$ROOT/.claude/hooks/$name" ]; then
    echo "  FAIL  setup.sh registers $name but the kit does not ship it"
    fail=$((fail + 1))
  fi
done < <(grep -oE 'hooks_dir \+ "/[a-z0-9._-]+"' "$ROOT/setup.sh" \
         | sed 's|.*"/||; s|"||' | sort -u)

# 2. Anything in the kit that refuses things must be registered, or it is a
#    file nobody runs.
for f in "$ROOT"/.claude/hooks/*guard*.sh; do
  b=$(basename "$f")
  grep -q "$b" "$ROOT/setup.sh" || {
    echo "  FAIL  the kit ships $b but setup.sh never registers it"
    fail=$((fail + 1))
  }
done

# 3. Registered hooks have to be executable, or they fail silently at runtime.
for f in "$ROOT"/.claude/hooks/*.sh; do
  b=$(basename "$f")
  # lib.sh is sourced by the others, never executed on its own.
  [ "$b" = "lib.sh" ] && continue
  [ -x "$f" ] || { echo "  FAIL  $b is not executable"; fail=$((fail + 1)); }
done

[ "$fail" = 0 ] && echo "  ok    the installer ships everything it registers" \
                || echo "  $fail problem(s)"
exit "$fail"

#!/bin/bash
# setup.sh with no arguments must run on a machine that already has an install,
# and must still refuse on one that does not.
#
# WHY. `chewbacca update` fast-forwards the repo and then runs setup.sh with no
# arguments. --name was required unconditionally, so that second half exited 2
# every time on every machine: update pulled new hooks, skills, commands and
# tools and installed none of them. The repo and the machine then disagreed
# while every version surface reported the new one.
#
# Found 2026-09-22 while making pull-and-push the default, which is what made it
# matter. Pulling code you never install is worse than not pulling at all.
set -uo pipefail
ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/.chewbacca"
FAILED=0

# No manifest: a genuinely new machine still needs --name.
HOME="$TMP" bash "$ROOT/setup.sh" --dry-run >/dev/null 2>&1
[ "$?" -eq 2 ] || { echo "FAIL: a fresh machine no longer demands --name"; FAILED=1; }

# With a manifest: this is a re-install, so it proceeds and skips repos.
echo '{"profile":"developer","repo":"/x"}' > "$TMP/.chewbacca/install-manifest.json"
OUT="$(HOME="$TMP" bash "$ROOT/setup.sh" --dry-run 2>&1)"
RC=$?
[ "$RC" -eq 0 ] || { echo "FAIL: a re-install still exits $RC, so chewbacca update installs nothing"; FAILED=1; }
case "$OUT" in
  *"skipping"*repos*) ;;
  *) echo "FAIL: re-install did not skip the repos section: $OUT"; FAILED=1 ;;
esac

[ "$FAILED" -eq 0 ] && echo "ok    setup.sh re-runs without --name on an existing install, and still refuses on a new one"
exit "$FAILED"

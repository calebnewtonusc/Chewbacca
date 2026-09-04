#!/bin/bash
# Reads Claude Code session JSON on stdin, prints one status line.
input=$(cat)
py() { python3 -c "import json,sys;d=json.load(sys.stdin);print($1)" <<< "$input" 2>/dev/null; }

MODEL=$(py "d.get('model',{}).get('display_name','?')")
CWD=$(py "d.get('workspace',{}).get('current_dir','')")
DIR=$(basename "${CWD:-$PWD}")
PCT=$(py "round(d.get('context',{}).get('used_pct') or 0)")
COST=$(py "d.get('cost',{}).get('total_cost_usd') or 0")

BRANCH=$(git -C "${CWD:-$PWD}" rev-parse --abbrev-ref HEAD 2>/dev/null)
if [ -n "$BRANCH" ]; then
  DIRTY=$(git -C "${CWD:-$PWD}" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  [ "$DIRTY" != "0" ] && BRANCH="$BRANCH*"
  GIT=" \033[38;5;108m⎇ $BRANCH\033[0m"
else
  GIT=""
fi

# context bar turns amber past 60%, red past 80%
if   [ "${PCT:-0}" -ge 80 ]; then CTX="\033[38;5;203m${PCT}%\033[0m"
elif [ "${PCT:-0}" -ge 60 ]; then CTX="\033[38;5;179m${PCT}%\033[0m"
else CTX="\033[38;5;245m${PCT}%\033[0m"; fi

# Staleness nudge. now.md is the file that rots, and a rotted one is worse than
# an empty one because it is quoted with confidence.
#
# This used to hardcode the author's own directory, so on anybody else's machine
# the path did not exist, the nudge never fired, and nothing said so. Read the
# configured location instead, and check both the current schema (core/now.md)
# and the flat one setup.sh writes (NOW.md).
[ -f "$HOME/.claude/d1-config.sh" ] && . "$HOME/.claude/d1-config.sh" 2>/dev/null
STALE=$(PCD="${PERSONAL_CONTEXT_DIR:-}" python3 - <<'PY' 2>/dev/null
import datetime, os, re, pathlib
roots = [p for p in (os.environ.get("PCD", ""), str(pathlib.Path.home() / "second-brain")) if p]
for root in roots:
    for rel in ("core/now.md", "NOW.md"):
        p = pathlib.Path(root) / rel
        if not p.exists():
            continue
        m = re.search(r"updated: (\d{4}-\d{2}-\d{2})", p.read_text(errors="replace"))
        if not m:
            raise SystemExit
        d = (datetime.date.today() - datetime.date.fromisoformat(m.group(1))).days
        if d > 14:
            print(f" \033[38;5;203m◍ {p.name} {d}d\033[0m")
        raise SystemExit
PY
)

printf "\033[38;5;110m%s\033[0m \033[38;5;245m│\033[0m \033[1m%s\033[0m%b \033[38;5;245m│\033[0m %b \033[38;5;245m│\033[0m \033[38;5;245m\$%.2f\033[0m%b" \
  "$MODEL" "$DIR" "$GIT" "$CTX" "$COST" "$STALE"

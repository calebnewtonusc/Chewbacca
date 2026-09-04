#!/bin/bash
# Timing, logging, a watchdog and an output cap. See lib.sh.
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" 2>/dev/null || true
type hook_init >/dev/null 2>&1 && hook_init session-context.sh 8
# SessionStart: inject personal context, and today's tasks if Todoist is wired.
#
# Why this is a script and not an inline settings.json command:
#
#   1. The inline version was one string with seven levels of backslash
#      escaping. It worked, and nobody could read or safely change it.
#
#   2. It injected raw template scaffolding into every session: empty headings,
#      "- ..." bullets, "| ... | ... |" table rows, PROJECT_NAME. Until you
#      actually fill in YOU.md that is pure token cost with no signal. This
#      strips placeholders and drops headings that have nothing under them.
#
#   3. It baked the literal Todoist token into the hook command. The token now
#      comes from the environment, so settings.json holds one copy in `env`
#      instead of a second copy pasted inside a shell string.
#
# Config comes from ~/.claude/d1-config.sh, written by setup.sh.

set -uo pipefail

CONFIG="$HOME/.claude/d1-config.sh"
# shellcheck source=/dev/null
[ -f "$CONFIG" ] && . "$CONFIG"

export PERSONAL_CONTEXT_DIR="${PERSONAL_CONTEXT_DIR:-}"
export CONTEXT_OWNER="${CONTEXT_OWNER:-}"
export TODOIST_API_TOKEN="${TODOIST_API_TOKEN:-}"

# The coursework ledger, if there is one. Deadlines are the context most worth
# having before the first question, and asking for them costs a round trip.
# Silent when the CLI is missing or the ledger is empty.
COURSEWORK_JSON=""
if command -v coursework >/dev/null 2>&1; then
  COURSEWORK_JSON="$(coursework due --days 7 --json 2>/dev/null || true)"
fi
export COURSEWORK_JSON

# Cache. Building this costs a Todoist round trip and two subprocesses, and
# measured at 4.5 seconds on every single session start. Two sessions opened a
# minute apart do not need two round trips, so the result is reused until it
# goes stale or a source file changes underneath it.
CACHE_DIR="$HOME/.chewbacca/cache"
CACHE="$CACHE_DIR/session-context.json"
TTL="${CHEWBACCA_CONTEXT_TTL:-900}"
mkdir -p "$CACHE_DIR" 2>/dev/null || true

cache_fresh() {
  [ -f "$CACHE" ] || return 1
  [ "${CHEWBACCA_NO_CACHE:-0}" = "1" ] && return 1
  local age now mt
  now=$(date +%s)
  mt=$(stat -f %m "$CACHE" 2>/dev/null || stat -c %Y "$CACHE" 2>/dev/null || echo 0)
  age=$((now - mt))
  [ "$age" -lt "$TTL" ] || return 1
  # Any source newer than the cache invalidates it, so editing a context file
  # takes effect in the next session rather than fifteen minutes later.
  for d in "${PERSONAL_CONTEXT_DIR:-}/core" "$HOME/coursework/courses"; do
    [ -d "$d" ] || continue
    [ -n "$(find "$d" -newer "$CACHE" -type f -print -quit 2>/dev/null)" ] && return 1
  done
  return 0
}

if cache_fresh; then
  type hook_emit >/dev/null 2>&1 && hook_emit < "$CACHE" || cat "$CACHE"
  type hook_note >/dev/null 2>&1 && hook_note "cache hit"
else
# Values reach python through the environment, never by string interpolation.
# A token containing a quote or a backslash would otherwise break the script.
python3 <<'PY' > "$CACHE.tmp"
import json, os, re, urllib.request

ctx_dir = os.environ.get("PERSONAL_CONTEXT_DIR", "")
owner = os.environ.get("CONTEXT_OWNER", "") or "user"
token = os.environ.get("TODOIST_API_TOKEN", "")

PLACEHOLDER = re.compile(
    r"^(?:[-*+]\s*\.{2,}\s*$"          # - ...
    r"|\|(?:\s*\.{2,}\s*\|)+\s*$"      # | ... | ... |
    r"|\|[\s:|-]+\|\s*$"               # table separator row
    r"|-{3,}$|\*{3,}$|_{3,}$"          # horizontal rule
    r"|<!--.*?-->$"                    # whole-line HTML comment
    r"|>?\s*_?(?:TODO|TBD)_?\s*$"
    r"|\s*$)",
    re.S,
)
# Anything still wearing its template clothes. YOUR_CITY, YOUR_TITLE, {name},
# <your name here>, and the "auto-updated by Claude" boilerplate all qualify.
TEMPLATE_TOKEN = re.compile(
    r"YOUR_[A-Z_]{2,}|PROJECT_NAME|\{name\}|<your[- ]"
    r"|Auto-updated by Claude|Update trigger:",
    re.I,
)

# A standalone "..." is scaffolding wherever it appears: as a bullet, a
# numbered item, or one cell of a table row.
ELLIPSIS_CELL = re.compile(r"(?:^|[|\s])\.{3,}(?:$|[|\s])")


def is_noise(s):
    return bool(PLACEHOLDER.match(s) or TEMPLATE_TOKEN.search(s) or ELLIPSIS_CELL.search(s))


def is_table_row(s):
    return s.startswith("|")


def useful_lines(path):
    try:
        raw = open(path, encoding="utf-8").read()
    except OSError:
        return []
    lines = [ln.strip() for ln in raw.split("\n")]

    # Pass 1: drop whole tables that have no real data row. Otherwise a header
    # like "| Company | Role |" survives with nothing but placeholders under it.
    drop = set()
    i = 0
    while i < len(lines):
        if is_table_row(lines[i]):
            j = i
            while j < len(lines) and is_table_row(lines[j]):
                j += 1
            block = range(i, j)
            has_data = any(
                not is_noise(lines[k]) and not re.match(r"^\|[\s:|-]+\|$", lines[k])
                for k in list(block)[2:]  # skip header and separator
            )
            if not has_data:
                drop.update(block)
            i = j
        else:
            i += 1

    # Pass 2: drop noise, then headings left with nothing under them.
    kept = []
    for i, s in enumerate(lines):
        if i in drop or is_noise(s):
            continue
        if s.startswith("#"):
            has_body = False
            for k in range(i + 1, len(lines)):
                t = lines[k]
                if t.startswith("#"):
                    break
                if t and k not in drop and not is_noise(t):
                    has_body = True
                    break
            if not has_body:
                continue
        kept.append(s)
    return kept

parts = []
if ctx_dir:
    for name in ("YOU.md", "NOW.md"):
        parts.extend(useful_lines(os.path.join(ctx_dir, name)))

context = " | ".join(parts[:25])

tasks = ""
if token:
    try:
        req = urllib.request.Request(
            "https://api.todoist.com/rest/v2/tasks?filter=today",
            headers={"Authorization": f"Bearer {token}"},
        )
        with urllib.request.urlopen(req, timeout=4) as r:
            data = json.load(r)
        top = [t["content"] for t in sorted(data, key=lambda x: -x.get("priority", 1))[:3]]
        tasks = ", ".join(top)
    except Exception:
        tasks = ""

due_line = ""
raw = os.environ.get("COURSEWORK_JSON", "")
if raw.strip():
    try:
        data = json.loads(raw)
        bits = []
        for d in data.get("overdue", [])[:3]:
            bits.append(f"OVERDUE {d['course']} {d['name']}")
        for d in data.get("upcoming", [])[:4]:
            when = d.get("date") or ""
            bits.append(f"{d['course']} {d['name']} due {when}")
        if bits:
            due_line = "Coursework: " + "; ".join(bits) + "."
    except Exception:
        due_line = ""

# Kits installed on this machine. A kit that has been built but is not
# discoverable gets rebuilt, or gets ignored while the agent answers the same
# question turn by turn. This is the half of the loop that closes it.
kits_line = ""
try:
    import subprocess
    for candidate in (
        os.path.join(os.path.expanduser("~"), ".local", "bin", "kits"),
        os.path.join(os.path.expanduser("~"), ".claude", "bin", "kits"),
        "kits",
    ):
        try:
            out = subprocess.run(
                [candidate, "--context"], capture_output=True, text=True, timeout=6
            )
        except (FileNotFoundError, OSError):
            continue
        if out.returncode == 0 and out.stdout.strip():
            kits_line = out.stdout.strip()
        break
except Exception:
    kits_line = ""

chunks = []
if kits_line:
    chunks.append(kits_line)
if due_line:
    chunks.append(due_line)
if tasks:
    chunks.append(f"Today's priorities: {tasks}.")
if context:
    chunks.append(f"{owner}'s context: {context}")

if not chunks:
    # Nothing worth saying. Staying quiet beats injecting empty scaffolding.
    raise SystemExit(0)

print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": " ".join(chunks),
    }
}))
PY
# An empty result is a valid answer and is worth caching too: it means there
# was nothing to say, and recomputing that costs the same round trip.
mv "$CACHE.tmp" "$CACHE" 2>/dev/null || rm -f "$CACHE.tmp"
[ -s "$CACHE" ] && { type hook_emit >/dev/null 2>&1 && hook_emit < "$CACHE" || cat "$CACHE"; }
fi

# Pull new iMessages into the local people store, in the background.
#
# Backgrounded on purpose: a session must never wait on it. The first run reads
# a 90-day window and the rest are incremental, but a cold Messages database on
# a slow disk can still take a few seconds, and a hook that delays every session
# start is a hook people disable.
#
# Silent by design. No Full Disk Access, no `people` on PATH, no database: all
# of those mean this does nothing, and none of them are worth a warning at the
# top of an unrelated session. `people texts stats` says when the last sync ran.
#
# The events pass runs behind the sync, and only that way round: it reads the
# messages the sync just pulled. It throttles itself to once every six hours and
# caps each run, so twenty sessions in a day cost one bounded scan rather than
# twenty open-ended ones. It says nothing unless it actually found something.
if command -v people >/dev/null 2>&1; then
  # trap - EXIT inside the subshell: it inherits the hook's exit trap, and
  # without this the background sync logs a second, wildly misleading duration
  # for the hook minutes after the hook itself finished.
  # Actually backgrounded. The comment above said it was, and it was not: the
  # subshell ran `people texts sync` in its own foreground, so a session that
  # happened to land on a sync waited 4.3 seconds for it. Measured, not guessed.
  # trap - EXIT because the subshell inherits the hook's exit trap and would
  # otherwise log a second, wildly wrong duration minutes later.
  ( trap - EXIT
    people texts sync >/dev/null 2>&1
    people events auto >/dev/null 2>&1 ) >/dev/null 2>&1 &
  disown 2>/dev/null || true
fi

exit 0

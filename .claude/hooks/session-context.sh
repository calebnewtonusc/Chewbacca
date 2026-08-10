#!/bin/bash
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

# Values reach python through the environment, never by string interpolation.
# A token containing a quote or a backslash would otherwise break the script.
python3 <<'PY'
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
    r"YOUR_[A-Z_]{2,}|PROJECT_NAME|\{name\}|<your[- ]|Auto-updated by Claude",
    re.I,
)

> # A standalone "..." is scaffolding wherever it appears: as a bullet, a
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

chunks = []
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

exit 0

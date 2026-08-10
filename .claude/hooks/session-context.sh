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
    r"|>?\s*_?TODO_?\s*$"
    r"|\s*$)"
)
TEMPLATE_TOKEN = re.compile(r"PROJECT_NAME|YOUR_NAME|YOUR_GITHUB|\{name\}|<your[- ]", re.I)

def useful_lines(path):
    try:
        raw = open(path, encoding="utf-8").read()
    except OSError:
        return []
    lines = raw.split("\n")
    kept = []
    for i, ln in enumerate(lines):
        s = ln.strip()
        if PLACEHOLDER.match(s) or TEMPLATE_TOKEN.search(s):
            continue
        if s.startswith("#"):
            # Keep a heading only if real content follows before the next heading.
            has_body = False
            for nxt in lines[i + 1:]:
                t = nxt.strip()
                if t.startswith("#"):
                    break
                if t and not PLACEHOLDER.match(t) and not TEMPLATE_TOKEN.search(t):
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

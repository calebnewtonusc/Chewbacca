#!/bin/bash
# PreToolUse: refuse to write a person's name that collides with a known person.
#
# STAGE 8, ENFORCED. The graph-engineering skill calls knowledge fusion, merging
# the same real-world entity across different surface forms, "the #1 cause of
# useless graphs", and it is the stage this machine keeps skipping.
#
# WHAT HAPPENED, 2026-09-21. A session wrote "Jonah Black, Cosmos Institute
# grantee" into second-brain as the name of a paying client, on a FIRST NAME
# match against the people store. Wrong person. The client is Jonah Graham. The
# kit has bin/people with a `brief` that refuses on a split identity, and a
# people skill with disambiguation, and neither ran, because nothing forces
# them before an agent writes a name down.
#
# It was not the first time. feedback_resolve_identity_before_writing has been
# in memory since 2026-09-18, after fourteen Tylers and 162 duplicate pairs, and
# the documented mistake was repeated three days later. A note that has been
# read and disobeyed is not a control.
#
# WHAT IT FIRES ON, narrowly. A write that introduces "First Last" where that
# FIRST name is already recorded against a DIFFERENT last name. That is the
# exact collision shape, and it is rare, so the gate is quiet almost always.
#
# It does not fire on a name already known, on a first name nobody shares, or
# on any file outside the notes and people stores. Getting this wrong in the
# noisy direction would be worse than not having it: a gate that interrupts
# ordinary writing gets removed within a day.
#
# Exit 2 refuses the call and hands the reason back.

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" 2>/dev/null || true
type hook_init >/dev/null 2>&1 && hook_init fusion-guard.sh 10

set -uo pipefail
INPUT=$(cat)
command -v jq >/dev/null 2>&1 || exit 0

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')
case "$TOOL" in Write|Edit|MultiEdit) ;; *) exit 0 ;; esac

FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')
[ -n "$FILE" ] || exit 0

# Only where a name becomes a recorded fact. Code and scratch are not claims
# about who someone is.
case "$FILE" in
  "$HOME"/second-brain/*) ;;
  *["/"]people*.md) ;;
  *) exit 0 ;;
esac

# `// ""`, never `// empty`. In jq a string concatenated with `empty`
# produces empty, so "content // empty" plus anything yielded NOTHING and the
# guard read no content at all. Its own test caught that on the first run.
NEW=$(printf '%s' "$INPUT" | jq -r '
  (.tool_input.content // "") + "\n" +
  (.tool_input.new_string // "") + "\n" +
  ((.tool_input.edits // []) | map(.new_string // "") | join("\n"))')
[ -n "${NEW// /}" ] || exit 0

REPORT=$(FG_NEW="$NEW" FG_FILE="$FILE" python3 <<'PY'
import os, re, sys
from pathlib import Path

new = os.environ.get("FG_NEW", "")
target = Path(os.environ.get("FG_FILE", ""))

# Who is already known, and under what full name. core/people.md is the roster
# the agent is told to recognise people from, so it is the authority here.
roster = Path.home() / "second-brain" / "core" / "people.md"
known: dict[str, set[str]] = {}
if roster.exists():
    text = roster.read_text(encoding="utf-8", errors="replace")
    for first, last in re.findall(r"\*\*([A-Z][a-z]+) ([A-Z][a-z]+)\*\*", text):
        known.setdefault(first, set()).add(last)

# Names being introduced by this write. Bolded or plain "First Last".
introduced: set[tuple[str, str]] = set()
for first, last in re.findall(r"\b([A-Z][a-z]{2,})\s+([A-Z][a-z]{2,})\b", new):
    introduced.add((first, last))

# Already in the file being edited is not an introduction.
existing = ""
if target.exists():
    existing = target.read_text(encoding="utf-8", errors="replace")

clashes = []
for first, last in sorted(introduced):
    if first not in known:
        continue
    if last in known[first]:
        continue                      # this exact person is already known
    if f"{first} {last}" in existing:
        continue                      # already in this file, not new
    clashes.append((first, last, sorted(known[first])))

if clashes:
    for first, last, others in clashes:
        alts = ", ".join(f"{first} {o}" for o in others)
        print(f"{first} {last}|{alts}")
PY
)

[ -n "$REPORT" ] || exit 0

{
  echo
  echo "fusion-guard: refusing. This write introduces a person whose first name"
  echo "already belongs to someone else on the roster."
  echo
  printf '%s\n' "$REPORT" | while IFS='|' read -r newname others; do
    echo "  writing:  $newname"
    echo "  known:    $others"
  done
  cat <<'MSG'

This is the exact shape that put "Jonah Black" into second-brain as the name
of a paying client on 2026-09-21. The client was Jonah Graham. A first name is
not an identity, and the kit has the tools to tell them apart:

  people find <first>          every match, not the first one
  people brief <who>           refuses outright if the identity is split

Resolve it, then write. If they really are two different people, add the new
one to core/people.md in the same change and this stops firing.
MSG
} >&2
exit 2

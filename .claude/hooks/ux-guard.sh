#!/bin/bash
# PreToolUse on Write|Edit: refuse to write a UI file carrying the generated look.
#
# THIS WAS A PostToolUse HOOK AND IT DID NOT WORK.
#
# The docs are explicit: "PostToolUse | No | Exit code 2 isn't honored for this
# event. The tool already ran." The previous version exited 2 from PostToolUse
# and the README claimed it "blocks the turn." It did not. It printed findings
# after the file was already on disk, and the test asserted the exit code
# rather than the blocking, so it passed while proving nothing.
#
# Caught 2026-09-20 by an adversarial prior-art review that read the hooks
# reference. Moved to PreToolUse, where exit 2 genuinely blocks the tool call,
# and the content is linted BEFORE it is written.
#
# Which is also the better architecture on the evidence: research/14 found
# post-editing does not work and fails invisibly, so a gate that fires after
# the artifact exists is working at the end of the pipeline where the leverage
# is not.
set -uo pipefail

ENGINE="${UX_ENGINE_DIR:-$HOME/Desktop/2026-Code/ux-engine}"
[ -x "$ENGINE/bin/ux-lint" ] || exit 0

INPUT="$(cat 2>/dev/null || true)"

# PreToolUse gives the content BEFORE the write. Write has `content`; Edit has
# `new_string`. Lint whichever is present against the target path's extension.
read -r FILE TMP <<EOF
$(printf '%s' "$INPUT" | python3 -c '
import json, sys, os, tempfile
try:
    d = json.load(sys.stdin)
except Exception:
    print(""); raise SystemExit
ti = d.get("tool_input") or {}
path = ti.get("file_path") or ti.get("path") or ""
body = ti.get("content")
if body is None:
    body = ti.get("new_string")
if not path or body is None:
    print(""); raise SystemExit
ext = os.path.splitext(path)[1] or ".tsx"
fd, tmp = tempfile.mkstemp(suffix=ext)
with os.fdopen(fd, "w") as f:
    f.write(body)
print(path, tmp)
' 2>/dev/null)
EOF

[ -n "${TMP:-}" ] && [ -f "${TMP:-}" ] || exit 0
trap 'rm -f "$TMP"' EXIT

case "$FILE" in
  *.tsx|*.jsx|*.vue|*.svelte|*.astro|*.html|*.css|*.scss) ;;
  *) exit 0 ;;
esac
case "$FILE" in
  */ux-engine/systems/*|*/tests/fixtures/*|*/node_modules/*|*/dist/*|*/.next/*) exit 0 ;;
esac

OUT="$("$ENGINE/bin/ux-lint" "$TMP" --fix-help 2>/dev/null | sed "s|$TMP|$FILE|g")"

# ONLY BORROWED OR DECLARED AUTHORITY BLOCKS.
#
# research/16: Google requires ZERO effective false positives for anything
# build-breaking, and under 10% for a review check. Measured LLM design
# critique runs near 34%. A blocking gate made of house opinion is roughly
# 3.4x over the line where tools get switched off, and the suppression
# literature says what happens then: 61-68% of suppressions are "unactionable",
# meaning the rule was right in general and wrong here.
#
# So this blocks only on rules tagged EXTERNAL, which cite WCAG, MDN, W3C or
# NIST. Everything else prints and lets the write through. A project that
# wants more enforced writes its own DENY.md, which is external authority from
# this tool's point of view. That is the axe-core move.
BLOCKING="$(printf '%s' "$OUT" | grep -c '^HIGH \[EXTERNAL\]' || true)"
[ "${BLOCKING:-0}" -gt 0 ] || { printf '%s\n' "$OUT" | grep -q '^\(HIGH\|MED\|LOW\)' && printf '%s\n' "$OUT" >&2; exit 0; }

{
  echo "ux-guard: refusing to write $(basename "$FILE"). $BLOCKING finding(s) against a standard this tool did not write."
  echo
  printf '%s\n' "$OUT"
  echo
  echo "Only BLOCKING findings stopped this, and each cites WCAG, MDN or W3C."
  echo "ADVISORY findings are this repo's reading and never block: disagree"
  echo "and move on, or put it in DENY.md to make it enforceable here."
  echo
  echo "Derive the constraints first: ux-constrain"

  PRESET=""
  case "$(tr '[:upper:]' '[:lower:]' < "$TMP" | head -200)" in
    *"<table"*|*datagrid*|*"data-table"*|*columndef*) PRESET=data-table ;;
    *"<form"*|*onsubmit*|*"<input"*|*validation*)     PRESET=form ;;
    *dialog*|*modal*|*drawer*|*"<sheet"*)             PRESET=dialog ;;
    *toast*|*snackbar*|*notification*)                PRESET=toast ;;
    *cmdk*|*"command palette"*|*commandpalette*)      PRESET=command-palette ;;
    *"<nav"*|*sidebar*|*"side-nav"*)                  PRESET=sidebar-nav ;;
    *chart*|*recharts*|*d3*|*plot*)                   PRESET=chart ;;
    *"no results"*|*"nothing here"*|*emptystate*)     PRESET=empty-state ;;
  esac
  [ -n "$PRESET" ] && echo "And load the behaviour spec: ux-preset $PRESET"
} >&2
exit 2

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
HIGH="$(printf '%s' "$OUT" | grep -c '^HIGH' || true)"
[ "${HIGH:-0}" -gt 0 ] || exit 0

{
  echo "ux-guard: refusing to write $(basename "$FILE"). $HIGH high-severity generated-UI tell(s)."
  echo
  printf '%s\n' "$OUT"
  echo
  echo "Each COSTS line is the cost to the person using this, not a style"
  echo "preference. Fix them and write again. If a rule is genuinely wrong for"
  echo "this file, say why in one line rather than working around it."
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

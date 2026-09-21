#!/bin/bash
# PostToolUse on Write|Edit: refuse a UI file that carries the generated look.
#
# THE FAILURE THIS EXISTS FOR. Caleb, 2026-09-20: "Chewbacca should be smart
# enough to ALWAYS apply what it knows." It was not. ux-engine held 5,537 lines
# of researched craft and a linter with 31 rules, and none of it ran unless
# somebody remembered to run it. That is the same failure craft-gate was built
# for one genre at a time, and the same failure prose-check solved for writing:
# the only rules in this kit that actually fire are the ones a hook enforces.
#
# So this is prose-check for interfaces. It runs on the file that was just
# written, prints the user cost of each hit, and blocks the turn on a high.
#
# It blocks rather than warns because a warning is a thing you scroll past.
set -uo pipefail

ENGINE="${UX_ENGINE_DIR:-$HOME/Desktop/2026-Code/ux-engine}"
[ -x "$ENGINE/bin/ux-lint" ] || exit 0

# The tool result arrives on stdin as JSON. No jq dependency: this kit runs on
# machines that do not have it.
INPUT="$(cat 2>/dev/null || true)"
FILE="$(printf '%s' "$INPUT" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
ti = d.get("tool_input") or {}
print(ti.get("file_path") or ti.get("path") or "")
' 2>/dev/null)"

[ -n "$FILE" ] && [ -f "$FILE" ] || exit 0

case "$FILE" in
  *.tsx|*.jsx|*.vue|*.svelte|*.astro|*.html|*.css|*.scss) ;;
  *) exit 0 ;;
esac

# Never lint the corpus, the fixtures, or a vendored tree.
case "$FILE" in
  */ux-engine/systems/*|*/tests/fixtures/*|*/node_modules/*|*/dist/*|*/.next/*) exit 0 ;;
esac

OUT="$("$ENGINE/bin/ux-lint" "$FILE" --fix-help 2>/dev/null)"
HIGH="$(printf '%s' "$OUT" | grep -c '^HIGH' || true)"
[ "${HIGH:-0}" -gt 0 ] || exit 0

# exit 2 sends stderr back to the model as a blocking error.
{
  echo "ux-guard: $HIGH high-severity generated-UI tell(s) in $(basename "$FILE")."
  echo
  printf '%s\n' "$OUT"
  echo
  echo "Fix these before continuing. Each COSTS line is the cost to the person"
  echo "using this, not a style preference. If a rule is wrong for this file,"
  echo "say why in one line and move on; do not silently ignore it."
  echo
  echo "Pick a design system first next time: ux-pick \"<the brief>\""

  # Name the preset for whatever this file actually is. systems/ covers the
  # look and cannot describe behaviour, so a blocked file usually needs the
  # behaviour spec more than it needs a different palette.
  PRESET=""
  case "$(tr "[:upper:]" "[:lower:]" < "$FILE" | head -200)" in
    *"<table"*|*datagrid*|*"data-table"*|*columndef*) PRESET=table ;;
    *"<form"*|*onsubmit*|*"<input"*|*validation*)     PRESET=form ;;
    *dialog*|*modal*|*drawer*|*"<sheet"*)             PRESET=dialog ;;
    *toast*|*snackbar*|*notification*)                PRESET=toast ;;
    *cmdk*|*"command palette"*|*commandpalette*)      PRESET=command-palette ;;
    *"<nav"*|*sidebar*|*"side-nav"*|*navigation*)     PRESET=sidebar-nav ;;
    *chart*|*recharts*|*"<svg"*|*d3*|*plot*)          PRESET=chart ;;
    *"no results"*|*"nothing here"*|*emptystate*)     PRESET=empty-state ;;
  esac
  if [ -n "$PRESET" ]; then
    echo "And this looks like a $PRESET, so load its behaviour spec:"
    echo "  ux-preset $PRESET"
    echo "systems/ was extracted from marketing sites and documents no states,"
    echo "no keyboard and no validation. The preset does."
  fi
} >&2
exit 2

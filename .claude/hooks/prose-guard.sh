#!/bin/bash
# PostToolUse on Write|Edit: check PROSE FILES, not just the chat reply.
#
# Why this exists. slop-guard.sh reads .last_assistant_message, so it only ever
# saw Claude's chat replies. On 2026-09-16 Claude wrote a 1,434-word WRIT 150
# essay straight to disk through the Write tool carrying six kickers, three
# not-X-but-Y constructions and two announced turns, and nothing looked at it,
# because Caleb's actual deliverables are files. ai-scan and slop-check both
# passed that file: they score generic AI-isms (delve, tapestry, robust) and do
# not know what a kicker is. prose-check encodes HIS list, from
# ~/second-brain/core/voice.md and the fifteen 180DC corrections.
#
# Advisory, not blocking. It tells Claude what fired so Claude fixes it before
# handing the file over. It never rewrites Caleb's own prose.
set -uo pipefail

INPUT=$(cat)
command -v jq >/dev/null 2>&1 || exit 0

FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')
[ -n "$FILE" ] || exit 0
[ -f "$FILE" ] || exit 0

# Prose only. Never lint code, config, or lockfiles.
case "$FILE" in
  *.md|*.txt|*.markdown) ;;
  *) exit 0 ;;
esac

# Never lint what Caleb wrote himself: his raw corpus is the voice reference and
# his own slack is deliberate. Also skip machine-written logs and evidence.
case "$FILE" in
  */corpus/raw/*|*/raw/*|*/archive/*|*/node_modules/*) exit 0 ;;
  */AI-LOG.md|*/EVIDENCE-*|*/CHANGELOG.md|*/SHA256SUMS.txt) exit 0 ;;
esac

CHECK=$(command -v prose-check || echo "$HOME/.local/bin/prose-check")
[ -x "$CHECK" ] || exit 0

REPORT=$("$CHECK" "$FILE" 2>/dev/null) && exit 0
[ -n "$REPORT" ] || exit 0

DETAIL=$(printf '%s' "$REPORT" | tail -n +2 | head -30)
jq -n --arg f "$(basename "$FILE")" --arg d "$DETAIL" '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: ("prose-check flagged " + $f + ":\n" + $d +
      "\n\nThese are Caleb'"'"'s banned patterns from voice.md, not generic AI-isms. " +
      "Fix the file before showing it to him. Do not announce the check.")
  }
}' 2>/dev/null || true
exit 0

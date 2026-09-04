#!/usr/bin/env bash
# chewbacca why <behavior>: which rule or skill is causing this.
#
# The kit changes how Claude behaves through five separate mechanisms and
# there was no way to trace an observed behavior back to the file that
# caused it. "Why did it refuse to use an em dash" took a grep across four
# directories.
set -uo pipefail
q="${*:-}"
[ -z "$q" ] && { echo "usage: chewbacca why <word or phrase>" >&2; exit 2; }
CLAUDE_DIR="$HOME/.claude"
BLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

hits=0
show() {
  local label="$1" path="$2"
  [ -e "$path" ] || return 0
  local out
  out="$(grep -rin --include='*.md' -m2 "$q" "$path" 2>/dev/null | head -4)" || true
  [ -z "$out" ] && return 0
  echo -e "\n${BLD}$label${NC}"
  echo "$out" | while IFS= read -r line; do
    f="${line%%:*}"; rest="${line#*:}"; ln="${rest%%:*}"; txt="${rest#*:}"
    printf "  ${DIM}%s:%s${NC}\n    %s\n" "${f/#$HOME/~}" "$ln" "$(echo "$txt" | cut -c1-110)"
  done
  hits=1
}

echo -e "Tracing: ${BLD}$q${NC}"
show "Always-on standards (loaded every session)" "$CLAUDE_DIR/CLAUDE.md"
show "Rules (loaded every session)" "$CLAUDE_DIR/rules"
show "Skills (loaded on demand)" "$CLAUDE_DIR/skills"
show "Slash commands (loaded when typed)" "$CLAUDE_DIR/commands"
show "Subagents" "$CLAUDE_DIR/agents"
[ -d "$HOME/second-brain" ] && show "Your context store" "$HOME/second-brain/core"

if [ "$hits" -eq 0 ]; then
  echo -e "\nNothing in the kit mentions that. The behavior is coming from the"
  echo "model itself, from a plugin, or from a project-level CLAUDE.md."
fi

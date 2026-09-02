#!/bin/bash
# Chewbacca: Quick install
# Copies CLAUDE.md + .claude/ into the current project directory.
# For full infrastructure setup (second brain, iMessage agent, MCP), run setup.sh instead.

set -e

GRN='\033[0;32m'
YLW='\033[1;33m'
NC='\033[0m'

PROJECT_DIR="${1:-$(pwd)}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ""
echo "Chewbacca: Project Install"
echo "================================="
echo ""
echo "Installing to: $PROJECT_DIR"
echo ""

# React Doctor is per project, not per machine: it scans a codebase and installs
# a skill teaching the agent the issues it found there. Only offered when this
# actually is a React project, because installing a React linter into a Python
# repo is noise. Deterministic and model-free, same as ai-scan and slop-check.
if [ -f "$PROJECT_DIR/package.json" ] &&
  grep -qE '"(react|next)"' "$PROJECT_DIR/package.json" 2>/dev/null; then
  if command -v npx >/dev/null 2>&1; then
    echo "  React project detected. Installing the react-doctor skill..."
    if (cd "$PROJECT_DIR" && npx -y react-doctor@latest install >/dev/null 2>&1); then
      echo -e "  ${GRN}✓${NC} react-doctor skill (run: npx react-doctor)"
    else
      echo -e "  ${YLW}!${NC} react-doctor install failed, skipping"
    fi
  fi
fi

# Copy CLAUDE.md
cp "$SCRIPT_DIR/CLAUDE.md" "$PROJECT_DIR/CLAUDE.md"
echo -e "  ${GRN}✓${NC} CLAUDE.md"

# Anything settings.json points at, or CLAUDE.md imports, must sit at a fixed
# global path or it silently resolves to nothing. Only CLAUDE.md is
# project-scoped, so you can tune it per project.
mkdir -p "$HOME/.claude/hooks" "$HOME/.claude/agents" "$HOME/.claude/commands"
cp "$SCRIPT_DIR/.claude/hooks/"*.sh    "$HOME/.claude/hooks/"    2>/dev/null || true
chmod +x "$HOME/.claude/hooks/"*.sh 2>/dev/null || true
cp "$SCRIPT_DIR/.claude/agents/"*.md   "$HOME/.claude/agents/"   2>/dev/null || true
cp "$SCRIPT_DIR/.claude/commands/"*.md "$HOME/.claude/commands/" 2>/dev/null || true
echo -e "  ${GRN}✓${NC} ~/.claude/hooks ($(ls "$SCRIPT_DIR"/.claude/hooks/*.sh | wc -l | tr -d ' ') hooks)"
echo -e "  ${GRN}✓${NC} ~/.claude/agents ($(ls "$SCRIPT_DIR/.claude/agents/" | wc -l | tr -d ' ') subagents)"
echo -e "  ${GRN}✓${NC} ~/.claude/commands ($(ls "$SCRIPT_DIR/.claude/commands/" | wc -l | tr -d ' ') commands)"

# Rules go global. CLAUDE.md imports them as @~/.claude/rules/*.md, so they have
# to be at that path for the imports to resolve in any project.
mkdir -p "$HOME/.claude/rules"
cp "$SCRIPT_DIR/.claude/rules/"*.md "$HOME/.claude/rules/"
echo -e "  ${GRN}✓${NC} ~/.claude/rules ($(ls "$SCRIPT_DIR/.claude/rules/" | wc -l | tr -d ' ') always-on rules)"

# Skills load on demand, including the twelve stack-specific standards.
if [ -d "$SCRIPT_DIR/skills" ]; then
  mkdir -p "$HOME/.claude/skills"
  cp -R "$SCRIPT_DIR/skills/." "$HOME/.claude/skills/"
  echo -e "  ${GRN}✓${NC} ~/.claude/skills ($(ls "$SCRIPT_DIR/skills" | wc -l | tr -d ' ') skills)"
fi

# Merge settings if no global settings exist
SETTINGS_DEST="$HOME/.claude/settings.json"
if [ ! -f "$SETTINGS_DEST" ]; then
  mkdir -p "$HOME/.claude"
  cp "$SCRIPT_DIR/settings/settings.json" "$SETTINGS_DEST"
  # The next step tells the user to paste tokens in here.
  chmod 600 "$SETTINGS_DEST"
  echo -e "  ${GRN}✓${NC} ~/.claude/settings.json (created)"
else
  echo -e "  ${YLW}!${NC} ~/.claude/settings.json exists, merge settings/settings.json manually"
fi

echo ""
echo -e "${GRN}Done.${NC} CLAUDE.md and .claude/ are in your project."
echo ""
echo "Next steps:"
echo "  1. Add your tokens to ~/.claude/settings.json:"
echo '     "env": { "GITHUB_TOKEN": "...", "ANTHROPIC_API_KEY": "...", "TODOIST_API_TOKEN": "..." }'
echo ""
echo "For full infrastructure (second brain + iMessage agent + MCP):"
echo "  chmod +x setup.sh && ./setup.sh"
echo ""

#!/bin/bash
# init-brain.sh: D1 Second Brain Setup
#
# Creates two repos:
#   claude-context   (PUBLIC), operational instructions: CLAUDE.md, rules, commands, hooks
#   personal-context (PRIVATE), personal facts: YOU.md, NOW.md, PEOPLE.md, SYSTEM.md, VOICE.md
#
# claude-context can be made public. It contains zero PII.
# personal-context stays private. It contains everything about you.

set -e

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo ""
echo -e "${BOLD}${BLUE}D1 Second Brain: Setup${NC}"
echo "================================================"
echo ""
echo "Two repos will be created:"
echo ""
echo -e "  ${CYAN}claude-context${NC}   (public-safe)"
echo "  → Operational instructions: CLAUDE.md, rules, commands"
echo "  → Zero personal info. You can make this public."
echo ""
echo -e "  ${CYAN}personal-context${NC} (private)"
echo "  → You: identity, projects, contacts, system info"
echo "  → Never make this public."
echo ""

if ! command -v gh &>/dev/null; then
  echo -e "${YELLOW}gh CLI required. Install: brew install gh && gh auth login${NC}"
  exit 1
fi

if ! gh auth status &>/dev/null; then
  echo -e "${YELLOW}Not authenticated. Run: gh auth login${NC}"
  exit 1
fi

GITHUB_USER=$(gh api user --jq .login 2>/dev/null)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_ROOT="$(dirname "$SCRIPT_DIR")"

echo -e "GitHub: ${CYAN}$GITHUB_USER${NC}"
echo ""

# ── Step 1: claude-context ────────────────────────────────────────────────────
echo -e "${BOLD}Step 1: claude-context${NC} (public-safe operational instructions)"
echo ""

CC_DIR="$HOME/.claude/context"
mkdir -p "$CC_DIR"

echo "→ Copying CLAUDE.md and rules..."
cp "$KIT_ROOT/CLAUDE.md" "$CC_DIR/CLAUDE.md"
mkdir -p "$CC_DIR/commands" "$CC_DIR/rules" "$CC_DIR/hooks"
cp "$KIT_ROOT/.claude/commands/"*.md "$CC_DIR/commands/" 2>/dev/null || true
cp "$KIT_ROOT/.claude/rules/"*.md "$CC_DIR/rules/" 2>/dev/null || true
cp "$KIT_ROOT/.claude/hooks/"* "$CC_DIR/hooks/" 2>/dev/null || true
echo -e "  ${GREEN}✓${NC} Copied to $CC_DIR"

echo "→ Creating GitHub repo: $GITHUB_USER/claude-context (public)..."
if gh repo view "$GITHUB_USER/claude-context" &>/dev/null; then
  echo -e "  ${YELLOW}!${NC} Repo exists, skipping creation"
else
  gh repo create "$GITHUB_USER/claude-context" --public \
    --description "Claude Code operational instructions: CLAUDE.md, rules, commands" \
    2>/dev/null || gh repo create "$GITHUB_USER/claude-context" --public \
    --description "Claude Code operational instructions"
  echo -e "  ${GREEN}✓${NC} Created github.com/$GITHUB_USER/claude-context (public)"
fi

if [ ! -d "$CC_DIR/.git" ]; then
  cd "$CC_DIR"
  git init
  git remote add origin "https://github.com/$GITHUB_USER/claude-context.git"
  git add .
  git commit -m "init: claude-context operational instructions"
  git branch -M main
  git push -u origin main
else
  cd "$CC_DIR"
  git add .
  git diff --cached --quiet || git commit -m "chore: update operational instructions"
  git push origin main 2>/dev/null || true
fi
echo -e "  ${GREEN}✓${NC} https://github.com/$GITHUB_USER/claude-context"
echo ""

# ── Step 2: personal-context ──────────────────────────────────────────────────
echo -e "${BOLD}Step 2: personal-context${NC} (private, your identity + projects)"
echo ""

PC_DIR="$HOME/personal-context"
mkdir -p "$PC_DIR"

if [ ! -f "$PC_DIR/YOU.md" ]; then
  cp "$SCRIPT_DIR/context/YOU.md" "$PC_DIR/YOU.md"
  cp "$SCRIPT_DIR/context/NOW.md" "$PC_DIR/NOW.md"
  cp "$SCRIPT_DIR/context/PEOPLE.md" "$PC_DIR/PEOPLE.md"
  cp "$SCRIPT_DIR/context/SYSTEM.md" "$PC_DIR/SYSTEM.md"
  cp "$SCRIPT_DIR/context/VOICE.md" "$PC_DIR/VOICE.md"
  echo -e "  ${GREEN}✓${NC} Templates copied to $PC_DIR"
else
  echo -e "  ${YELLOW}!${NC} Files already exist, not overwriting"
fi

echo ""
echo "→ Opening YOU.md for editing..."
echo "  This is the most important file. Fill in your name, background, goals."
read -rp "  Press Enter to open in your editor... "
"${EDITOR:-nano}" "$PC_DIR/YOU.md"

echo ""
echo "→ Creating GitHub repo: $GITHUB_USER/personal-context (private)..."
if gh repo view "$GITHUB_USER/personal-context" &>/dev/null; then
  echo -e "  ${YELLOW}!${NC} Repo exists, skipping creation"
else
  gh repo create "$GITHUB_USER/personal-context" --private \
    --description "Personal context: identity, projects, contacts, system" \
    2>/dev/null || gh repo create "$GITHUB_USER/personal-context" --private \
    --description "Personal context"
  echo -e "  ${GREEN}✓${NC} Created github.com/$GITHUB_USER/personal-context (private)"
fi

if [ ! -d "$PC_DIR/.git" ]; then
  cd "$PC_DIR"
  git init
  git remote add origin "https://github.com/$GITHUB_USER/personal-context.git"
  git add .
  git commit -m "init: personal context"
  git branch -M main
  git push -u origin main
else
  cd "$PC_DIR"
  git add .
  git diff --cached --quiet || git commit -m "chore: init personal context"
  git push origin main 2>/dev/null || true
fi
echo -e "  ${GREEN}✓${NC} https://github.com/$GITHUB_USER/personal-context"
echo ""

# ── Step 3: Hook config ───────────────────────────────────────────────────────
echo -e "${BOLD}Step 3: Hook configuration${NC}"
echo ""
echo "Add these to ~/.claude/settings.json:"
echo ""
cat << 'HOOKSEOF'
"SessionStart": [{
  "hooks": [{
    "type": "command",
    "command": "PERSONAL=$(cat ~/personal-context/YOU.md ~/personal-context/NOW.md 2>/dev/null | head -100 | tr '\"' \"'\" | tr '\n' ' '); printf '%s' \"{\\\"hookSpecificOutput\\\": {\\\"hookEventName\\\": \\\"SessionStart\\\", \\\"additionalContext\\\": \\\"$PERSONAL\\\"}}\"",
    "statusMessage": "Loading your context..."
  }]
}]

"PostToolUse" Write|Edit: [{
  "type": "command",
  "command": "jq -r '.tool_input.file_path // empty' | { read -r f; [ -z \"$f\" ] && exit 0; PC=\"$HOME/personal-context\"; CC=\"$HOME/.claude/context\"; if [[ \"$f\" == \"$PC\"/* ]]; then cd \"$PC\" && git add . && git diff --cached --quiet || (git commit -m \"chore: update $(basename $f)\" && git push origin main 2>/dev/null); elif [[ \"$f\" == \"$CC\"/* ]]; then cd \"$CC\" && git add . && git diff --cached --quiet || (git commit -m \"chore: update $(basename $f)\" && git push origin main 2>/dev/null); fi; } 2>/dev/null || true",
  "statusMessage": "Syncing context...",
  "async": true
}]
HOOKSEOF

echo ""
echo "════════════════════════════════════════════════"
echo -e "${GREEN}${BOLD}Second Brain ready.${NC}"
echo ""
echo -e "  ${CYAN}claude-context${NC}   (public):  https://github.com/$GITHUB_USER/claude-context"
echo -e "  ${CYAN}personal-context${NC} (private): https://github.com/$GITHUB_USER/personal-context"
echo ""
echo "Next:"
echo "  1. Fill in ~/personal-context/NOW.md, PEOPLE.md, SYSTEM.md"
echo "  2. Add the hooks above to ~/.claude/settings.json"
echo "  3. Wire agents: see second-brain/agents/"
echo ""

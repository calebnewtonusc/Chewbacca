#!/bin/bash
# D1 Vibe Coding — Full Infrastructure Setup
#
# Run this ONCE from the D1-Vibe-Coding repo.
# It builds your entire Claude Code infrastructure in ~5 minutes.
#
# What it creates:
#   {name}-context      PRIVATE  Your personal second brain (projects, identity, contacts)
#   claude-context      PUBLIC   Operational instructions (CLAUDE.md, rules, commands)
#   imessage-agent      PRIVATE  AI iMessage agent (triage, reply, route prospects)
#
# What it wires:
#   ~/.claude/settings.json     All hooks (format, sync, session context, Todoist)
#   ~/.mcp.json or .mcp.json    Composio MCP + iMessage MCP
#
# Usage:
#   git clone https://github.com/calebnewtonusc/D1-Vibe-Coding
#   cd D1-Vibe-Coding
#   chmod +x setup.sh && ./setup.sh

set -e

# ── Colors ────────────────────────────────────────────────────────────────────
BLU='\033[0;34m'
GRN='\033[0;32m'
YLW='\033[1;33m'
CYN='\033[0;36m'
RED='\033[0;31m'
BLD='\033[1m'
NC='\033[0m'

log()  { echo -e "  ${GRN}✓${NC} $1"; }
warn() { echo -e "  ${YLW}!${NC} $1"; }
err()  { echo -e "  ${RED}✗${NC} $1"; }
head() { echo -e "\n${BLD}${BLU}$1${NC}"; }
sep()  { echo -e "${BLD}────────────────────────────────────────────${NC}"; }

# Cross-platform sed in-place (macOS uses -i '', GNU uses -i)
sedi() {
  if [[ "$(uname)" == "Darwin" ]]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

clear
echo ""
sep
echo -e "  ${BLD}D1 Vibe Coding — Infrastructure Setup${NC}"
sep
echo ""
echo "  This sets up your complete Claude Code infrastructure."
echo "  Takes about 5 minutes. Run it once."
echo ""
echo "  What you'll get:"
echo -e "    ${CYN}{name}-context${NC}   your private second brain"
echo -e "    ${CYN}claude-context${NC}   public operational rules (forkable)"
echo -e "    ${CYN}imessage-agent${NC}   AI iMessage triage + reply agent"
echo ""
echo "  Hooks wired automatically:"
echo "    Session context injection on every Claude session"
echo "    PostToolUse auto-format + auto-sync to GitHub"
echo "    Todoist priorities injected at session start"
echo ""
read -rp "  Press Enter to begin..."

# ── Prerequisites ─────────────────────────────────────────────────────────────
head "Checking prerequisites"
MISSING=0

if ! command -v gh &>/dev/null; then
  err "gh CLI not found. Install: brew install gh"
  MISSING=1
fi

if ! command -v git &>/dev/null; then
  err "git not found. Install Xcode Command Line Tools: xcode-select --install"
  MISSING=1
fi

if ! command -v bun &>/dev/null && ! command -v node &>/dev/null; then
  err "Neither bun nor node found. Install bun: curl -fsSL https://bun.sh/install | bash"
  MISSING=1
fi

if [ "$MISSING" -eq 1 ]; then
  echo ""
  echo "  Fix the above and re-run setup.sh."
  exit 1
fi

if ! gh auth status &>/dev/null; then
  warn "Not authenticated with GitHub. Running gh auth login now..."
  gh auth login
fi

# A clean macOS install has no git identity. Without one, every commit below
# fails with "Author identity unknown", both repos get created and pushed empty,
# and the sync hook then fails silently forever because it swallows the error.
# Catch it here where there is still someone at the keyboard to answer.
if [ -z "$(git config --global user.name 2>/dev/null)" ] ||
  [ -z "$(git config --global user.email 2>/dev/null)" ]; then
  warn "No global git identity is set. Every commit will fail without one."
  echo ""
  read -rp "  Git author name (e.g. Jane Doe): " GIT_NAME
  read -rp "  Git author email: " GIT_EMAIL
  if [ -z "$GIT_NAME" ] || [ -z "$GIT_EMAIL" ]; then
    err "Both are required. Set them yourself and re-run this script:"
    err "  git config --global user.name \"Your Name\""
    err "  git config --global user.email \"you@example.com\""
    exit 1
  fi
  git config --global user.name "$GIT_NAME"
  git config --global user.email "$GIT_EMAIL"
  log "Git identity set: $GIT_NAME <$GIT_EMAIL>"
else
  log "Git identity: $(git config --global user.name) <$(git config --global user.email)>"
fi

GITHUB_USER=$(gh api user --jq .login 2>/dev/null)
log "GitHub: $GITHUB_USER"

# ── Collect info ──────────────────────────────────────────────────────────────
head "About you"
echo ""

read -rp "  Your first name (e.g. John): " USER_NAME
USER_NAME_LOWER=$(echo "$USER_NAME" | tr '[:upper:]' '[:lower:]')
PERSONAL_REPO="${USER_NAME_LOWER}-context"

echo ""
read -rp "  Anthropic API key (sk-ant-...): " ANTHROPIC_KEY
echo ""
read -rp "  GitHub Personal Access Token (repo+workflow scopes): " GITHUB_PAT
echo ""
read -rp "  Composio MCP URL (optional, press Enter to skip): " COMPOSIO_URL
echo ""
read -rp "  Composio API Key (optional, press Enter to skip): " COMPOSIO_KEY
echo ""
read -rp "  Todoist API token (optional, press Enter to skip): " TODOIST_TOKEN
echo ""

WORKSPACE_DIR="$HOME/dev"
read -rp "  Where should repos live? [$WORKSPACE_DIR]: " CUSTOM_DIR
WORKSPACE_DIR="${CUSTOM_DIR:-$WORKSPACE_DIR}"
mkdir -p "$WORKSPACE_DIR"

echo ""
sep
echo ""

# ── Repo 1: {name}-context (private) ─────────────────────────────────────────
head "Creating $PERSONAL_REPO (private personal brain)"

PC_DIR="$WORKSPACE_DIR/$PERSONAL_REPO"
mkdir -p "$PC_DIR"

cp "$SCRIPT_DIR/second-brain/context/YOU.md"    "$PC_DIR/YOU.md"
cp "$SCRIPT_DIR/second-brain/context/NOW.md"    "$PC_DIR/NOW.md"
cp "$SCRIPT_DIR/second-brain/context/PEOPLE.md" "$PC_DIR/PEOPLE.md"
cp "$SCRIPT_DIR/second-brain/context/SYSTEM.md" "$PC_DIR/SYSTEM.md"
cp "$SCRIPT_DIR/second-brain/context/STACK.md"  "$PC_DIR/STACK.md"

# Pre-fill the name placeholder
sedi "s/YOUR_NAME/$USER_NAME/g" "$PC_DIR/YOU.md"
sedi "s/YOUR_GITHUB_USERNAME/$GITHUB_USER/g" "$PC_DIR/YOU.md"

log "Templates copied to $PC_DIR"

echo ""
echo "  Opening YOU.md in your editor. Fill in your background, goals, working style."
echo "  This is what Claude reads about you every single session."
echo ""
read -rp "  Press Enter to open YOU.md..."
"${EDITOR:-nano}" "$PC_DIR/YOU.md"

if gh repo view "$GITHUB_USER/$PERSONAL_REPO" &>/dev/null; then
  warn "Repo $GITHUB_USER/$PERSONAL_REPO already exists — using existing"
else
  gh repo create "$GITHUB_USER/$PERSONAL_REPO" \
    --private \
    --description "$USER_NAME's personal context for Claude — identity, projects, contacts" \
    2>/dev/null || true
  log "Created github.com/$GITHUB_USER/$PERSONAL_REPO (private)"
fi

cd "$PC_DIR"
git init -q 2>/dev/null || true
git remote remove origin 2>/dev/null || true
git remote add origin "https://github.com/$GITHUB_USER/$PERSONAL_REPO.git"

# This repo is private and personal. Keep OS cruft and any stray secret out of
# it from the first commit, and stage by filename per .claude/rules/git.md
# instead of sweeping the directory with `git add .`.
cat > "$PC_DIR/.gitignore" << 'GITIGNORE'
.DS_Store
Thumbs.db
.env
.env.*
!.env.example
*.log
GITIGNORE

git add -- .gitignore YOU.md NOW.md PEOPLE.md SYSTEM.md STACK.md
git diff --cached --quiet || git commit -q -m "init: $USER_NAME personal context"
git branch -M main
git push -u origin main -q 2>/dev/null || warn "Push failed — you may need to push manually"
log "https://github.com/$GITHUB_USER/$PERSONAL_REPO"

# ── Repo 2: claude-context (public) ──────────────────────────────────────────
head "Creating claude-context (public operational rules)"

CC_DIR="$WORKSPACE_DIR/claude-context"
mkdir -p "$CC_DIR/.claude/commands" "$CC_DIR/.claude/rules" "$CC_DIR/.claude/hooks"

cp "$SCRIPT_DIR/CLAUDE.md" "$CC_DIR/CLAUDE.md"
cp "$SCRIPT_DIR/.claude/commands/"*.md "$CC_DIR/.claude/commands/" 2>/dev/null || true
cp "$SCRIPT_DIR/.claude/rules/"*.md    "$CC_DIR/.claude/rules/"    2>/dev/null || true
cp "$SCRIPT_DIR/.claude/hooks/"*       "$CC_DIR/.claude/hooks/"    2>/dev/null || true

cat > "$CC_DIR/README.md" << READMEOF
# claude-context

Operational instructions for Claude Code: design system, coding standards, slash commands, and hooks.

Forked from [D1-Vibe-Coding](https://github.com/calebnewtonusc/D1-Vibe-Coding).

## What's here

- \`CLAUDE.md\` — full design system, behavioral rules, coding standards
- \`.claude/commands/\` — 36 slash commands covering the full dev lifecycle
- \`.claude/rules/\` — 18 rules files injected as context by file type
- \`.claude/hooks/\` — PostToolUse formatters and linters

## How to use

Copy \`CLAUDE.md\` and \`.claude/\` into any project:

\`\`\`bash
cp CLAUDE.md /path/to/project/
cp -r .claude/ /path/to/project/.claude/
\`\`\`

Or copy globally:

\`\`\`bash
cp CLAUDE.md ~/.claude/CLAUDE.md
\`\`\`

## Source

Built and maintained at [D1-Vibe-Coding](https://github.com/calebnewtonusc/D1-Vibe-Coding).

All glory to God! ✝️❤️
READMEOF

if gh repo view "$GITHUB_USER/claude-context" &>/dev/null; then
  warn "Repo $GITHUB_USER/claude-context already exists — using existing"
else
  gh repo create "$GITHUB_USER/claude-context" \
    --public \
    --description "Claude Code operational instructions — design system, rules, commands" \
    2>/dev/null || true
  log "Created github.com/$GITHUB_USER/claude-context (public)"
fi

cd "$CC_DIR"
git init -q 2>/dev/null || true
git remote remove origin 2>/dev/null || true
git remote add origin "https://github.com/$GITHUB_USER/claude-context.git"

cat > "$CC_DIR/.gitignore" << 'GITIGNORE'
.DS_Store
Thumbs.db
.env
.env.*
!.env.example
*.log
GITIGNORE

git add -- .gitignore CLAUDE.md README.md .claude
git diff --cached --quiet || git commit -q -m "init: claude-context from D1-Vibe-Coding"
git branch -M main
git push -u origin main -q 2>/dev/null || warn "Push failed — you may need to push manually"
log "https://github.com/$GITHUB_USER/claude-context"

# ── Repo 3: imessage-agent (optional, macOS only) ───────────────────────────
IMSG_DIR=""
SETUP_IMESSAGE=0

if [[ "$(uname)" == "Darwin" ]]; then
  echo ""
  read -rp "  Set up iMessage agent? (macOS only, requires Messages.app) [y/N]: " IMSG_CHOICE
  if [[ "$IMSG_CHOICE" =~ ^[Yy] ]]; then
    SETUP_IMESSAGE=1
  fi
else
  warn "Skipping iMessage agent (macOS only)"
fi

if [ "$SETUP_IMESSAGE" -eq 1 ]; then
  head "Setting up imessage-agent"
  IMSG_DIR="$WORKSPACE_DIR/imessage-agent"

  if [ -d "$IMSG_DIR/.git" ]; then
    warn "imessage-agent already exists at $IMSG_DIR. Pulling latest."
    cd "$IMSG_DIR" && git pull -q 2>/dev/null || true
  else
    echo "  Cloning imessage-agent..."
    gh repo clone calebnewtonusc/imessage-agent "$IMSG_DIR" 2>/dev/null || \
      git clone "https://github.com/calebnewtonusc/imessage-agent.git" "$IMSG_DIR" -q 2>/dev/null
    if [ -d "$IMSG_DIR" ]; then
      log "Cloned to $IMSG_DIR"
    else
      warn "Could not clone imessage-agent. Skipping. You can set it up manually later."
      SETUP_IMESSAGE=0
    fi
  fi

  if [ "$SETUP_IMESSAGE" -eq 1 ]; then
    # Create .env with their key
    cat > "$IMSG_DIR/.env" << ENVEOF
ANTHROPIC_API_KEY=${ANTHROPIC_KEY}
# Add other keys below as needed
ENVEOF

    if [ -f "$IMSG_DIR/.gitignore" ]; then
      grep -q "^\.env" "$IMSG_DIR/.gitignore" || echo ".env" >> "$IMSG_DIR/.gitignore"
    fi

    # Install deps
    echo "  Installing dependencies..."
    cd "$IMSG_DIR"
    if command -v bun &>/dev/null; then
      bun install -q 2>/dev/null && log "Dependencies installed (bun)"
    else
      npm install -q 2>/dev/null && log "Dependencies installed (npm)"
    fi

    log "iMessage agent ready at $IMSG_DIR"
  fi
else
  log "Skipping iMessage agent"
fi

# ── Wire ~/.claude/settings.json ─────────────────────────────────────────────
head "Wiring ~/.claude/settings.json"

SETTINGS="$HOME/.claude/settings.json"
mkdir -p "$HOME/.claude"

SESSION_CTX_CMD="PERSONAL=\$(cat \"$PC_DIR/YOU.md\" \"$PC_DIR/NOW.md\" 2>/dev/null | head -150 | python3 -c \"import sys; content=sys.stdin.read(); lines=[l for l in content.split(chr(10)) if l.strip()]; print(' | '.join(lines[:20]))\" 2>/dev/null || echo ''); printf '%s' \"{\\\\\\\"hookSpecificOutput\\\\\\\": {\\\\\\\"hookEventName\\\\\\\": \\\\\\\"SessionStart\\\\\\\", \\\\\\\"additionalContext\\\\\\\": \\\\\\\"$USER_NAME's context: \$PERSONAL\\\\\\\"}}\""

if [ -n "$TODOIST_TOKEN" ]; then
  SESSION_CTX_CMD="TASKS=\$(curl -sf 'https://api.todoist.com/rest/v2/tasks?filter=today' -H 'Authorization: Bearer $TODOIST_TOKEN' 2>/dev/null | python3 -c \"import json,sys; tasks=json.load(sys.stdin); top=[t['content'] for t in sorted(tasks, key=lambda x: -x.get('priority',1))[:3]]; print(', '.join(top))\" 2>/dev/null || echo 'none'); PERSONAL=\$(cat \"$PC_DIR/YOU.md\" \"$PC_DIR/NOW.md\" 2>/dev/null | head -100 | python3 -c \"import sys; content=sys.stdin.read(); lines=[l for l in content.split(chr(10)) if l.strip()]; print(' | '.join(lines[:15]))\" 2>/dev/null || echo ''); printf '%s' \"{\\\\\\\"hookSpecificOutput\\\\\\\": {\\\\\\\"hookEventName\\\\\\\": \\\\\\\"SessionStart\\\\\\\", \\\\\\\"additionalContext\\\\\\\": \\\\\\\"Today priorities: \$TASKS. Context: \$PERSONAL\\\\\\\"}}\""
fi

# Build the full settings.json
python3 << PYEOF
import json, os

settings_path = os.path.expanduser("~/.claude/settings.json")

try:
    with open(settings_path) as f:
        settings = json.load(f)
except:
    settings = {}

# Env
if "env" not in settings:
    settings["env"] = {}

github_pat = "${GITHUB_PAT}"
anthropic_key = "${ANTHROPIC_KEY}"
todoist_token = "${TODOIST_TOKEN}"

if github_pat:
    settings["env"]["GITHUB_TOKEN"] = github_pat
if anthropic_key:
    settings["env"]["ANTHROPIC_API_KEY"] = anthropic_key
if todoist_token:
    settings["env"]["TODOIST_API_TOKEN"] = todoist_token

# Permissions
if "permissions" not in settings:
    settings["permissions"] = {}
settings["permissions"]["defaultMode"] = "bypassPermissions"
if "additionalDirectories" not in settings["permissions"]:
    settings["permissions"]["additionalDirectories"] = []
for d in ["${PC_DIR}", "${CC_DIR}", "${IMSG_DIR}"]:
    if d and d not in settings["permissions"]["additionalDirectories"]:
        settings["permissions"]["additionalDirectories"].append(d)

# Allow Messages DB
if "allow" not in settings["permissions"]:
    settings["permissions"]["allow"] = []
msg_read = f"Read({os.path.expanduser('~')}/Library/Messages/**)"
if msg_read not in settings["permissions"]["allow"]:
    settings["permissions"]["allow"].append(msg_read)
    settings["permissions"]["allow"].append("Bash(sqlite3:*)")
    settings["permissions"]["allow"].append("Bash(osascript:*)")
    settings["permissions"]["allow"].append("WebSearch")

settings["enableAllProjectMcpServers"] = True
settings["alwaysThinkingEnabled"] = True

# Hooks
if "hooks" not in settings:
    settings["hooks"] = {}

# UserPromptSubmit - prayer + identity reminder
settings["hooks"]["UserPromptSubmit"] = [{
    "hooks": [{
        "type": "command",
        "command": "printf '%s' '{\"hookSpecificOutput\": {\"hookEventName\": \"UserPromptSubmit\", \"additionalContext\": \"MANDATORY: Begin every response with a prayer to Jesus. Specific, personal, end with Amen. Then respond.\"}}'",
        "statusMessage": "Prayer reminder loaded"
    }]
}]

# PostToolUse - format + sync
sync_cmd = (
    "jq -r '.tool_input.file_path // empty' | { read -r f; [ -z \"$f\" ] && exit 0; "
    "PC=\"" + "${PC_DIR}" + "\"; "
    "CC=\"" + "${CC_DIR}" + "\"; "
    "case \"$f\" in "
    "*.ts|*.tsx|*.js|*.jsx|*.json|*.css|*.md) npx prettier --write \"$f\" --log-level silent 2>/dev/null || true;; "
    "esac; "
    "if [[ \"$f\" == \"$PC\"/* ]]; then cd \"$PC\" && git add . && git diff --cached --quiet || "
    "(git commit -q -m \"chore: update $(basename $f)\" && git push origin main -q 2>/dev/null); fi; "
    "if [[ \"$f\" == \"$CC\"/* ]]; then cd \"$CC\" && git add . && git diff --cached --quiet || "
    "(git commit -q -m \"chore: update $(basename $f)\" && git push origin main -q 2>/dev/null); fi; "
    "} 2>/dev/null || true"
)

settings["hooks"]["PostToolUse"] = [{
    "matcher": "Write|Edit",
    "hooks": [{
        "type": "command",
        "command": sync_cmd,
        "statusMessage": "Formatting + syncing...",
        "async": True
    }]
}]

# SessionStart - load context + Todoist
settings["hooks"]["SessionStart"] = [{
    "hooks": [{
        "type": "command",
        "command": "${SESSION_CTX_CMD}",
        "statusMessage": "Loading your context..."
    }]
}]

# Stop - GitHub push reminder
settings["hooks"]["Stop"] = [{
    "hooks": [{
        "type": "command",
        "command": "printf '%s' '{\"hookSpecificOutput\": {\"hookEventName\": \"Stop\", \"additionalContext\": \"REMINDER: If you completed any project or feature, push to GitHub now. Create the repo if it does not exist. Never wait to be asked.\"}}'",
        "statusMessage": "Session end check..."
    }]
}]

# Notification
settings["hooks"]["Notification"] = [{
    "hooks": [{
        "type": "command",
        "command": "say 'Claude Code task complete' 2>/dev/null || true",
        "async": True
    }]
}]

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)

print("Settings written.")
PYEOF

log "~/.claude/settings.json configured"

# ── Wire .mcp.json ────────────────────────────────────────────────────────────
head "Wiring .mcp.json"

MCP_FILE="$HOME/.claude/.mcp.json"

python3 << PYEOF2
import json, os

mcp_path = "${MCP_FILE}"
os.makedirs(os.path.dirname(mcp_path), exist_ok=True)

try:
    with open(mcp_path) as f:
        mcp = json.load(f)
except:
    mcp = {"mcpServers": {}}

composio_url = "${COMPOSIO_URL}"
composio_key = "${COMPOSIO_KEY}"
imsg_dir = "${IMSG_DIR}"

if composio_url:
    mcp["mcpServers"]["composio"] = {
        "url": composio_url,
        "headers": {"x-api-key": composio_key} if composio_key else {}
    }

# iMessage agent is a CLI tool (bun run agent.ts --mode scan/inbox/run)
# It does NOT implement MCP stdio protocol, so it is NOT wired as an MCP server.
# Claude invokes it directly via Bash. No MCP entry needed.

with open(mcp_path, "w") as f:
    json.dump(mcp, f, indent=2)

print("MCP config written.")
PYEOF2

log ".mcp.json configured"

# ── Install D1 rules globally ─────────────────────────────────────────────────
head "Installing rules and commands globally"

GLOBAL_CLAUDE="$HOME/.claude"
mkdir -p "$GLOBAL_CLAUDE/commands" "$GLOBAL_CLAUDE/rules"

cp "$SCRIPT_DIR/.claude/commands/"*.md "$GLOBAL_CLAUDE/commands/" 2>/dev/null || true
cp "$SCRIPT_DIR/.claude/rules/"*.md    "$GLOBAL_CLAUDE/rules/"    2>/dev/null || true
cp "$SCRIPT_DIR/CLAUDE.md"             "$GLOBAL_CLAUDE/CLAUDE.md" 2>/dev/null || true

log "Commands installed to ~/.claude/commands/ ($(ls "$GLOBAL_CLAUDE/commands/" | wc -l | tr -d ' ') files)"
log "Rules installed to ~/.claude/rules/ ($(ls "$GLOBAL_CLAUDE/rules/" | wc -l | tr -d ' ') files)"
log "CLAUDE.md installed to ~/.claude/CLAUDE.md"

# ── Skills and plugins ────────────────────────────────────────────────────────
head "Installing skills and plugins"

mkdir -p "$GLOBAL_CLAUDE/skills"
cp -R "$SCRIPT_DIR/skills/." "$GLOBAL_CLAUDE/skills/" 2>/dev/null || true
log "Skills installed to ~/.claude/skills/"

# no-ai-slop is MIT-licensed work by Peter Yang. Cloned rather than vendored so
# it stays updatable and keeps its own LICENSE next to it.
if [ -d "$GLOBAL_CLAUDE/skills/no-ai-slop" ]; then
  log "no-ai-slop already present, left alone"
else
  TMP_SLOP="$(mktemp -d)"
  if git clone -q --depth 1 https://github.com/petergyang/no-ai-slop "$TMP_SLOP" 2>/dev/null; then
    cp -R "$TMP_SLOP/skills/no-ai-slop" "$GLOBAL_CLAUDE/skills/"
    cp "$TMP_SLOP/LICENSE" "$GLOBAL_CLAUDE/skills/no-ai-slop/LICENSE" 2>/dev/null || true
    log "no-ai-slop installed (MIT, Peter Yang)"
  else
    warn "Could not reach GitHub for no-ai-slop. See docs/EXTENSIONS.md to add it later."
  fi
  rm -rf "$TMP_SLOP"
fi

if command -v claude &>/dev/null; then
  claude plugin marketplace add anthropics/claude-plugins-official &>/dev/null || true
  claude plugin marketplace add Egonex-AI/Understand-Anything &>/dev/null || true
  log "Marketplaces registered"

  PLUGIN_FAILED=0
  for p in context7@claude-plugins-official \
    serena@claude-plugins-official \
    playwright@claude-plugins-official \
    vercel@claude-plugins-official \
    railway@claude-plugins-official \
    expo@claude-plugins-official \
    pinecone@claude-plugins-official \
    bigquery-data-analytics@claude-plugins-official \
    understand-anything@understand-anything; do
    if claude plugin install "$p" --scope user &>/dev/null; then
      log "installed ${p%%@*}"
    else
      warn "could not install ${p%%@*}"
      PLUGIN_FAILED=1
    fi
  done

  if [ "$PLUGIN_FAILED" -eq 1 ]; then
    warn "Some plugins failed. Retry individually: claude plugin install <name>"
  fi
  warn "Plugins needing OAuth (Vercel, Railway) stay inert until you run /mcp and authorize."
else
  warn "claude CLI not found. Plugins skipped. See docs/EXTENSIONS.md."
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
sep
echo -e "  ${BLD}${GRN}Setup complete.${NC}"
sep
echo ""
echo -e "  ${BLD}Repos created:${NC}"
echo -e "    ${CYN}$PERSONAL_REPO${NC}     https://github.com/$GITHUB_USER/$PERSONAL_REPO"
echo -e "    ${CYN}claude-context${NC}   https://github.com/$GITHUB_USER/claude-context"
if [ -n "$IMSG_DIR" ] && [ "$SETUP_IMESSAGE" -eq 1 ]; then
  echo -e "    ${CYN}imessage-agent${NC}   $IMSG_DIR"
fi
echo ""
echo -e "  ${BLD}Wired:${NC}"
echo "    ~/.claude/settings.json   hooks, env vars, permissions"
if [ -n "$COMPOSIO_URL" ]; then
  echo "    .mcp.json                 Composio (100+ tools)"
else
  echo "    .mcp.json                 (add Composio URL later for 100+ integrations)"
fi
echo ""
echo -e "  ${BLD}Next steps:${NC}"
echo "    1. Fill in the rest of $PC_DIR/NOW.md, PEOPLE.md, SYSTEM.md"
echo "    2. Open a new Claude Code session — your context loads automatically"
echo "    3. Try: /sprint, /daily-brief, /inbox"
if [ -z "$COMPOSIO_URL" ]; then
  echo ""
  echo "    To add Composio (GitHub, Gmail, Calendar, Todoist, Vercel):"
  echo "    → Sign up at composio.dev, get your MCP URL"
  echo "    → Add to ~/.claude/.mcp.json under mcpServers.composio"
fi
echo ""
sep
echo ""

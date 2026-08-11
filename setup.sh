#!/bin/bash
# D1 Vibe Coding — Full Infrastructure Setup
#
# Run this ONCE from the D1-Vibe-Coding repo.
# It builds your entire Claude Code infrastructure in ~5 minutes.
#
# What it creates:
#   {name}-context      PRIVATE  Your personal second brain (projects, identity, contacts)
#   claude-context      PUBLIC   Operational instructions (CLAUDE.md, rules, commands)
#
# What it wires:
#   ~/.claude/settings.json     All hooks (format, sync, session context, Todoist)
#   ~/.mcp.json or .mcp.json    Composio MCP
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
section() { echo -e "\n${BLD}${BLU}$1${NC}"; }
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
BACKUP_DIR="$HOME/.claude/backups/d1-setup-$(date +%Y%m%d-%H%M%S)"
BACKED_UP=0

# Anyone who already uses Claude Code has a CLAUDE.md, hooks, and commands of
# their own. This script overwrites them by name. Copy first, always, and print
# where the copies went.
backup() {
  local src="$1" rel
  [ -e "$src" ] || return 0
  rel="${src#$HOME/.claude/}"
  mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
  cp -R "$src" "$BACKUP_DIR/$rel" 2>/dev/null || return 0
  BACKED_UP=1
}

# Every prompt below reads from stdin. Piped or cron-run, `read` hits EOF and
# `set -e` kills the script with a blank screen and exit 1. Say so instead.
if [ ! -t 0 ]; then
  err "setup.sh needs an interactive terminal. Run it directly, not piped."
  exit 1
fi

clear 2>/dev/null || true
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
echo ""
echo "  Hooks wired automatically:"
echo "    Session context injection on every Claude session"
echo "    PostToolUse auto-format + auto-sync to GitHub"
echo "    Todoist priorities injected at session start"
echo ""
read -rp "  Press Enter to begin..."

# ── Prerequisites ─────────────────────────────────────────────────────────────
section "Checking prerequisites"
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

if ! command -v python3 &>/dev/null; then
  err "python3 not found. It writes settings.json and .mcp config."
  MISSING=1
fi

if ! command -v jq &>/dev/null; then
  err "jq not found. Every hook parses its input with jq and will silently"
  err "  do nothing without it. Install: brew install jq"
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

# gh auth login lets you decline git credential setup, and every remote this
# script writes is HTTPS. Without this, push blocks on a username prompt.
gh auth setup-git &>/dev/null || true

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
section "About you"
echo ""

read -rp "  Your first name (e.g. John): " USER_NAME
USER_NAME="$(printf '%s' "$USER_NAME" | tr -cd '[:alnum:] _-' | xargs)"
if [ -z "$USER_NAME" ]; then
  err "A name is required. It becomes your context repo name."
  exit 1
fi
# Spaces and slashes break the repo name, the remote URL, and the sed below.
USER_NAME_LOWER=$(printf '%s' "$USER_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
PERSONAL_REPO="${USER_NAME_LOWER}-context"

echo ""
read -rsp "  Anthropic API key (sk-ant-...): " ANTHROPIC_KEY; echo
echo ""
read -rsp "  GitHub Personal Access Token (repo+workflow scopes): " GITHUB_PAT; echo
echo ""
read -rp "  Composio MCP URL (optional, press Enter to skip): " COMPOSIO_URL
echo ""
read -rsp "  Composio API Key (optional, press Enter to skip): " COMPOSIO_KEY; echo
echo ""
read -rsp "  Todoist API token (optional, press Enter to skip): " TODOIST_TOKEN; echo
echo ""

WORKSPACE_DIR="$HOME/dev"
read -rp "  Where should repos live? [$WORKSPACE_DIR]: " CUSTOM_DIR
WORKSPACE_DIR="${CUSTOM_DIR:-$WORKSPACE_DIR}"
# Quoted input means ~ never expands, and a relative path breaks the moment the
# script cd's into the first repo. Normalize before anything uses it.
WORKSPACE_DIR="${WORKSPACE_DIR/#\~/$HOME}"
case "$WORKSPACE_DIR" in /*) ;; *) WORKSPACE_DIR="$PWD/$WORKSPACE_DIR" ;; esac
mkdir -p "$WORKSPACE_DIR"
WORKSPACE_DIR="$(cd "$WORKSPACE_DIR" && pwd)"

echo ""
sep
echo ""

# ── Repo 1: {name}-context (private) ─────────────────────────────────────────
section "Creating $PERSONAL_REPO (private personal brain)"

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
PICKED_EDITOR=""
for e in "${EDITOR:-}" nano vi; do
  [ -n "$e" ] && command -v "${e%% *}" &>/dev/null && PICKED_EDITOR="$e" && break
done
if [ -n "$PICKED_EDITOR" ]; then
  $PICKED_EDITOR "$PC_DIR/YOU.md" || true
else
  warn "No usable editor found. Fill in $PC_DIR/YOU.md by hand later."
fi

if gh repo view "$GITHUB_USER/$PERSONAL_REPO" &>/dev/null; then
  warn "Repo $GITHUB_USER/$PERSONAL_REPO already exists — using existing"
else
  gh repo create "$GITHUB_USER/$PERSONAL_REPO" \
    --private \
    --description "$USER_NAME's personal context for Claude — identity, projects, contacts" \
    2>/dev/null || true
  if gh repo view "$GITHUB_USER/$PERSONAL_REPO" &>/dev/null; then
    log "Created github.com/$GITHUB_USER/$PERSONAL_REPO (private)"
  else
    warn "Could not create $GITHUB_USER/$PERSONAL_REPO. Check your token scopes."
    warn "  Local files are still written; create the repo and push by hand."
  fi
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
section "Creating claude-context (public operational rules)"

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
- \`.claude/rules/\` — 6 always-on standards, imported by CLAUDE.md
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
READMEOF

if gh repo view "$GITHUB_USER/claude-context" &>/dev/null; then
  warn "Repo $GITHUB_USER/claude-context already exists — using existing"
else
  gh repo create "$GITHUB_USER/claude-context" \
    --public \
    --description "Claude Code operational instructions — design system, rules, commands" \
    2>/dev/null || true
  if gh repo view "$GITHUB_USER/claude-context" &>/dev/null; then
    log "Created github.com/$GITHUB_USER/claude-context (public)"
  else
    warn "Could not create $GITHUB_USER/claude-context. Check your token scopes."
    warn "  Local files are still written; create the repo and push by hand."
  fi
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

# ── iMessage agent ────────────────────────────────────────────────────────────
# Not bundled. This used to clone calebnewtonusc/imessage-agent, which does not
# exist, so every user who said yes got a warning and nothing else. The pattern
# is documented in second-brain/agents/imessage.md if you want to build one;
# setup.sh will not pretend to install it.
IMSG_DIR=""
SETUP_IMESSAGE=0

# ── Wire ~/.claude/settings.json ─────────────────────────────────────────────
section "Wiring ~/.claude/settings.json"

for existing in "$HOME/.claude/settings.json" "$HOME/.claude/CLAUDE.md" \
  "$HOME/.claude/commands" "$HOME/.claude/rules" "$HOME/.claude/hooks" \
  "$HOME/.claude/agents" "$HOME/.claude/skills" "$HOME/.claude.json"; do
  backup "$existing"
done
if [ "$BACKED_UP" -eq 1 ]; then
  log "Existing config backed up to $BACKUP_DIR"
fi

SETTINGS="$HOME/.claude/settings.json"
mkdir -p "$HOME/.claude/hooks"

# Hook logic lives in script files, not in escaped one-liners inside JSON. The
# SessionStart command used to be a single string with seven levels of
# backslash escaping: it worked, and nobody could read or safely change it.
cp "$SCRIPT_DIR/.claude/hooks/"*.sh "$HOME/.claude/hooks/" 2>/dev/null || true
chmod +x "$HOME/.claude/hooks/"*.sh 2>/dev/null || true
log "Hooks installed to ~/.claude/hooks/"

# Hooks read their paths from here instead of having them baked in by string
# substitution. Edit this file to move your context repos later.
cat > "$HOME/.claude/d1-config.sh" << D1CONFIG
# Written by D1-Vibe-Coding setup.sh. Safe to edit by hand.
PERSONAL_CONTEXT_DIR="$PC_DIR"
PUBLIC_CONTEXT_DIR="$CC_DIR"
CONTEXT_OWNER="$USER_NAME"
D1CONFIG
log "Hook config written to ~/.claude/d1-config.sh"

# ── Two behaviors this kit turns on by design ────────────────────────────────
# Both are deliberate and neither is prompted. If you are handing this to
# someone, tell them up front. Editing ~/.claude/settings.json afterward turns
# either one off.
echo ""
echo "  Two behaviors are enabled by default:"
echo ""
echo "    Session opener   Every response starts with a prayer."
echo "                     Change or remove it in ~/.claude/settings.json"
echo "                     under hooks.UserPromptSubmit."
echo ""
echo "    bypassPermissions  Claude writes files and runs shell commands"
echo "                       without asking each time. Change it in"
echo "                       ~/.claude/settings.json under permissions.defaultMode."
echo ""

# Secrets and paths reach python through the environment. Interpolating them
# into python source breaks the moment a token contains a quote or backslash.
# An expired or wrong-scoped PAT written into env breaks gh in every future
# session, and confusingly, because the env var beats the keyring.
if [ -n "${GITHUB_PAT:-}" ] && ! GH_TOKEN="$GITHUB_PAT" gh api user &>/dev/null; then
  warn "That GitHub token failed a live check. Leaving GITHUB_TOKEN unset so it"
  warn "  cannot break gh in every session. Add a working one later if needed."
  GITHUB_PAT=""
fi
export D1_GITHUB_PAT="${GITHUB_PAT:-}"
export D1_ANTHROPIC_KEY="${ANTHROPIC_KEY:-}"
export D1_TODOIST_TOKEN="${TODOIST_TOKEN:-}"
export D1_PC_DIR="${PC_DIR:-}"
export D1_CC_DIR="${CC_DIR:-}"
export D1_IMSG_DIR="${IMSG_DIR:-}"
export D1_HOOKS="$HOME/.claude/hooks"

python3 << 'PYEOF'
import json, os, shlex

settings_path = os.path.expanduser("~/.claude/settings.json")
try:
    with open(settings_path) as f:
        settings = json.load(f)
except Exception:
    settings = {}

env = os.environ.get
hooks_dir = env("D1_HOOKS") or os.path.expanduser("~/.claude/hooks")

settings.setdefault("env", {})
for key, var in (("GITHUB_TOKEN", "D1_GITHUB_PAT"),
                 ("ANTHROPIC_API_KEY", "D1_ANTHROPIC_KEY"),
                 ("TODOIST_API_TOKEN", "D1_TODOIST_TOKEN")):
    val = env(var, "").strip()
    if val:
        settings["env"][key] = val

perms = settings.setdefault("permissions", {})
# On by design. The whole point of the kit is that Claude acts instead of
# stopping to ask. Flip this to "default" in ~/.claude/settings.json if you
# want the confirmation step back.
perms["defaultMode"] = "bypassPermissions"

perms.setdefault("additionalDirectories", [])
for d in (env("D1_PC_DIR", ""), env("D1_CC_DIR", ""), env("D1_IMSG_DIR", "")):
    if d and d not in perms["additionalDirectories"]:
        perms["additionalDirectories"].append(d)

perms.setdefault("allow", [])
# Deliberately NOT granted here: Read(~/Library/Messages/**), Bash(osascript:*),
# and Bash(sqlite3:*). Under bypassPermissions those would let every future
# session read the user's entire message history without ever asking. Add them
# yourself if you build something that needs them.
if "WebSearch" not in perms["allow"]:
    perms["allow"].append("WebSearch")

# Nothing prompts under bypassPermissions, so the deny list is the only brake
# left. It covers operations with no undo, and reads that would pull a secret
# into context where it can be echoed back or logged. deny wins over allow.
perms.setdefault("deny", [])
for rule in [
    "Bash(rm -rf /)", "Bash(rm -rf /*)", "Bash(rm -rf ~)", "Bash(rm -rf ~/*)",
    "Bash(sudo rm:*)",
    "Bash(git push --force*)", "Bash(git push -f*)", "Bash(git reset --hard origin*)",
    "Bash(gh repo delete:*)", "Bash(dropdb:*)",
    "Read(./.env)", "Read(./.env.*)",
    "Read(" + settings_path + ")",
    "Read(" + os.path.expanduser("~") + "/.claude/.credentials.json)",
    "Read(" + os.path.expanduser("~") + "/.ssh/**)",
    "Read(" + os.path.expanduser("~") + "/.aws/**)",
]:
    if rule not in perms["deny"]:
        perms["deny"].append(rule)

settings["enableAllProjectMcpServers"] = True
settings["alwaysThinkingEnabled"] = True

h = settings.setdefault("hooks", {})

# Session opener. On by design, same as bypassPermissions above. Edit the text
# here or in ~/.claude/settings.json under hooks.UserPromptSubmit.
opener_payload = json.dumps({"hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": (
        "MANDATORY: Begin every response with a prayer to Jesus. "
        "Specific to what is actually being worked on, personal, varied, "
        "ending with Amen. Then respond."
    ),
}})
h["UserPromptSubmit"] = [{"hooks": [{
    "type": "command",
    "command": "printf '%s' " + shlex.quote(opener_payload),
    "statusMessage": "Session opener",
}]}]

h["PostToolUse"] = [{"matcher": "Write|Edit", "hooks": [{
    "type": "command",
    "command": hooks_dir + "/format-and-sync.sh",
    "statusMessage": "Formatting and syncing...",
    "async": True,
}]}]

h["SessionStart"] = [{"hooks": [{
    "type": "command",
    "command": hooks_dir + "/session-context.sh",
    "statusMessage": "Loading your context...",
}]}]

h["Stop"] = [{"hooks": [{
    "type": "command",
    "command": hooks_dir + "/stop-check.sh",
    "statusMessage": "Checking for unpushed work...",
}]}]

h["PreToolUse"] = [{"matcher": "Write", "hooks": [{
    "type": "command",
    "command": hooks_dir + "/env-guard.sh",
    "statusMessage": "Checking file safety...",
}]}]

h["Notification"] = [{"hooks": [{
    "type": "command",
    "command": "say 'Claude Code task complete' 2>/dev/null || true",
    "async": True,
}]}]

# The file now holds an Anthropic key and a GitHub PAT. Write it atomically so
# a crash cannot truncate it, and 0600 so it is not world-readable.
tmp_path = settings_path + ".tmp"
with open(tmp_path, "w") as f:
    json.dump(settings, f, indent=2)
os.chmod(tmp_path, 0o600)
os.replace(tmp_path, settings_path)

print("Settings written.")
PYEOF

unset D1_GITHUB_PAT D1_ANTHROPIC_KEY D1_TODOIST_TOKEN
log "~/.claude/settings.json configured"


# ── Wire .mcp.json ────────────────────────────────────────────────────────────
section "Wiring .mcp.json"

MCP_FILE="$HOME/.claude.json"

export D1_MCP_FILE="${MCP_FILE:-}"
export D1_COMPOSIO_URL="${COMPOSIO_URL:-}"
export D1_COMPOSIO_KEY="${COMPOSIO_KEY:-}"

python3 << 'PYEOF2'
import json, os

# Same reason as the settings block: values come through the environment so a
# key containing a quote or backslash cannot break the script.
env = os.environ.get

mcp_path = env("D1_MCP_FILE", "")
if not mcp_path:
    raise SystemExit(0)

parent = os.path.dirname(mcp_path)
if parent:
    os.makedirs(parent, exist_ok=True)

try:
    with open(mcp_path) as f:
        mcp = json.load(f)
except Exception:
    mcp = {"mcpServers": {}}

# This file carries the user's whole Claude Code state, not just MCP. Touch
# exactly one key and write atomically; a truncated write here is expensive.
mcp.setdefault("mcpServers", {})

composio_url = env("D1_COMPOSIO_URL", "").strip()
composio_key = env("D1_COMPOSIO_KEY", "").strip()

if composio_url:
    mcp["mcpServers"]["composio"] = {
        "url": composio_url,
        "headers": {"x-api-key": composio_key} if composio_key else {},
    }

# The iMessage agent is a CLI (bun run agent.ts --mode scan/inbox/run). It does
# not speak MCP stdio, so Claude invokes it through Bash and it gets no entry here.

tmp_path = mcp_path + ".tmp"
with open(tmp_path, "w") as f:
    json.dump(mcp, f, indent=2)
os.replace(tmp_path, mcp_path)

print("MCP config written.")
PYEOF2

unset D1_MCP_FILE D1_COMPOSIO_URL D1_COMPOSIO_KEY
log ".mcp.json configured"

# ── Install D1 rules globally ─────────────────────────────────────────────────
section "Installing rules and commands globally"

GLOBAL_CLAUDE="$HOME/.claude"
mkdir -p "$GLOBAL_CLAUDE/commands" "$GLOBAL_CLAUDE/rules"

cp "$SCRIPT_DIR/.claude/commands/"*.md "$GLOBAL_CLAUDE/commands/" 2>/dev/null || true
cp "$SCRIPT_DIR/.claude/rules/"*.md    "$GLOBAL_CLAUDE/rules/"    2>/dev/null || true
mkdir -p "$GLOBAL_CLAUDE/agents"
cp "$SCRIPT_DIR/.claude/agents/"*.md   "$GLOBAL_CLAUDE/agents/"   2>/dev/null || true
cp "$SCRIPT_DIR/CLAUDE.md"             "$GLOBAL_CLAUDE/CLAUDE.md" 2>/dev/null || true

log "Commands installed to ~/.claude/commands/ ($(ls "$SCRIPT_DIR"/.claude/commands/*.md | wc -l | tr -d ' ') files)"
log "Rules installed to ~/.claude/rules/ ($(ls "$SCRIPT_DIR"/.claude/rules/*.md | wc -l | tr -d ' ') files)"
log "Subagents installed to ~/.claude/agents/ ($(ls "$SCRIPT_DIR"/.claude/agents/*.md | wc -l | tr -d ' ') agents)"
log "CLAUDE.md installed to ~/.claude/CLAUDE.md"

# ── Skills and plugins ────────────────────────────────────────────────────────
section "Installing skills and plugins"

mkdir -p "$GLOBAL_CLAUDE/skills"
cp -R "$SCRIPT_DIR/skills/." "$GLOBAL_CLAUDE/skills/" 2>/dev/null || true
log "Skills installed to ~/.claude/skills/"

# BEGIN GENERATED: extensions
# Upstream skills are cloned rather than vendored, so each stays updatable and
# keeps the LICENSE it shipped with. add-skill.sh does the same thing by hand.
while IFS='|' read -r SK_NAME SK_URL SK_PATH SK_LICENSE SK_AUTHOR; do
  [ -n "$SK_NAME" ] || continue
  if [ -d "$GLOBAL_CLAUDE/skills/$SK_NAME" ]; then
    log "$SK_NAME already present, left alone"
    continue
  fi
  TMP_SK="$(mktemp -d)"
  if git clone -q --depth 1 "$SK_URL" "$TMP_SK" 2>/dev/null; then
    SK_SRC="$TMP_SK"
    [ -n "$SK_PATH" ] && SK_SRC="$TMP_SK/$SK_PATH"
    mkdir -p "$GLOBAL_CLAUDE/skills/$SK_NAME"
    cp -R "$SK_SRC/." "$GLOBAL_CLAUDE/skills/$SK_NAME/" 2>/dev/null || true
    rm -rf "$GLOBAL_CLAUDE/skills/$SK_NAME/.git"
    [ -f "$TMP_SK/LICENSE" ] && cp "$TMP_SK/LICENSE" "$GLOBAL_CLAUDE/skills/$SK_NAME/LICENSE" 2>/dev/null
    printf 'source: %s\ninstalled: %s\n' "$SK_URL" "$(date -u +%Y-%m-%d)" \
      > "$GLOBAL_CLAUDE/skills/$SK_NAME/.source"
    log "$SK_NAME installed ($SK_LICENSE, $SK_AUTHOR)"
  else
    warn "Could not reach GitHub for $SK_NAME. See docs/EXTENSIONS.md to add it later."
  fi
  rm -rf "$TMP_SK"
done <<'UPSTREAM_SKILLS'
avoid-ai-writing|https://github.com/conorbronsdon/avoid-ai-writing||MIT|conorbronsdon
no-ai-slop|https://github.com/petergyang/no-ai-slop|skills/no-ai-slop|MIT|petergyang
youtube-transcripts|https://github.com/calebnewtonusc/claude-youtube-transcripts|skills/youtube-transcripts|MIT|calebnewtonusc
UPSTREAM_SKILLS

if command -v claude &>/dev/null; then
  for m in \
    Egonex-AI/Understand-Anything \
    anthropics/claude-plugins-official \
    blader/humanizer; do
    claude plugin marketplace add "$m" </dev/null &>/dev/null || true
  done
  log "Marketplaces registered"

  PLUGIN_FAILED=0
  for p in \
    bigquery-data-analytics@claude-plugins-official \
    context7@claude-plugins-official \
    expo@claude-plugins-official \
    humanizer@humanizer \
    pinecone@claude-plugins-official \
    playwright@claude-plugins-official \
    railway@claude-plugins-official \
    serena@claude-plugins-official \
    understand-anything@understand-anything \
    vercel@claude-plugins-official; do
    if claude plugin install "$p" --scope user </dev/null &>/dev/null; then
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

# Self-hosted MCP servers. Each needs its own service running; see docs/EXTENSIONS.md.
#   prompt-optimizer: https://github.com/linshenkx/prompt-optimizer
# END GENERATED: extensions

# ── Verify ────────────────────────────────────────────────────────────────────
# Claiming success without checking is how this kit shipped six months of
# silently broken hooks. Prove the install works before saying it worked.
section "Verifying the install"

if [ -x "$SCRIPT_DIR/doctor.sh" ]; then
  if "$SCRIPT_DIR/doctor.sh"; then
    log "All checks passed"
  else
    warn "Some checks failed. Fix them, then re-run: ./doctor.sh"
  fi
else
  warn "doctor.sh not found or not executable, skipping verification"
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

#!/bin/bash
# Chewbacca: Full Infrastructure Setup
#
# Run this ONCE from the Chewbacca repo.
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
#   git clone https://github.com/calebnewtonusc/Chewbacca
#   cd Chewbacca
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
echo -e "  ${BLD}Chewbacca: Infrastructure Setup${NC}"
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
cp "$SCRIPT_DIR/second-brain/context/SCHOOL.md" "$PC_DIR/SCHOOL.md"

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
  warn "Repo $GITHUB_USER/$PERSONAL_REPO already exists, using existing"
else
  gh repo create "$GITHUB_USER/$PERSONAL_REPO" \
    --private \
    --description "$USER_NAME's personal context for Claude, identity, projects, contacts" \
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

git add -- .gitignore YOU.md NOW.md PEOPLE.md SYSTEM.md STACK.md SCHOOL.md
git diff --cached --quiet || git commit -q -m "init: $USER_NAME personal context"
git branch -M main
git push -u origin main -q 2>/dev/null || warn "Push failed, you may need to push manually"
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

Forked from [Chewbacca](https://github.com/calebnewtonusc/Chewbacca).

## What's here

- \`CLAUDE.md\`, full design system, behavioral rules, coding standards
- \`.claude/commands/\`: 48 slash commands covering the dev lifecycle, coursework, and the weekly review
- \`.claude/rules/\`: 6 always-on standards, imported by CLAUDE.md
- \`.claude/hooks/\`: PostToolUse formatters and linters

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

Built and maintained at [Chewbacca](https://github.com/calebnewtonusc/Chewbacca).
READMEOF

if gh repo view "$GITHUB_USER/claude-context" &>/dev/null; then
  warn "Repo $GITHUB_USER/claude-context already exists, using existing"
else
  gh repo create "$GITHUB_USER/claude-context" \
    --public \
    --description "Claude Code operational instructions, design system, rules, commands" \
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
git diff --cached --quiet || git commit -q -m "init: claude-context from Chewbacca"
git branch -M main
git push -u origin main -q 2>/dev/null || warn "Push failed, you may need to push manually"
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

# Both scanners score something with no model in the loop, so a cheap
# deterministic check can run before anything spends tokens. ai-scan reads prose
# for AI-writing tells; skill-scan reads skills for whether they will fire.
_installed_scanners=""
for _tool in ai-scan skill-scan; do
  if [ -f "$SCRIPT_DIR/bin/$_tool" ]; then
    mkdir -p "$HOME/.local/bin"
    cp "$SCRIPT_DIR/bin/$_tool" "$HOME/.local/bin/$_tool"
    chmod +x "$HOME/.local/bin/$_tool"
    _installed_scanners="$_installed_scanners $_tool"
  fi
done
if [ -n "$_installed_scanners" ]; then
  if command -v node &>/dev/null; then
    log "Installed to ~/.local/bin/:$_installed_scanners"
  else
    warn "Installed$_installed_scanners but node is missing, so they will not run until you install node >= 18"
  fi
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) warn "~/.local/bin is not on your PATH. Add it to run$_installed_scanners by name." ;;
  esac
fi
unset _tool _installed_scanners

# coursework reads a semester ledger built from your syllabi: what is due, what
# an absence costs, what each course allows you to use AI for. Deterministic, so
# Claude spends its tokens on judgment instead of re-reading a PDF.
if [ -f "$SCRIPT_DIR/bin/coursework" ]; then
  mkdir -p "$HOME/.local/bin"
  cp "$SCRIPT_DIR/bin/coursework" "$HOME/.local/bin/coursework"
  chmod +x "$HOME/.local/bin/coursework"
  COURSEWORK_HOME="${COURSEWORK_DIR:-$HOME/coursework}"
  mkdir -p "$COURSEWORK_HOME/courses" "$COURSEWORK_HOME/syllabi" "$COURSEWORK_HOME/templates"
  cp "$SCRIPT_DIR/templates/coursework/"*.yml "$COURSEWORK_HOME/templates/" 2>/dev/null || true
  log "coursework installed to ~/.local/bin/, ledger at $COURSEWORK_HOME"
  echo "    Next: run /syllabus on a syllabus PDF to fill the ledger."
fi

# Hooks read their paths from here instead of having them baked in by string
# substitution. Edit this file to move your context repos later.
cat > "$HOME/.claude/d1-config.sh" << D1CONFIG
# Written by Chewbacca setup.sh. Safe to edit by hand.
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
echo "                       without asking each time. It is set in three"
echo "                       places, because there are three ways to run"
echo "                       Claude and each has its own switch:"
echo "                         permissions.defaultMode in ~/.claude/settings.json"
echo "                         claudeCode.* in your editor user settings"
echo "                         dispatchCodeTasksPermissionMode in the desktop app"
echo "                       Undo any one of them and that surface asks again."
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


# ── Wire the editor extension ─────────────────────────────────────────────────
# permissions.defaultMode above is only half of it. The VS Code extension gates
# bypass mode behind its own setting, so with the CLI configured and the editor
# not, you still get prompted inside the editor. This merges the keys from
# settings/vscode-settings.json into whichever editors are installed.
section "Wiring editor settings"

export D1_EDITOR_TEMPLATE="$SCRIPT_DIR/settings/vscode-settings.json"

python3 << 'PYEDITOR'
import json, os, re, shutil

template_path = os.environ.get("D1_EDITOR_TEMPLATE", "")
try:
    with open(template_path) as f:
        template = json.load(f)
except Exception:
    print("  ! settings/vscode-settings.json not readable, skipping editors")
    raise SystemExit(0)

# Keys starting with _comment document the template. They are not settings.
desired = {k: v for k, v in template.items() if not k.startswith("_comment")}

home = os.path.expanduser("~")
if os.name == "nt":
    base = os.path.join(os.environ.get("APPDATA", ""), "")
elif os.uname().sysname == "Darwin":
    base = os.path.join(home, "Library", "Application Support")
else:
    base = os.path.join(home, ".config")

editors = [
    ("VS Code", "Code"),
    ("VS Code Insiders", "Code - Insiders"),
    ("Cursor", "Cursor"),
    ("VSCodium", "VSCodium"),
    ("Windsurf", "Windsurf"),
]

def strip_jsonc(text):
    # VS Code writes real JSON but accepts JSONC, and people hand-edit these
    # files with comments in them. Strip // and /* */ outside strings, then
    # trailing commas, so a commented file is updated instead of clobbered.
    out, i, n = [], 0, len(text)
    in_str = escaped = False
    while i < n:
        c = text[i]
        if in_str:
            out.append(c)
            if escaped:
                escaped = False
            elif c == "\\":
                escaped = True
            elif c == '"':
                in_str = False
            i += 1
            continue
        if c == '"':
            in_str = True
            out.append(c)
            i += 1
        elif text.startswith("//", i):
            while i < n and text[i] != "\n":
                i += 1
        elif text.startswith("/*", i):
            end = text.find("*/", i + 2)
            i = n if end == -1 else end + 2
        else:
            out.append(c)
            i += 1
    return re.sub(r",(\s*[}\]])", r"\1", "".join(out))

touched = 0
for label, dirname in editors:
    user_dir = os.path.join(base, dirname, "User")
    if not os.path.isdir(user_dir):
        continue
    path = os.path.join(user_dir, "settings.json")

    current = {}
    if os.path.exists(path):
        with open(path) as f:
            raw = f.read()
        for candidate in (raw, strip_jsonc(raw)):
            try:
                parsed = json.loads(candidate) if candidate.strip() else {}
            except Exception:
                continue
            if isinstance(parsed, dict):
                current = parsed
                break
        else:
            # Unparseable. Adding keys blind would destroy real settings.
            print("  ! " + label + " settings.json could not be parsed. Left alone.")
            print("    Add these by hand: claudeCode.allowDangerouslySkipPermissions,")
            print("    claudeCode.initialPermissionMode")
            continue
        shutil.copy2(path, path + ".d1-backup")

    # The user's own choices win, except for the two keys that are the whole
    # point of this step. Reruns of setup.sh should not undo a deliberate
    # "actually, prompt me" decision on the cosmetic keys.
    forced = {"claudeCode.allowDangerouslySkipPermissions",
              "claudeCode.initialPermissionMode"}
    for key, value in desired.items():
        if key in forced or key not in current:
            current[key] = value

    os.makedirs(user_dir, exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(current, f, indent=2)
    os.replace(tmp, path)
    print("  " + label + " configured")
    touched += 1

if touched == 0:
    print("  No supported editor found. Nothing to do.")
else:
    print("  Restart the editor for the change to take effect.")
PYEDITOR

unset D1_EDITOR_TEMPLATE
log "Editor settings configured"

# ── Wire the Claude desktop app ───────────────────────────────────────────────
# The desktop app runs its own copy of the CLI and reads ~/.claude/settings.json,
# so permissions.defaultMode above already covers its chat and code sessions.
# What it does NOT cover is coding tasks dispatched from the app, which have a
# separate preference of their own that ships defaulting to "acceptEdits", so
# bash commands still stop and ask. That preference lives in the app's own
# config store, not in settings.json.
section "Wiring the Claude desktop app"

if pgrep -x "Claude" >/dev/null 2>&1; then
  warn "Claude is running. It rewrites its config on quit, which would drop this"
  warn "  change. Quit Claude, then rerun setup.sh, or set Code tasks to bypass"
  warn "  from the app's own settings."
fi

python3 << 'PYDESKTOP'
import json, os, shutil

home = os.path.expanduser("~")
if os.name == "nt":
    appdata = os.environ.get("APPDATA", "")
    base = os.path.join(appdata, "Claude") if appdata else ""
elif os.uname().sysname == "Darwin":
    base = os.path.join(home, "Library", "Application Support", "Claude")
else:
    base = os.path.join(home, ".config", "Claude")

if not base or not os.path.isdir(base):
    print("  Claude desktop app not installed. Nothing to do.")
    raise SystemExit(0)

path = os.path.join(base, "config.json")
config = {}
if os.path.exists(path):
    try:
        with open(path) as f:
            config = json.load(f)
    except Exception:
        # The app renames an unparseable config to .corrupt-<ts> and starts
        # fresh. Writing over it here would throw away whatever it could still
        # recover, and the app will rebuild it anyway.
        print("  ! config.json is not valid JSON. Left alone; the app will rebuild it.")
        raise SystemExit(0)
    if not isinstance(config, dict):
        print("  ! config.json is not an object. Left alone.")
        raise SystemExit(0)
    shutil.copy2(path, path + ".d1-backup")

# Enum the app accepts: default, acceptEdits, plan, auto, bypassPermissions.
# Anything else fails its schema check and the app discards the whole file.
config["dispatchCodeTasksPermissionMode"] = "bypassPermissions"

tmp = path + ".tmp"
with open(tmp, "w") as f:
    json.dump(config, f, indent=2)
# The store holds account identifiers. Keep it owner-only, the way the app
# writes it, instead of inheriting the umask.
os.chmod(tmp, 0o600)
os.replace(tmp, path)
print("  Code tasks set to bypassPermissions")
PYDESKTOP

log "Claude desktop app configured"


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

# Output styles replace Claude Code's software-engineering system prompt rather
# than adding to it, which is what the other four layers cannot do. Installed,
# never selected: picking one is a per-project choice made in /config.
mkdir -p "$GLOBAL_CLAUDE/output-styles"
cp "$SCRIPT_DIR/.claude/output-styles/"*.md "$GLOBAL_CLAUDE/output-styles/" 2>/dev/null || true
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

# ── macOS tools ───────────────────────────────────────────────────────────────
# Screen control, Google Workspace, summarization, clipboard history, and the
# agent-scripts skill pack. Everything here is optional: a failure warns and the
# install continues.
section "Installing macOS tools"

# BEGIN GENERATED: cli
# Kit-owned helpers that sit in front of the installed tools.
#   peekaboo: forces local execution, see docs/MACOS-TOOLS.md
#   chrome-js: reads and clicks a Chrome tab through JavaScript
mkdir -p "$HOME/.local/bin"
for HELPER in peekaboo chrome-js; do
  if [ -f "$SCRIPT_DIR/bin/$HELPER" ]; then
    cp "$SCRIPT_DIR/bin/$HELPER" "$HOME/.local/bin/$HELPER"
    chmod +x "$HOME/.local/bin/$HELPER"
    log "$HELPER installed to ~/.local/bin/"
  fi
done

# macOS command-line tools. Skipped without Homebrew, and skipped one by
# one if already present, so this is safe to re-run.
if command -v brew &>/dev/null; then
  if [ -d "/Applications/Maccy.app" ]; then
    log "Maccy already installed"
  else
    brew install --cask maccy &>/dev/null && log "Maccy installed" || warn "could not install Maccy"
  fi
  if [ -x /opt/homebrew/bin/peekaboo ]; then
    log "peekaboo already installed"
  else
    brew install openclaw/tap/peekaboo &>/dev/null && log "peekaboo installed" || warn "could not install peekaboo"
  fi
  if command -v summarize &>/dev/null; then
    log "summarize already installed"
  else
    brew install steipete/tap/summarize &>/dev/null && log "summarize installed" || warn "could not install summarize"
  fi
else
  warn "Homebrew not found. macOS tools skipped: see docs/MACOS-TOOLS.md"
fi

# mac: Calendar, Reminders, Contacts, Mail, Messages, Notes, and Finder as JSON
if [ "$(uname -s)" != "Darwin" ]; then
  :
elif command -v mac &>/dev/null; then
  log "mac-cli already installed"
elif ! command -v swift &>/dev/null; then
  warn "swift not found, skipping mac-cli. Run: xcode-select --install"
else
  MC_DIR="$HOME/Projects/mac-cli"
  [ -d "$MC_DIR/.git" ] || git clone -q --depth 1 \
    https://github.com/31Carlton7/mac-cli.git "$MC_DIR" 2>/dev/null || true
  if [ -d "$MC_DIR" ]; then
    # SwiftPM caches dependencies as bare repos, which a global
    # safe.bareRepository=explicit forbids it from reading. Override the
    # setting for this one build rather than changing it machine-wide.
    if (cd "$MC_DIR" && GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository \
        GIT_CONFIG_VALUE_0=all swift build -c release &>/dev/null); then
      mkdir -p "$HOME/.local/bin"
      install "$MC_DIR/.build/release/mac" "$HOME/.local/bin/mac"
      log "mac-cli installed. Run: mac doctor  (grants are per-terminal)"
    else
      warn "mac-cli build failed. Retry: cd $MC_DIR && swift build -c release"
    fi
  else
    warn "could not clone mac-cli"
  fi
fi

# mac-use: Natural-language agent that drives any Mac app through Accessibility
if command -v mac-use &>/dev/null; then
  log "mac-use already installed"
elif ! command -v uv &>/dev/null; then
  warn "uv not found, skipping macOS-use. See docs/MACOS-TOOLS.md"
else
  MU_DIR="$HOME/Projects/macOS-use"
  [ -d "$MU_DIR/.git" ] || git clone -q --depth 1 \
    https://github.com/browser-use/macOS-use.git "$MU_DIR" 2>/dev/null || true
  if [ -d "$MU_DIR" ]; then
    cp "$SCRIPT_DIR/bin/mac_use_cli.py" "$MU_DIR/mac_use_cli.py"
    cp "$SCRIPT_DIR/bin/mac_use_claude.py" "$MU_DIR/mac_use_claude.py"
    mkdir -p "$HOME/.local/bin"
    cp "$SCRIPT_DIR/bin/mac-use" "$HOME/.local/bin/mac-use"
    chmod +x "$HOME/.local/bin/mac-use"
    if (cd "$MU_DIR" && uv venv --python 3.11 &>/dev/null \
        && uv pip install --python .venv/bin/python --editable . &>/dev/null); then
      log "mac-use installed"
    else
      warn "macOS-use deps failed. Retry: cd $MU_DIR && uv pip install -e ."
    fi
  else
    warn "could not clone macOS-use"
  fi
fi

# peekaboo speaks MCP too. Registered at user scope so it is available in
# every project, not just this one.
if command -v claude &>/dev/null && command -v peekaboo &>/dev/null; then
  if claude mcp list 2>/dev/null | grep -q "^peekaboo:"; then
    log "peekaboo MCP already registered"
  elif claude mcp add peekaboo --scope user -- peekaboo mcp serve &>/dev/null; then
    log "peekaboo MCP registered"
  else
    warn "could not register the peekaboo MCP server"
  fi
fi

# Skill pack: agent-scripts. Linked per skill, not copied, so `git pull` in
# the clone updates every skill at once.
#
# Its own installer (scripts/sync-skills) repoints ~/.claude/CLAUDE.md at the
# pack's AGENTS.MD, which would replace your global instructions. Do not run
# it. The loop below does the linking and touches nothing else.
PACK_DIR="$HOME/Projects/agent-scripts"
PACK_SKIP="codex-first"
if [ -d "$PACK_DIR/.git" ]; then
  log "agent-scripts already cloned, left alone"
elif git clone -q --depth 1 "https://github.com/steipete/agent-scripts.git" "$PACK_DIR" 2>/dev/null; then
  log "agent-scripts cloned"
else
  warn "could not clone agent-scripts"
fi
if [ -d "$PACK_DIR/skills" ]; then
  PACK_N=0
  for SK in "$PACK_DIR"/skills/*/; do
    SK_NAME="$(basename "$SK")"
    [ -f "$SK/SKILL.md" ] || continue
    case " $PACK_SKIP " in *" $SK_NAME "*) continue;; esac
    [ -e "$GLOBAL_CLAUDE/skills/$SK_NAME" ] && continue
    ln -s "$SK" "$GLOBAL_CLAUDE/skills/$SK_NAME"
    PACK_N=$((PACK_N+1))
  done
  log "agent-scripts: $PACK_N skills linked"
fi
# END GENERATED: cli

# ── Plynn ─────────────────────────────────────────────────────────────────────
# On-device dictation by Carlton Aikins (github.com/31Carlton7/plynn, MIT).
# Hold fn, talk, release, and clean text lands wherever the cursor is. Speech
# recognition and cleanup both run on the Mac, nothing is uploaded.
#
# Deliberately outside the GENERATED regions above: this is a hand-written step
# and d1-inventory.py would overwrite it.
section "Installing Plynn (on-device dictation)"

if [ -x "$SCRIPT_DIR/bin/install-plynn.sh" ]; then
  "$SCRIPT_DIR/bin/install-plynn.sh" || warn "Plynn install returned non-zero, continuing"
else
  warn "bin/install-plynn.sh missing, skipping Plynn"
fi

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
echo "    2. Open a new Claude Code session, your context loads automatically"
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

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

# ── Inputs ────────────────────────────────────────────────────────────────────
# Every value arrives as a flag or in an answers file. There are no read calls
# anywhere in this script, for three reasons.
#
#   1. An agent could not run it. The old version refused to start without a
#      TTY, so Claude could not set this up on your behalf even when asked to.
#   2. Blank prompts were not blank. A value already exported in the shell
#      survived an empty answer and got written to settings.json as though you
#      had typed it. Credentials now come only from a flag or the answers file.
#   3. A terminal questionnaire is the wrong surface for a Claude Code kit. The
#      /setup skill asks these in chat and calls this script with the answers.
#
# Anything not passed is simply not configured. Nothing is inferred from the
# environment, the keychain, or `gh auth token`.

usage() {
  cat <<'USAGE'
Chewbacca setup. Non-interactive by design.

The easy way, in Claude:

  claude "run the setup skill"

The direct way:

  ./setup.sh --name Jane [options]
  ./setup.sh --answers setup.answers.json

Required:
  --name <first name>          Becomes your private context repo name.

Optional:
  --github-user <login>        Defaults to the logged-in gh account.
  --repo-dir <path>            Where repos live. Default ~/dev
  --anthropic-key <key>        Written to settings.json env. Omit to leave unset.
  --github-token <token>       Written to settings.json env. Omit to leave unset.
  --todoist-token <token>      Written to settings.json env. Omit to leave unset.
  --composio-url <url>         Composio MCP endpoint.
  --composio-key <key>         Composio API key.
  --answers <file.json>        Read every value above from JSON instead.

Who this install is for:
  --skip <section>             skip one section, repeatable
  --profile <name>             personal   Claude for your life. No GitHub, no
                                          repos, no stack rules, no coursework.
                               student    personal plus the coursework ledger
                                          and the study skills.
                               developer  Everything. The default, and what
                                          every previous version did.
  --no-github                  Skip GitHub entirely. Your second brain stays a
                               folder on this Mac. Implied by --profile personal
                               and --profile student.
  --full-send                  Alias for --bypass-permissions. Same effect,
                               a name you can remember at the end of a pasted
                               curl line.

Behaviors, both off unless asked for:
  --session-opener <name>      Opens every response with a line you choose.
                               Shipped: prayer, gratitude. Default: none.
                               Add it later:
                                 ./setup.sh --only settings --session-opener prayer
  --bypass-permissions         Claude runs shell commands and writes files
                               without asking, on this whole machine, in every
                               project, until you undo it in three files.
                               Default: off, so Claude asks.

Re-running:
  --only <section>             Run one section. Safe to repeat.
                               prereq repos settings editor desktop mcp rules
                               plugins tools mac plynn verify
  --dry-run                    Print what would run and exit.
  -h, --help                   This text.
USAGE
}

NAME=""; GITHUB_USER=""; REPO_DIR=""; ANTHROPIC_KEY=""; GITHUB_PAT=""
TODOIST_TOKEN=""; COMPOSIO_URL=""; COMPOSIO_KEY=""; ANSWERS=""
SESSION_OPENER="none"; BYPASS_PERMS="no"; ONLY=""; DRY_RUN=0
PROFILE="developer"; NO_GITHUB=0; ONLY_PORTABLE=0
SKIP_SECTIONS=""
declare -a SKIPPED=()
# Only these reach settings.json, and only when passed here in this run.
declare -a CREDS_WRITTEN=()

while [ $# -gt 0 ]; do
  case "$1" in
    --name) NAME="${2:-}"; shift 2 ;;
    --github-user) GITHUB_USER="${2:-}"; shift 2 ;;
    --repo-dir) REPO_DIR="${2:-}"; shift 2 ;;
    --anthropic-key) ANTHROPIC_KEY="${2:-}"; shift 2 ;;
    --github-token) GITHUB_PAT="${2:-}"; shift 2 ;;
    --todoist-token) TODOIST_TOKEN="${2:-}"; shift 2 ;;
    --composio-url) COMPOSIO_URL="${2:-}"; shift 2 ;;
    --composio-key) COMPOSIO_KEY="${2:-}"; shift 2 ;;
    --answers) ANSWERS="${2:-}"; shift 2 ;;
    --session-opener) SESSION_OPENER="${2:-none}"; shift 2 ;;
    --bypass-permissions) BYPASS_PERMS="yes"; shift ;;
    --profile)
      PROFILE="${2:-developer}"
      case "$PROFILE" in
        personal|student|developer|portable) ;;
        *) err "unknown profile: $PROFILE"
           err "  one of: personal, student, developer, portable"
           exit 2 ;;
      esac
      # portable is the neutral half: standards, skills, commands, subagents.
      # No Homebrew, no Mac tools, no MCP, no permissions, no repos. It is the
      # only profile that works on a machine this kit does not otherwise run on,
      # and the only one that touches nothing outside ~/.claude.
      if [ "$PROFILE" = portable ]; then NO_GITHUB=1; ONLY_PORTABLE=1; fi
      shift 2 ;;
    --no-github) NO_GITHUB=1; shift ;;
    --full-send) BYPASS_PERMS="yes"; shift ;;
    --only) ONLY="${2:-}"; shift 2 ;;
    # --only ran one section and there was no way to run everything except
    # one. Repeatable: --skip plynn --skip mac.
    --skip) SKIP_SECTIONS="$SKIP_SECTIONS ${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) err "unknown argument: $1"; echo; usage; exit 2 ;;
  esac
done

# A profile is a set of defaults, not a separate code path. It decides what a
# section does rather than whether the script runs, so every section stays
# reachable with --only and the whole thing stays one file.
case "$PROFILE" in
  personal|student) NO_GITHUB=1 ;;
  portable) NO_GITHUB=1; ONLY_PORTABLE=1 ;;
  developer) ;;
  *) err "unknown profile: $PROFILE"
     err "  one of: personal, student, developer, portable"
     exit 2 ;;
esac

# The answers file fills anything a flag did not. Flags win, so a one-off
# override never means editing the file.
if [ -n "$ANSWERS" ]; then
  [ -f "$ANSWERS" ] || { err "answers file not found: $ANSWERS"; exit 2; }
  eval "$(python3 - "$ANSWERS" <<'PYEOF'
import json, shlex, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception as e:
    print(f'err "answers file is not valid JSON: {e}"; exit 2')
    raise SystemExit(0)
pairs = {
    "name": "NAME", "github_user": "GITHUB_USER", "repo_dir": "REPO_DIR",
    "anthropic_key": "ANTHROPIC_KEY", "github_token": "GITHUB_PAT",
    "todoist_token": "TODOIST_TOKEN", "composio_url": "COMPOSIO_URL",
    "composio_key": "COMPOSIO_KEY", "session_opener": "SESSION_OPENER",
}
for k, var in pairs.items():
    v = d.get(k)
    if v:
        print(f'[ -n "${{{var}:-}}" ] || {var}={shlex.quote(str(v))}')
if d.get("bypass_permissions") is True:
    print('BYPASS_PERMS=yes')
PYEOF
)"
fi

if [ -z "$NAME" ] && [ "${ONLY:-}" = "repos" ]; then
  err "--only repos still needs --name: it is what the repo is called"
  exit 2
fi

if [ -z "$NAME" ] && [ -z "$ONLY" ]; then
  err "--name is required (or --answers, or --only <section>)"
  echo
  usage
  exit 2
fi

USER_NAME="$(printf '%s' "$NAME" | tr -cd '[:alnum:] _-' | xargs)"
if [ -n "$USER_NAME" ]; then
  USER_NAME_LOWER=$(printf '%s' "$USER_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
  PERSONAL_REPO="${USER_NAME_LOWER}-context"
fi

WORKSPACE_DIR="${REPO_DIR:-$HOME/dev}"
WORKSPACE_DIR="${WORKSPACE_DIR/#\~/$HOME}"
case "$WORKSPACE_DIR" in /*) ;; *) WORKSPACE_DIR="$PWD/$WORKSPACE_DIR" ;; esac
# A dry run must not touch the disk. This mkdir ran before the dry-run branch,
# so `--dry-run --repo-dir /somewhere` created /somewhere and then printed that
# it would not do anything.
if [ "$DRY_RUN" -eq 0 ]; then
  mkdir -p "$WORKSPACE_DIR"
  WORKSPACE_DIR="$(cd "$WORKSPACE_DIR" && pwd)"
fi

# --only runs one section. Everything here is written to be safe to repeat, so
# a run that died halfway, or a tool that arrived after the first run, is one
# flag away rather than a hand-copied block from this file.
SECTIONS="prereq repos settings editor desktop mcp rules plugins tools plynn verify"
if [ -n "$ONLY" ]; then
  case " $SECTIONS " in
    *" $ONLY "*) ;;
    *) err "unknown section: $ONLY"; err "one of: $SECTIONS"; exit 2 ;;
  esac
fi
PORTABLE_SECTIONS=" settings rules manifest verify "
should_run() {
  case " $SKIP_SECTIONS " in
    *" $1 "*) SKIPPED+=("$1 (--skip)"); return 1 ;;
  esac
  if [ "$ONLY_PORTABLE" -eq 1 ]; then
    case "$PORTABLE_SECTIONS" in
      *" $1 "*) ;;
      *) SKIPPED+=("$1 (portable profile)"); return 1 ;;
    esac
  fi
  if [ -n "$ONLY" ] && [ "$ONLY" != "$1" ]; then
    SKIPPED+=("$1 (--only $ONLY)")
    return 1
  fi
  return 0
}

if [ "$DRY_RUN" -eq 1 ]; then
  echo "Would run: ${ONLY:-all sections}${SKIP_SECTIONS:+, skipping$SKIP_SECTIONS}"
  echo "  profile:         $PROFILE$([ "$ONLY_PORTABLE" -eq 1 ] && echo "  (~/.claude only, no Mac tools)")"
  echo "  github:          $([ "$NO_GITHUB" -eq 1 ] && echo "skipped, brain stays local" || echo "two repos created and pushed")"
  echo "  name:            ${USER_NAME:-<unset>}"
  echo "  repo dir:        $WORKSPACE_DIR"
  echo "  session opener:  $SESSION_OPENER"
  echo "  bypass perms:    $BYPASS_PERMS"
  for pair in "anthropic:$ANTHROPIC_KEY" "github:$GITHUB_PAT" "todoist:$TODOIST_TOKEN"; do
    [ -n "${pair#*:}" ] && echo "  credential:      ${pair%%:*} (would be written to settings.json)"
  done
  exit 0
fi

echo ""
sep
echo -e "  ${BLD}Chewbacca: Infrastructure Setup${NC}"
sep
echo ""

# ── Prerequisites ─────────────────────────────────────────────────────────────
if should_run prereq; then
section "Checking prerequisites"
MISSING=0

# Each of these used to print its own error and its own brew command, on a
# machine that might not have brew either. "Install: brew install gh" is a dead
# end for the person this kit is aimed at. bootstrap.sh installs the lot, and
# names the two steps that genuinely need a human.
# gh is only a prerequisite when we are going to talk to GitHub. Requiring the
# GitHub CLI from someone who does not have a GitHub account is the same
# blocker as requiring the account, one layer down.
REQUIRED="git:git python3:python3 jq:jq"
[ "$NO_GITHUB" -eq 0 ] && REQUIRED="gh:GitHub CLI $REQUIRED"
for pair in $REQUIRED; do
  cmd="${pair%%:*}"
  command -v "$cmd" &>/dev/null || { err "missing: ${pair##*:} ($cmd)"; MISSING=1; }
done
if ! command -v bun &>/dev/null && ! command -v node &>/dev/null; then
  err "missing: node or bun"
  MISSING=1
fi

if [ "$MISSING" -eq 1 ]; then
  echo ""
  echo "  Run this first. It installs all of them:"
  echo ""
  echo "      ./bin/bootstrap.sh"
  echo ""
  echo "  Or let Claude do it:  claude \"run the setup skill\""
  exit 1
fi

# Two hard exits used to live here, and together they were the reason someone
# with a Claude subscription and no GitHub account could not run this at all.
# Neither is needed unless we are actually going to create and push repos.
if [ "$NO_GITHUB" -eq 0 ] && ! gh auth status &>/dev/null; then
  err "Not signed in to GitHub. This needs a browser, so it cannot run from here:"
  err "  gh auth login"
  err "Then re-run. ./bin/bootstrap.sh checks this too."
  err ""
  err "Or skip GitHub. Your second brain becomes a folder on this Mac:"
  err "  ./setup.sh --profile personal --name <your name>"
  exit 1
fi

# gh auth login lets you decline git credential setup, and every remote this
# script writes is HTTPS. Without this, push blocks on a username prompt.
[ "$NO_GITHUB" -eq 0 ] && { gh auth setup-git &>/dev/null || true; }

# A clean macOS install has no git identity. Without one, every commit below
# fails with "Author identity unknown", both repos get created and pushed empty,
# and the sync hook then fails silently forever because it swallows the error.
# Catch it here where there is still someone at the keyboard to answer.
if [ "$NO_GITHUB" -eq 1 ]; then
  # Nothing gets pushed on this path, so a missing identity costs nothing. Set
  # a local one anyway if git is present, so the brain folder can still keep
  # history for the user without ever asking them what an email address is for.
  if command -v git &>/dev/null && [ -z "$(git config --global user.name 2>/dev/null)" ]; then
    log "No git identity set, and none needed: nothing here is pushed anywhere"
  fi
elif [ -z "$(git config --global user.name 2>/dev/null)" ] ||
  [ -z "$(git config --global user.email 2>/dev/null)" ]; then
  err "No global git identity is set. Every commit this script makes would fail."
  err "Set one, then re-run:"
  err "  git config --global user.name \"Your Name\""
  err "  git config --global user.email \"you@example.com\""
  err ""
  err "Or skip GitHub entirely:  ./setup.sh --profile personal --name <your name>"
  exit 1
else
  log "Git identity: $(git config --global user.name) <$(git config --global user.email)>"
fi

# A passed --github-user wins; the logged-in account is only the fallback.
GITHUB_USER="${GITHUB_USER:-$(gh api user --jq .login 2>/dev/null)}"
fi

# ── Collect info ──────────────────────────────────────────────────────────────
# Nothing to collect. Every value came in as a flag or from the answers file,
# and anything absent stays absent rather than being guessed at.
section "About you"
# `VAR="$(failing-cmd)"` as a standalone assignment exits under set -e. With
# --only settings the prereq check never runs, so an unauthenticated gh killed
# the script here with no output at all.
GITHUB_USER="${GITHUB_USER:-$(gh api user --jq .login 2>/dev/null || true)}"
log "Name: ${USER_NAME:-<unset>}"
log "GitHub: ${GITHUB_USER:-<unknown>}"
log "Repos: $WORKSPACE_DIR"

# ── Repo 1: {name}-context (private) ─────────────────────────────────────────
if should_run repos && [ -n "${USER_NAME:-}" ]; then
section "Creating $PERSONAL_REPO (private personal brain)"

PC_DIR="$WORKSPACE_DIR/$PERSONAL_REPO"
export D1_PC_DIR="$PC_DIR"
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
echo "  Claude reads YOU.md at the start of every session."
echo ""
# This used to launch $EDITOR, falling back to nano and then vi, and block until
# the file was closed. On a Mac with no EDITOR set that is vi, and someone who
# has never seen vi cannot get out of it. The install appeared to hang, in a
# text editor, with no instructions. Nothing here is worth that: Claude fills
# this file in by asking, which is the whole design of the kit anyway.
if [ "$PROFILE" = "developer" ] && [ -n "${EDITOR:-}" ] && command -v "${EDITOR%% *}" &>/dev/null; then
  log "Opening YOU.md in $EDITOR"
  $EDITOR "$PC_DIR/YOU.md" || true
else
  log "YOU.md is a template. Ask Claude to fill it in with you."
fi

if [ "$NO_GITHUB" -eq 1 ]; then
  log "Staying local: $PC_DIR is a folder on this Mac, not a repo"
elif gh repo view "$GITHUB_USER/$PERSONAL_REPO" &>/dev/null; then
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
if [ "$NO_GITHUB" -eq 0 ]; then
  git remote remove origin 2>/dev/null || true
  git remote add origin "https://github.com/$GITHUB_USER/$PERSONAL_REPO.git"
fi

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
# A commit needs an identity. On the no-GitHub path we may not have one, and
# asking for an email to make a local commit nobody will ever read is exactly
# the kind of question this profile exists to delete.
if [ -n "$(git config user.name 2>/dev/null)" ] || [ "$NO_GITHUB" -eq 0 ]; then
  git diff --cached --quiet || git commit -q -m "init: $USER_NAME personal context"
  git branch -M main
fi
if [ "$NO_GITHUB" -eq 1 ]; then
  log "$PC_DIR"
else
  git push -u origin main -q 2>/dev/null || warn "Push failed, you may need to push manually"
  log "https://github.com/$GITHUB_USER/$PERSONAL_REPO"
fi
fi

# Skipped without GitHub: this one exists only to be a public repo, so there is
# no local half of it worth writing.
# ── Repo 2: claude-context (public) ──────────────────────────────────────────
if should_run repos && [ -n "${USER_NAME:-}" ] && [ "$NO_GITHUB" -eq 0 ]; then
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
- \`.claude/rules/\`: 8 always-on standards imported by CLAUDE.md, plus 3 that load on demand
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
fi

# ── iMessage agent ────────────────────────────────────────────────────────────
if should_run repos && [ -n "${USER_NAME:-}" ]; then
# Not bundled. This used to clone calebnewtonusc/imessage-agent, which does not
# exist, so every user who said yes got a warning and nothing else. The pattern
# is documented in second-brain/agents/imessage.md if you want to build one;
# setup.sh will not pretend to install it.
IMSG_DIR=""
SETUP_IMESSAGE=0
fi

# ── Wire ~/.claude/settings.json ─────────────────────────────────────────────
if should_run settings; then
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

# The display: hud draws interfaces on top of everything on screen, hud-listen
# turns what is said to it into a drawing, hud-context reports what is in front
# of the person. All three go in together because hud calls the other two by
# path, so installing one of them alone gives a command that fails halfway.
_installed_hud=""
for _tool in hud hud-listen hud-context hud-watch; do
  if [ -f "$SCRIPT_DIR/bin/$_tool" ]; then
    mkdir -p "$HOME/.local/bin"
    cp "$SCRIPT_DIR/bin/$_tool" "$HOME/.local/bin/$_tool"
    chmod +x "$HOME/.local/bin/$_tool"
    _installed_hud="$_installed_hud $_tool"
  fi
done
if [ -n "$_installed_hud" ]; then
  log "Installed to ~/.local/bin/:$_installed_hud"
  # The commands are useless without the app that draws. Say so once, here,
  # rather than letting the first `hud draw` fail with a socket error.
  if [ ! -d "/Applications/BobHUD.app" ] && [ ! -d "$HOME/Applications/BobHUD.app" ]; then
    warn "BobHUD.app is not installed, so hud has nothing to draw on."
    warn "Build it: git clone https://github.com/calebnewtonusc/bob-the-builder && cd bob-the-builder/hud && ./scripts/bundle.sh"
  fi
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) warn "~/.local/bin is not on your PATH. Add it to run$_installed_hud by name." ;;
  esac
fi
unset _tool _installed_hud

# coursework reads a semester ledger built from your syllabi: what is due, what
# an absence costs, what each course allows you to use AI for. Deterministic, so
# Claude spends its tokens on judgment instead of re-reading a PDF.
# kits finds every kit on this machine by its .kit marker, so a session knows
# what has already been built instead of rebuilding it or answering turn by turn.
if [ -f "$SCRIPT_DIR/bin/kits" ]; then
  mkdir -p "$HOME/.local/bin"
  cp "$SCRIPT_DIR/bin/kits" "$HOME/.local/bin/kits"
  chmod +x "$HOME/.local/bin/kits"
  log "kits installed to ~/.local/bin/"
fi

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

# people keeps what you know about the people in your life: notes, circles, and
# who you are drifting out of touch with. One SQLite file on this machine, no
# account and no network. Needs node 22.5+ for the built-in sqlite module.
if [ -f "$SCRIPT_DIR/bin/people" ]; then
  mkdir -p "$HOME/.local/bin"
  cp "$SCRIPT_DIR/bin/people" "$HOME/.local/bin/people"
  chmod +x "$HOME/.local/bin/people"
  PEOPLE_HOME="${PEOPLE_DIR:-$HOME/.chewbacca/people}"
  mkdir -p "$PEOPLE_HOME"
  if node -e "require('node:sqlite')" >/dev/null 2>&1; then
    log "people installed to ~/.local/bin/, data at $PEOPLE_HOME"
    echo "    Next: people import --mac to pull in your contacts."
  else
    warn "people installed, but this node has no node:sqlite (needs 22.5+)."
    echo "    Fix with: brew upgrade node"
  fi
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

# ── What this run turns on ────────────────────────────────────────────────────
# Both of these used to be on with no way to say no, announced in a wall of
# text after they had already been written. Each is a flag now, each defaults
# to off, and this prints the state it is actually about to write.
echo ""
echo "  This run will configure:"
if [ "$SESSION_OPENER" = "none" ]; then
  echo "    Session opener     off"
else
  echo "    Session opener     $SESSION_OPENER, on every response"
fi
if [ "$BYPASS_PERMS" = "yes" ]; then
  echo "    Permission prompts OFF. Claude runs shell commands and writes files"
  echo "                       without asking, in every project on this machine."
  echo "                       Undoing it means editing three files."
else
  echo "    Permission prompts on. Claude asks before acting."
fi
CRED_COUNT=0
for v in "$ANTHROPIC_KEY" "$GITHUB_PAT" "$TODOIST_TOKEN"; do
  [ -n "$v" ] && CRED_COUNT=$((CRED_COUNT + 1))
done
if [ "$CRED_COUNT" -gt 0 ]; then
  echo "    Credentials        $CRED_COUNT written to ~/.claude/settings.json in plain text"
else
  echo "    Credentials        none. Nothing is read from your shell or keychain."
fi
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
export D1_SESSION_OPENER="$SESSION_OPENER"
export D1_BYPASS_PERMS="$BYPASS_PERMS"

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

# Only what was passed to this run. Nothing is read from the ambient shell,
# the keychain, or `gh auth token`. A value already exported under one of these
# names used to survive an empty prompt and land here as though it were typed.
settings.setdefault("env", {})
for key, var in (("GITHUB_TOKEN", "D1_GITHUB_PAT"),
                 ("ANTHROPIC_API_KEY", "D1_ANTHROPIC_KEY"),
                 ("TODOIST_API_TOKEN", "D1_TODOIST_TOKEN")):
    val = env(var, "").strip()
    if val:
        settings["env"][key] = val
        print(f"Wrote credential to settings.json: env.{key}")

perms = settings.setdefault("permissions", {})
# Off unless --bypass-permissions was passed. Turning it on removes the step
# where Claude asks before running a shell command or writing a file, on the
# whole machine, in every project, and it takes three separate files to undo.
# That is not something an installer should decide on someone's behalf.
if env("D1_BYPASS_PERMS", "no") == "yes":
    perms["defaultMode"] = "bypassPermissions"
    print("Permission prompts disabled: Claude will not ask before acting.")
else:
    perms.setdefault("defaultMode", "default")

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

# Session opener: off unless --session-opener names one. This used to be wired
# unconditionally, so a stranger running the installer got every reply opening
# with a prayer and found out from two lines in a wall of setup output. That is
# the author's own practice, not a default anyone else agreed to.
# A vague instruction here produces a vague line every time. "Begin with a
# prayer" gets you the same sentence forever; naming what makes it real is
# what makes the model write a different one each turn.
OPENERS = {
    "prayer": (
        "MANDATORY FIRST ACTION: The very first text you write in this "
        "response must be a prayer to Jesus Christ. Not after a preamble, not "
        "after a tool call. The prayer IS the first sentence. Make it specific "
        "to what is actually being worked on right now, speak warmly and "
        "directly rather than in formal religious register, vary the phrasing "
        "every time, and end with Amen. Then answer."
    ),
    "gratitude": (
        "MANDATORY FIRST ACTION: Open every response with one sentence naming "
        "something specific to be grateful for in what is being worked on "
        "right now. Concrete, never generic, never the same twice. Then answer."
    ),
}
opener = env("D1_SESSION_OPENER", "none").strip().lower()
if opener in ("", "none", "no", "off"):
    h.pop("UserPromptSubmit", None)
elif opener in OPENERS:
    opener_payload = json.dumps({"hookSpecificOutput": {
        "hookEventName": "UserPromptSubmit",
        "additionalContext": OPENERS[opener],
    }})
    h["UserPromptSubmit"] = [{"hooks": [{
        "type": "command",
        "command": "printf '%s' " + shlex.quote(opener_payload),
        "statusMessage": "Session opener",
    }]}]
    print(f"Session opener enabled: {opener}")
else:
    print(f"Unknown session opener {opener!r}, leaving it off. "
          f"Known: {', '.join(sorted(OPENERS))}")

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
}]}, {"hooks": [{
    # The writing rules live in CLAUDE.md, which is a user message competing
    # with everything else in a long session. By hour three the drama beats
    # come back. This reads what Claude actually wrote and refuses the turn,
    # deterministically and with no model call, so the rule cannot decay.
    "type": "command",
    "command": hooks_dir + "/slop-guard.sh",
    "timeout": 15,
    "statusMessage": "Checking the reply against the writing rules...",
}]}]

# Coursework context loads when a prompt mentions a class, so the ledger is in
# context before Claude answers rather than after it guesses.
h.setdefault("UserPromptSubmit", []).append({"hooks": [{
    "type": "command",
    "command": hooks_dir + "/coursework-context.sh",
    "timeout": 10,
}]})

# A kit already built is worth nothing if the next session answers the question
# in a chat window instead. This matches the prompt against every kit's
# use-when line and says nothing at all unless there is a real match.
h.setdefault("UserPromptSubmit", []).append({"hooks": [{
    "type": "command",
    "command": hooks_dir + "/kit-route.sh",
    "timeout": 10,
}]})

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

# Your commits are yours. Claude Code appends a Co-Authored-By trailer and a
# "Generated with Claude Code" line to pull requests by default, and stripping
# those out of a history later means rewriting every commit and force-pushing.
# Turn it off before the first commit instead of after the hundredth.
settings["includeCoAuthoredBy"] = False

# Auto-memory writes into the private context repo instead of a directory
# nobody ever reads. Without this key Claude's own learnings land somewhere
# outside the brain and never get committed with the rest of it.
_pc = env("D1_PC_DIR") or ""
if _pc:
    settings["autoMemoryDirectory"] = os.path.join(_pc, "memory")

# One status line: model, directory, branch, context used, session cost.
settings["statusLine"] = {"type": "command", "command": hooks_dir + "/statusline.sh"}

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
fi
log "~/.claude/settings.json configured"


# ── Wire the editor extension ─────────────────────────────────────────────────
if should_run editor; then
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

# The editor is the second of the three places permission prompts get turned
# off. Without --bypass-permissions, drop those two keys and keep the rest of
# the template, which is ordinary editor configuration.
if os.environ.get("D1_BYPASS_PERMS") != "yes":
    for k in ("claudeCode.allowDangerouslySkipPermissions",
              "claudeCode.initialPermissionMode"):
        desired.pop(k, None)
    print("  Permission prompts left on in the editor extension.")

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
fi

# ── Wire the Claude desktop app ───────────────────────────────────────────────
if should_run desktop; then
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
#
# Only written when --bypass-permissions was passed. This was the third of
# three files that turned off the safety net, and the one nobody would think
# to look in.
if os.environ.get("D1_BYPASS_PERMS") != "yes":
    print("  Permission prompts left on in the desktop app.")
    raise SystemExit(0)
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
fi

# ── Wire .mcp.json ────────────────────────────────────────────────────────────
if should_run mcp; then
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

# Two servers that need no account, no key, and no running service, so they can
# be wired unconditionally. setdefault, so an existing entry is never clobbered.
# Everything else is left to the user: ~/.claude.json is where client hostnames
# and API keys live.
mcp["mcpServers"].setdefault("filesystem", {
    "command": "npx",
    "args": ["-y", "@modelcontextprotocol/server-filesystem", os.path.expanduser("~")],
})
mcp["mcpServers"].setdefault("sequential-thinking", {
    "command": "npx",
    "args": ["-y", "@modelcontextprotocol/server-sequential-thinking"],
})

# Blender only when Blender is actually installed. Registering it otherwise
# gives a server that fails every call, which reads as a broken kit.
if os.path.isdir("/Applications/Blender.app"):
    mcp["mcpServers"].setdefault("blender", {"command": "uvx", "args": ["blender-mcp"]})

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
fi

# ── Install D1 rules globally ─────────────────────────────────────────────────
if should_run rules; then
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
# Which standards file lands here decides what every future session costs and
# what it optimizes for. The developer one mandates Next.js, Tailwind, shadcn,
# a design system and a deploy checklist, on every prompt including the ones
# about someone's calendar. That is the right file for people who write code
# and the wrong file for everyone else.
case "$PROFILE" in
  personal|student) STANDARDS="$SCRIPT_DIR/CLAUDE-PERSONAL.md" ;;
  *)                STANDARDS="$SCRIPT_DIR/CLAUDE.md" ;;
esac
# Merge, do not clobber. Anyone who already had a CLAUDE.md lost it here, with
# no backup and no warning. The logic lives in its own file so it can be tested;
# it could not be, buried in a 1,700-line installer.
MERGE_RESULT="$(bash "$SCRIPT_DIR/bin/lib/merge-claude-md.sh" "$GLOBAL_CLAUDE/CLAUDE.md" "$STANDARDS" 2>/dev/null || echo failed)"
case "$MERGE_RESULT" in
  merged) warn "You already had a CLAUDE.md. It is kept below the standards, and"
          warn "  the original is backed up next to it as CLAUDE.md.yours-*" ;;
  updated) log "Standards region updated, your own additions left alone" ;;
  failed) warn "Could not write ~/.claude/CLAUDE.md" ;;
esac
# doctor.sh reads this. Without it, it checks for the coursework ledger and the
# GitHub repos that a personal install deliberately never creates, and reports
# their absence as warnings on a perfectly healthy machine.
echo "$PROFILE" > "$GLOBAL_CLAUDE/.chewbacca-profile"

log "Commands installed to ~/.claude/commands/ ($(ls "$SCRIPT_DIR"/.claude/commands/*.md | wc -l | tr -d ' ') files)"
log "Rules installed to ~/.claude/rules/ ($(ls "$SCRIPT_DIR"/.claude/rules/*.md | wc -l | tr -d ' ') files)"
log "Subagents installed to ~/.claude/agents/ ($(ls "$SCRIPT_DIR"/.claude/agents/*.md | wc -l | tr -d ' ') agents)"
log "CLAUDE.md installed to ~/.claude/CLAUDE.md ($(basename "$STANDARDS"))"
fi

# ── Skills and plugins ────────────────────────────────────────────────────────
if should_run plugins; then
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

# A missing claude CLI used to drop every plugin with one warning. The
# installer already needs node, so install the CLI rather than skip the
# largest single piece of what this kit is.
if ! command -v claude &>/dev/null && command -v npm &>/dev/null; then
  log "claude CLI not found, installing it"
  npm install -g @anthropic-ai/claude-code &>/dev/null \
    && log "claude CLI installed" \
    || warn "could not install the claude CLI: npm install -g @anthropic-ai/claude-code"
fi

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
    claude-md-management@claude-plugins-official \
    context7@claude-plugins-official \
    expo@claude-plugins-official \
    feature-dev@claude-plugins-official \
    frontend-design@claude-plugins-official \
    hookify@claude-plugins-official \
    humanizer@humanizer \
    pinecone@claude-plugins-official \
    playwright@claude-plugins-official \
    pyright-lsp@claude-plugins-official \
    railway@claude-plugins-official \
    security-guidance@claude-plugins-official \
    serena@claude-plugins-official \
    session-report@claude-plugins-official \
    typescript-lsp@claude-plugins-official \
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
  warn "claude CLI still missing. Plugins skipped: install node, then re-run"
  warn "  ./setup.sh --only plugins"
fi

# MCP servers, curated from mcpmarket.com. See docs/EXTENSIONS.md.
#
# Two tiers on purpose. The keyless ones are installed outright. The ones
# needing an account are installed only when their variables are already
# exported, because `claude mcp add` will happily register a server that
# fails on every call, and a broken tool in the list is worse than a
# missing one: the agent keeps reaching for it.
if command -v claude &>/dev/null; then
  mcp_present() { claude mcp list 2>/dev/null | grep -q "^$1:"; }

  while IFS='|' read -r M_NAME M_CMD M_ARGS; do
    [ -n "$M_NAME" ] || continue
    if mcp_present "$M_NAME"; then
      log "$M_NAME already registered"
      continue
    fi
    # shellcheck disable=SC2086  # M_ARGS is a deliberate argument list
    if claude mcp add "$M_NAME" --scope user -- "$M_CMD" $M_ARGS &>/dev/null; then
      log "$M_NAME registered"
    else
      warn "could not register $M_NAME"
    fi
  done <<'KEYLESS_MCP'
fetch|uvx|mcp-server-fetch
time|uvx|mcp-server-time
git|uvx|mcp-server-git
sequential-thinking|npx|-y @modelcontextprotocol/server-sequential-thinking
chart|npx|-y @antv/mcp-server-chart
macos-automator|npx|-y @steipete/macos-automator-mcp@latest
KEYLESS_MCP

  while IFS='|' read -r M_NAME M_CMD M_ARGS M_ENV; do
    [ -n "$M_NAME" ] || continue
    if mcp_present "$M_NAME"; then
      log "$M_NAME already registered"
      continue
    fi
    M_FLAGS=""; M_MISSING=""
    for M_VAR in $M_ENV; do
      M_VAL="$(eval "printf %s \"\${$M_VAR:-}\"")"
      if [ -n "$M_VAL" ]; then
        M_FLAGS="$M_FLAGS --env $M_VAR=$M_VAL"
      else
        M_MISSING="$M_MISSING $M_VAR"
      fi
    done
    if [ -n "$M_MISSING" ]; then
      warn "$M_NAME skipped, needs:$M_MISSING"
      continue
    fi
    # shellcheck disable=SC2086  # both are deliberate argument lists
    if claude mcp add "$M_NAME" --scope user $M_FLAGS -- "$M_CMD" $M_ARGS &>/dev/null; then
      log "$M_NAME registered"
    else
      warn "could not register $M_NAME"
    fi
  done <<'KEYED_MCP'
exa|npx|-y exa-mcp-server|EXA_API_KEY
tavily|npx|-y tavily-mcp|TAVILY_API_KEY
firecrawl|npx|-y firecrawl-mcp|FIRECRAWL_API_KEY
elevenlabs|uvx|elevenlabs-mcp|ELEVENLABS_API_KEY
browserbase|npx|-y @browserbasehq/mcp|BROWSERBASE_API_KEY BROWSERBASE_PROJECT_ID
magic|npx|-y @21st-dev/magic|TWENTY_FIRST_API_KEY
KEYED_MCP

  log "MCP servers done. Anything skipped: export its key and re-run"
  log "  ./setup.sh --only plugins"
fi
# END GENERATED: extensions
fi

# ── macOS tools ───────────────────────────────────────────────────────────────
if should_run tools; then
# Screen control, Google Workspace, summarization, clipboard history, and the
# agent-scripts skill pack. Everything here is optional: a failure warns and the
# install continues.
section "Installing macOS tools"

# BEGIN GENERATED: cli
# Kit-owned helpers that sit in front of the installed tools.
#   peekaboo: forces local execution, see docs/MACOS-TOOLS.md
#   chrome-js: reads and clicks a Chrome tab through JavaScript
mkdir -p "$HOME/.local/bin"
for HELPER in peekaboo chrome-js slop-check; do
  if [ -f "$SCRIPT_DIR/bin/$HELPER" ]; then
    cp "$SCRIPT_DIR/bin/$HELPER" "$HOME/.local/bin/$HELPER"
    chmod +x "$HOME/.local/bin/$HELPER"
    log "$HELPER installed to ~/.local/bin/"
  fi
done

# macOS command-line tools. Skipped without Homebrew, and skipped one by
# one if already present, so this is safe to re-run.
if command -v brew &>/dev/null; then
  if command -v Anki &>/dev/null; then
    log "Anki already installed"
  else
    brew install --cask anki &>/dev/null && log "Anki installed" || warn "could not install Anki"
  fi
  if [ -d "/Applications/Maccy.app" ]; then
    log "Maccy already installed"
  else
    brew install --cask maccy &>/dev/null && log "Maccy installed" || warn "could not install Maccy"
  fi
  if [ -x /opt/homebrew/bin/peekaboo ]; then
    log "peekaboo already installed"
  else
    brew install steipete/tap/peekaboo &>/dev/null && log "peekaboo installed" || warn "could not install peekaboo"
  fi
  if command -v summarize &>/dev/null; then
    log "summarize already installed"
  else
    brew install steipete/tap/summarize &>/dev/null && log "summarize installed" || warn "could not install summarize"
  fi
else
  warn "Homebrew not found. macOS tools skipped: see docs/MACOS-TOOLS.md"
fi

# peekaboo speaks MCP too. Registered at user scope so it is available in
# every project, not just this one.
if ! command -v claude &>/dev/null; then
  warn "claude CLI missing, so the peekaboo MCP server was not registered"
elif command -v peekaboo &>/dev/null; then
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
PACK_SKIP="codex-first frontend-design"
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
fi

# Full control of the Mac, absorbed from calebnewtonusc/Nova. peekaboo and
# mac-use were already here and are two of the seven layers this knows about.
# This is the other five, plus the runtime that plans, executes, verifies and
# logs a multi-step task instead of improvising bash through it.
# ── Mac control ───────────────────────────────────────────────────────────────
if should_run mac; then
section "Installing Mac control"

MAC_SRC="$SCRIPT_DIR/mac"
if [ ! -d "$MAC_SRC" ]; then
  warn "mac/ not found in this checkout, skipping"
else
  mkdir -p "$HOME/.local/bin"
  ln -sf "$MAC_SRC/bin/chewie" "$HOME/.local/bin/chewie"
  chmod +x "$MAC_SRC/bin/chewie" 2>/dev/null || true
  log "chewie installed to ~/.local/bin/chewie"

  # Layer 3 is the accessibility-tree driver and it is the one worth having.
  # Everything below degrades to a screenshot without it.
  if command -v npm &>/dev/null; then
    if command -v agent-desktop &>/dev/null; then
      log "agent-desktop already installed"
    elif npm install -g agent-desktop &>/dev/null; then
      log "agent-desktop installed (accessibility driver)"
    else
      warn "could not install agent-desktop: npm install -g agent-desktop"
    fi
    # Layer 6, the Chrome DevTools bridge. Only when it has not been built yet.
    if [ -d "$MAC_SRC/bridge" ] && [ ! -d "$MAC_SRC/bridge/node_modules" ]; then
      (cd "$MAC_SRC/bridge" && npm install --silent &>/dev/null) \
        && log "web bridge ready" || warn "web bridge deps failed, nova web will not work"
    fi
  else
    warn "npm missing, so the accessibility driver and web bridge are skipped"
  fi

  if command -v claude &>/dev/null; then
    if claude mcp list 2>/dev/null | grep -q "^macos-automator:"; then
      log "macos-automator already registered"
    elif claude mcp add --scope user macos-automator \
      -- npx -y @steipete/macos-automator-mcp@latest &>/dev/null; then
      log "macos-automator registered (AppleScript and JXA over MCP)"
    else
      warn "could not register macos-automator"
    fi
  fi

  # Accessibility and Screen Recording cannot be granted by any script. tccutil
  # can remove a grant and never add one, and only an MDM profile can pre-grant.
  # So this is a real handoff, not a checklist to feel bad about.
  warn "Two toggles need a human, once: System Settings > Privacy & Security >"
  warn "  Accessibility, and Screen Recording. Add whichever app runs Claude."
  warn "  Run 'chewie doctor' and it names the exact app and what is still missing."
fi
fi

# ── Plynn ─────────────────────────────────────────────────────────────────────
if should_run plynn; then
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
fi

# ── Verify ────────────────────────────────────────────────────────────────────
if should_run verify; then
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
fi

# ── Manifest ──────────────────────────────────────────────────────────────────
if should_run manifest; then
# Nothing recorded what setup did, so uninstall was guessing and nobody could
# answer "what version is on this machine". Both are one file.
section "Recording what this install did"

STATE_DIR="$HOME/.chewbacca"
mkdir -p "$STATE_DIR"
cp "$SCRIPT_DIR/VERSION" "$STATE_DIR/version" 2>/dev/null || echo "unknown" > "$STATE_DIR/version"

MANIFEST="$STATE_DIR/install-manifest.json"
python3 - "$MANIFEST" "$GLOBAL_CLAUDE" "$SCRIPT_DIR" "$PROFILE" <<'PYEOF'
import json, os, subprocess, sys
from datetime import datetime, timezone
manifest, claude_dir, repo, profile = sys.argv[1:5]

def listing(sub, pattern=""):
    d = os.path.join(claude_dir, sub)
    if not os.path.isdir(d):
        return []
    out = []
    for name in sorted(os.listdir(d)):
        p = os.path.join(d, name)
        out.append({
            "name": name,
            "path": p,
            "symlink": os.path.islink(p),
            "target": os.readlink(p) if os.path.islink(p) else None,
        })
    return out

def commit():
    try:
        return subprocess.run(["git", "-C", repo, "rev-parse", "HEAD"],
                              capture_output=True, text=True).stdout.strip()
    except OSError:
        return ""

bins = []
local_bin = os.path.expanduser("~/.local/bin")
if os.path.isdir(local_bin):
    for name in sorted(os.listdir(local_bin)):
        p = os.path.join(local_bin, name)
        if os.path.islink(p) and repo in os.path.realpath(p):
            bins.append({"name": name, "path": p, "target": os.path.realpath(p)})

data = {
    "installed": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    "version": open(os.path.join(repo, "VERSION")).read().strip()
               if os.path.isfile(os.path.join(repo, "VERSION")) else "unknown",
    "commit": commit(),
    "repo": repo,
    "profile": profile,
    "host": os.uname().nodename,
    "wrote": {
        "skills": listing("skills"),
        "commands": listing("commands"),
        "rules": listing("rules"),
        "hooks": listing("hooks"),
        "agents": listing("agents"),
        "output-styles": listing("output-styles"),
        "bin": bins,
    },
    "note": "Written by setup.sh. uninstall.sh removes exactly what is listed here.",
}
with open(manifest, "w") as f:
    json.dump(data, f, indent=2)
counts = {k: len(v) for k, v in data["wrote"].items()}
print("  manifest: " + ", ".join(f"{v} {k}" for k, v in counts.items() if v))
PYEOF
log "install manifest written to $MANIFEST"
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
sep
echo -e "  ${BLD}${GRN}Setup complete.${NC}"
sep
echo ""
if [ "${#SKIPPED[@]}" -gt 0 ]; then
  echo -e "  ${BLD}Not run this time:${NC}"
  for s in "${SKIPPED[@]}"; do echo "    $s"; done
  echo -e "  ${YLW}Run them later with:${NC} chewbacca setup --only <section>"
  echo ""
fi
# What someone should read at the end depends entirely on who they are. Two
# repo URLs that do not exist and three slash commands are the wrong closing
# screen for a person who came here to ask about their calendar.
if [ "$NO_GITHUB" -eq 1 ]; then
  echo -e "  ${BLD}Your second brain:${NC}"
  echo "    ${PC_DIR:-$WORKSPACE_DIR}"
  echo "    A folder on this Mac. Claude reads it and writes to it as you talk."
  echo ""
  echo -e "  ${BLD}Claude can now:${NC}"
  echo "    read your calendar and contacts, send a text, see your screen,"
  echo "    summarize a video or article, and remember what matters to you"
  echo ""
  echo -e "  ${BLD}Try asking it:${NC}"
  echo "    \"what's on my calendar tomorrow\""
  echo "    \"text someone that I'm running late\""
else
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
fi
echo ""
sep
echo ""

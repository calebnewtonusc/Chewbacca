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

# A sandboxed HOME must not reach the real agent config.
#
# Tests run this with HOME pointed at a temp directory. A second Claude
# account is run with CLAUDE_CONFIG_DIR=~/.claude-2, and a test started from
# that session inherited it: every `claude` call here then used the real
# account's config while macOS looked for a keychain under the fake HOME,
# which is the "A keychain cannot be found" dialogue that kept appearing
# (2026-09-22), and tools/agent_context.py wrote a temp brain path into the
# real CLAUDE.md. The config dir follows HOME whenever HOME is not the
# account's own.
if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
  _real_home="$(eval echo "~$(id -un)")"
  if [ "$HOME" != "$_real_home" ]; then
    case "$CLAUDE_CONFIG_DIR" in
      "$HOME"/*) ;;
      *) export CLAUDE_CONFIG_DIR="$HOME/.claude" ;;
    esac
  fi
  unset _real_home
fi

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
  --runtime <name>             Install only the selected runtime adapter:
                               claude-code, codex, both, or auto. No Mac bootstrap.
                               Use --dry-run to preview; use agent export for other hosts.
  --brain-dir <path>           With --runtime, choose the private context folder.
  --json                      With --runtime, print machine-readable results.
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
  --fast                       Install only what makes the agent know you:
                               settings, rules, skills, subagents. Skips brew
                               packages, plugins, MCP servers and dictation.
                               Takes about two minutes instead of thirty. Run
                               `chewbacca setup` later for the rest.
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
                               plugins tools agents mac plynn verify
  --dry-run                    Print what would run and exit.
  -h, --help                   This text.
USAGE
}

NAME=""; GITHUB_USER=""; REPO_DIR=""; ANTHROPIC_KEY=""; GITHUB_PAT=""
TODOIST_TOKEN=""; COMPOSIO_URL=""; COMPOSIO_KEY=""; ANSWERS=""
SESSION_OPENER="none"; BYPASS_PERMS="no"; ONLY=""; DRY_RUN=0
PROFILE="developer"; NO_GITHUB=0; ONLY_PORTABLE=0
FAST=0
AGENT_RUNTIME=""
AGENT_BRAIN=""; AGENT_JSON=0
SKIP_SECTIONS=""
declare -a SKIPPED=()
# Only these reach settings.json, and only when passed here in this run.
declare -a CREDS_WRITTEN=()
REQUESTED_ARGS=("$@")

while [ $# -gt 0 ]; do
  case "$1" in
    --name) NAME="${2:-}"; shift 2 ;;
    --runtime) AGENT_RUNTIME="${2:-}"; shift 2 ;;
    --brain-dir) AGENT_BRAIN="${2:-}"; shift 2 ;;
    --json) AGENT_JSON=1; shift ;;
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
      # and configures both agent homes without installing Mac tools.
      if [ "$PROFILE" = portable ]; then NO_GITHUB=1; ONLY_PORTABLE=1; fi
      shift 2 ;;
    --no-github) NO_GITHUB=1; shift ;;
    --full-send) BYPASS_PERMS="yes"; shift ;;
    --only) ONLY="${2:-}"; shift 2 ;;
    # --only ran one section and there was no way to run everything except
    # one. Repeatable: --skip plynn --skip mac.
    --skip) SKIP_SECTIONS="$SKIP_SECTIONS ${2:-}"; shift 2 ;;
    # The whole install is a few gigabytes of Homebrew formulae, nineteen Claude
    # plugins and twelve MCP servers, and it ran past thirty minutes in testing
    # on 2026-09-19. That is fine for the person who lives in this kit and
    # useless in a twenty minute call, where the thing being shown is ingestion
    # and nothing else. --fast installs the part that makes the agent know you:
    # settings, rules, skills, subagents. Everything else is one later command.
    --fast|--minimal)
      SKIP_SECTIONS="$SKIP_SECTIONS editor desktop mcp plugins tools plynn"
      FAST=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) err "unknown argument: $1"; echo; usage; exit 2 ;;
  esac
done

# Runtime setup is independent of the historical Mac/Claude bootstrap. A fresh
# Codex install must not need Claude credentials, Homebrew or a GitHub account.
if [ -n "$AGENT_RUNTIME" ]; then
  for ((arg_index=0; arg_index<${#REQUESTED_ARGS[@]}; arg_index++)); do
    case "${REQUESTED_ARGS[$arg_index]}" in
      --runtime|--name|--brain-dir) arg_index=$((arg_index + 1)) ;;
      --dry-run|--json) ;;
      *) err "Runtime setup does not accept ${REQUESTED_ARGS[$arg_index]}; use the full installer or native host settings for that option."
         exit 2 ;;
    esac
  done
  action=setup
  [ "$DRY_RUN" -eq 1 ] && action=plan
  runtime_args=("$action" --runtime "$AGENT_RUNTIME")
  [ -n "$NAME" ] && runtime_args+=(--name "$NAME")
  [ -n "$AGENT_BRAIN" ] && runtime_args+=(--brain-dir "$AGENT_BRAIN")
  [ "$AGENT_JSON" -eq 1 ] && runtime_args+=(--json)
  exec python3 "$SCRIPT_DIR/tools/agent_runtime.py" "${runtime_args[@]}"
fi
if [ -n "$AGENT_BRAIN" ] || [ "$AGENT_JSON" -eq 1 ]; then
  err "--brain-dir and --json require --runtime"
  exit 2
fi

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

# A RE-INSTALL HAS ALREADY ANSWERED THESE QUESTIONS.
#
# `chewbacca update` pulls and then runs this file with no arguments, which hit
# the --name guard below and exited 2. Every time, on every machine. So update
# fast-forwarded new hooks, skills, commands and tools and then installed none
# of them, and the only symptom was an exit code in a command nobody reads the
# tail of. Found 2026-09-22 while making pull-and-push the default, which is
# exactly the thing that made it matter: pulling code you never install is
# worse than not pulling, because now the repo and the machine disagree and
# every surface reports the new version.
#
# --name exists to name the personal context repo, which only the `repos`
# section creates. On a machine that already has an install manifest that repo
# exists, so the section has nothing left to do and its one input is not
# needed. Skip it and let the rest of the install proceed.
REINSTALL=0
if [ -z "$NAME" ] && [ -z "$ONLY" ] && [ -z "$ANSWERS" ] && \
   [ -f "$HOME/.chewbacca/install-manifest.json" ]; then
  REINSTALL=1
  SKIP_SECTIONS="$SKIP_SECTIONS repos"
fi

if [ -z "$NAME" ] && [ -z "$ONLY" ] && [ "$NO_GITHUB" -eq 0 ] && [ "$REINSTALL" -eq 0 ]; then
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
if [ "$DRY_RUN" -eq 0 ] && [ "$ONLY" != agents ]; then
  mkdir -p "$WORKSPACE_DIR"
  WORKSPACE_DIR="$(cd "$WORKSPACE_DIR" && pwd)"
fi

# --only runs one section. Everything here is written to be safe to repeat, so
# a run that died halfway, or a tool that arrived after the first run, is one
# flag away rather than a hand-copied block from this file.
# PLYNN IS OUT OF THE DEFAULT INSTALL, 2026-09-21.
#
# Dictation moved into the HUD, which draws its own pill. Plynn kept running as
# a separate app drawing the legacy indicator, so two overlapping systems were
# live at once and the one people saw was the retired one: "Secure field,
# dictation paused", from PlynnKit/IndicatorView.swift.
#
# The source stays in plynn/ and the installer still works if asked for by
# name, because the parts worth folding into the HUD are listed in
# plynn/SALVAGE.md. It just no longer installs and auto-starts behind a second
# indicator nobody asked for.
#
#     ./setup.sh --only plynn     still installs it
SECTIONS="prereq repos settings editor desktop mcp rules skills plugins tools agents verify manifest"
if [ -n "$ONLY" ]; then
  case " $SECTIONS " in
    *" $ONLY "*) ;;
    *) err "unknown section: $ONLY"; err "one of: $SECTIONS"; exit 2 ;;
  esac
fi
PORTABLE_SECTIONS=" settings rules skills agents manifest verify "
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

initialize_personal_context() {
  # Modern second brains already own their layout. Flat templates are additive.
  [ -d "$PC_DIR/core" ] && return 0
  mkdir -p "$PC_DIR/memory"
  local context_file
  for context_file in YOU NOW PEOPLE VOICE SYSTEM STACK SCHOOL; do
    if [ ! -e "$PC_DIR/$context_file.md" ]; then
      cp "$SCRIPT_DIR/second-brain/context/$context_file.md" "$PC_DIR/$context_file.md"
      if [ "$context_file" = YOU ] && [ -n "$USER_NAME" ]; then
        sedi "s/YOUR_NAME/$USER_NAME/g" "$PC_DIR/YOU.md"
        sedi "s/YOUR_GITHUB_USERNAME/${GITHUB_USER:-}/g" "$PC_DIR/YOU.md"
      fi
    fi
  done
  if [ ! -e "$PC_DIR/memory/MEMORY.md" ]; then
    printf '# Memory index\n\nAdd links to shared personal memory here as it is recorded.\n' > "$PC_DIR/memory/MEMORY.md"
  fi
}

# Telling somebody their PATH is wrong, at the end of an install, is handing
# them a chore. start.sh already writes this line into their shell; setup.sh
# run on its own did not, so it warned twice about something it could have
# fixed in three lines. Do the edit, then say what it did.
ensure_local_bin_on_path() {
  local rc added=0
  case ":$PATH:" in *":$HOME/.local/bin:"*) return 0 ;; esac
  for rc in "$HOME/.zshrc" "$HOME/.bash_profile" "$HOME/.profile"; do
    [ -f "$rc" ] || continue
    grep -q '.local/bin' "$rc" 2>/dev/null && continue
    printf '\n# Added by Chewbacca\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$rc"
    added=1
  done
  export PATH="$HOME/.local/bin:$PATH"
  [ "$added" -eq 1 ] && log "Added ~/.local/bin to your PATH. New terminals pick it up automatically."
  return 0
}

# A Terminal.app started from inside a Claude Code session hands its
# environment to every window it opens afterwards, and the login shell keeps
# it. On 2026-09-20 the voice agent, itself carrying a session's variables,
# ran `open -a Terminal -n` twice (21:34, 23:22); each started a second
# Terminal.app instance, and the `claude` opened in one of them at 00:47 drew
# a block under every word (FORCE_COLOR=3 is 24-bit colour Terminal.app cannot
# parse) and saved no transcript (CLAUDE_CODE_CHILD_SESSION=1).
#
# The block is rewritten rather than appended when it is already there, so a
# machine that took an earlier version of this guard gets the current one.
TERMINAL_GUARD_MARK="# Added by Chewbacca: a window is not a Claude Code child session"
TERMINAL_GUARD_END="# End of the Chewbacca terminal guard"
write_terminal_guard() {
  cat <<'GUARD'

# Added by Chewbacca: a window is not a Claude Code child session
# A Terminal.app opened from inside a Claude Code session hands that session's
# environment to every window it opens. Two halves, because the two kinds of
# variable are wrong for different reasons.
#
# The session marker, for a shell a person opened. A shell whose parent is
# login is one of those. Claude's own tool shells have claude as a parent and
# keep theirs, because CLAUDE_CODE_MESSAGING_SOCKET is how their tools reach
# the session they belong to.
if [ "$(ps -o comm= -p "$PPID" 2>/dev/null)" = "login" ]; then
  unset CLAUDECODE
  for _chewbacca_var in $(env | sed -n 's/^\(CLAUDE_CODE_[A-Za-z0-9_]*\)=.*/\1/p'); do
    unset "$_chewbacca_var"
  done
  unset _chewbacca_var
fi
# The colour, for every shell in Terminal.app. Terminal.app declares
# xterm-256color and its terminfo carries no 24-bit entry, so FORCE_COLOR=3 or
# COLORTERM=truecolor in one of its windows was inherited and is always wrong:
# Claude Code writes 24-bit escapes the terminal cannot parse and leaves a
# block behind every word. This half is not gated on the parent, because a
# nested shell, a tmux pane, and a window opened before this guard existed all
# have the same broken colour and a different parent.
if [ "${TERM_PROGRAM:-}" = "Apple_Terminal" ]; then
  unset FORCE_COLOR COLORTERM CLICOLOR_FORCE
fi
# End of the Chewbacca terminal guard
GUARD
}
ensure_terminal_shell_guard() {
  # Strip any previous copy, then write the current one. Rewriting rather than
  # skipping is what upgrades a machine that took an earlier version.
  local rc had tmp
  for rc in "$HOME/.zshrc" "$HOME/.bash_profile"; do
    [ -f "$rc" ] || continue
    had=0
    if grep -qF "$TERMINAL_GUARD_MARK" "$rc" 2>/dev/null; then
      had=1
      tmp="$(mktemp)" || return 0
      awk -v s="$TERMINAL_GUARD_MARK" -v e="$TERMINAL_GUARD_END" \
        'index($0,s){f=1; next} f{ if (index($0,e)) f=0; next } {print}' "$rc" > "$tmp"
      cat "$tmp" > "$rc"
      rm -f "$tmp"
    fi
    write_terminal_guard >> "$rc"
    if [ "$had" -eq 1 ]; then
      log "Refreshed the terminal guard in $(basename "$rc")."
    else
      log "Added the terminal guard to $(basename "$rc"): a window opened by a Claude session no longer inherits its colour and session variables."
    fi
  done
  return 0
}

link_tool() {
  local name="$1" src="$SCRIPT_DIR/bin/$1" dst="$HOME/.local/bin/$1"
  [ -f "$src" ] || return 1
  mkdir -p "$HOME/.local/bin"
  # -n so that when dst is already a symlink to a DIRECTORY we replace it rather
  # than writing inside it; -f to replace an existing copy from an older setup.
  ln -sfn "$src" "$dst"
  chmod +x "$src"
}

install_backend_launchers() {
  local backend_tool
  for backend_tool in chatgpt-tab chatgpt-gateway mac-use chrome-js; do
    link_tool "$backend_tool"
  done
  log "Chewbacca backend launchers refreshed in ~/.local/bin"
}

# agent-neutral.md is written for the OTHER agent. Its own text says so: "The
# detailed standards live in .claude/rules/ and in the user's global
# instructions, both of which already load for the primary agent. Nothing here
# restates them." Claude was loading all 1,176 tokens of it in every session
# anyway, because a rule with no `paths:` frontmatter is always-on, and the
# source file has none on purpose: it is also the source for AGENTS.md, where
# Claude-specific frontmatter would be noise.
#
# So the scoping is added here, on the way into ~/.claude/rules, and the source
# stays agent-neutral. The rule now loads when the work is actually about
# another agent, and Codex's export is unchanged.
install_agent_neutral_rule() {
  local dst="$HOME/.claude/rules/agent-neutral.md"
  mkdir -p "$HOME/.claude/rules"
  {
    printf '%s\n' '---'
    printf '%s\n' 'paths:'
    printf '%s\n' '  - "**/AGENTS.md"'
    printf '%s\n' '  - "**/.codex/**"'
    printf '%s\n' '  - "**/*codex*"'
    printf '%s\n' '  - "**/instructions/agent-neutral.md"'
    printf '%s\n' '---'
    cat "$SCRIPT_DIR/instructions/agent-neutral.md"
  } > "$dst"
}

install_agent_instructions() {
  install_agent_neutral_rule
  python3 "$SCRIPT_DIR/tools/agents_md.py"
  initialize_personal_context
  python3 "$SCRIPT_DIR/tools/agent_runtime.py" setup --runtime both --brain-dir "$PC_DIR"
  if ! command -v jq >/dev/null 2>&1; then
    warn "jq is missing: context loading works, but shared file and reply checks require jq"
  fi
  if command -v codex >/dev/null 2>&1; then
    log "Codex installed; shared context and runtime configuration ready"
  else
    log "Codex absent (optional); configuration ready for installation"
  fi
}


if [ "$DRY_RUN" -eq 1 ]; then
  echo "Would run: ${ONLY:-all sections}${SKIP_SECTIONS:+, skipping$SKIP_SECTIONS}"
  echo "  profile:         $PROFILE$([ "$ONLY_PORTABLE" -eq 1 ] && echo "  (Claude and Codex configuration, no Mac tools)")"
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

if [ -n "${CHEWBACCA_BRAIN_DIR:-}" ]; then
  PC_DIR="$(python3 "$SCRIPT_DIR/tools/codex_context.py" path)"
elif [ -n "$USER_NAME" ]; then
  PC_DIR="$WORKSPACE_DIR/$PERSONAL_REPO"
else
  PC_DIR="$(python3 "$SCRIPT_DIR/tools/codex_context.py" path)"
fi

if [ "$ONLY" = agents ]; then
  if [ "$ONLY_PORTABLE" -eq 0 ]; then install_backend_launchers; fi
  install_agent_instructions
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
[ "$NO_GITHUB" -eq 0 ] && REQUIRED="gh:GitHub-CLI $REQUIRED"
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
#
# `VAR="$(failing-cmd)"` as a standalone assignment exits under set -e, and
# `gh api user` exits 4 on a machine where gh is installed but nobody has
# signed in, which is every machine running the personal profile. The whole
# install died right here, silently, with no error and exit 4, after printing
# one line about git identity. The same mistake was already found and fixed
# thirteen lines below this one; this copy was missed.
#
# NO_GITHUB means no repo is ever created, so there is nothing to look up.
if [ "$NO_GITHUB" -eq 0 ]; then
  GITHUB_USER="${GITHUB_USER:-$(gh api user --jq .login 2>/dev/null || true)}"
fi
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

export D1_PC_DIR="$PC_DIR"
initialize_personal_context

log "Templates copied to $PC_DIR"

echo ""
echo "  Claude and Codex read the same personal context at session start."
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

git add -- .gitignore YOU.md NOW.md PEOPLE.md VOICE.md SYSTEM.md STACK.md SCHOOL.md memory/MEMORY.md
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

# Symlink, never copy.
#
# On 2026-09-07 the installed `people` was a stale COPY of the repo's, three days
# behind it. `events` and `merge` existed in the repo and not on PATH, so the
# nightly scan was silently dead for three days while every surface reported a
# healthy install: `command -v people` said yes, and it was pointing at the wrong
# file. `cp` here is what produced that, and a `cp` in an installer is a promise
# to reproduce it on the next `chewbacca update`.
#
# A symlink makes the repo the only copy, so pulling the repo IS updating the
# tool. `tests/live/people.sh` asserts the link, so this cannot quietly regress.
# link_tool is defined above, before its first caller in the agents section.

# Both scanners score something with no model in the loop, so a cheap
# deterministic check can run before anything spends tokens. ai-scan reads prose
# for AI-writing tells; skill-scan reads skills for whether they will fire.
_installed_scanners=""
# prose-check is the third scanner and the one that knows Caleb's own list.
# ai-scan and skill-scan score generic AI-writing tells; on 2026-09-16 a draft
# passed both while carrying six kickers, three not-X-but-Y constructions and
# two announced turns, because neither knows what a kicker is. prose-check
# encodes voice.md and the fifteen 180DC corrections. Python, so no node needed.
#
# code-slop is the fourth, and the only one that reads CODE. The other three all
# score a README: vocabulary, structure, and the house list, every one of them
# over prose. Code has its own AI-authorship tells, a comment narrating the line
# below it or a section banner in a 40-line file, and nothing here looked for
# them until 2026-09-16. It pairs with the `deslop` skill, which holds the
# judgement calls.
# demo-shoot is a wrapper, not a scanner, but it installs the same way: a
# small executable in bin/ that needs to reach ~/.local/bin.
for _tool in ai-scan skill-scan prose-check code-slop demo-shoot craft-gate claude-tab; do
  if [ -f "$SCRIPT_DIR/bin/$_tool" ]; then
    link_tool "$_tool"
    _installed_scanners="$_installed_scanners $_tool"
  fi
done
# The crafts this kit has already studied. Seeded so the research happens once
# and every machine inherits it; craft-gate refuses to produce in a craft with
# no notes, so an empty store would block the demo tooling on a fresh install.
if [ -d "$SCRIPT_DIR/crafts" ]; then
  mkdir -p "$HOME/.chewbacca/craft"
  cp "$SCRIPT_DIR/crafts/"*.md "$HOME/.chewbacca/craft/" 2>/dev/null || true
  log "seeded $(ls "$SCRIPT_DIR/crafts" | wc -l | tr -d ' ') craft notes"
fi

# ux-engine lives in its own repo, so its tools cannot go through link_tool,
# which resolves against this repo's bin/. Link them when that repo is present,
# from the same default ux-guard.sh reads.
#
# WHY THIS MATTERS AND IS NOT COSMETIC. ux-guard blocks a UI write and then
# tells the agent what to do next: "Derive the constraints first: ux-constrain"
# and "load the behaviour spec: ux-preset form". Neither was on PATH, so the
# remediation was a dead end and the only move left after a refusal was to
# guess again. A gate that refuses without a runnable next step trains people
# to route around it.
UX_ENGINE_DIR="${UX_ENGINE_DIR:-$HOME/Desktop/2026-Code/ux-engine}"
if [ -d "$UX_ENGINE_DIR/bin" ]; then
  mkdir -p "$HOME/.local/bin"
  _ux_linked=""
  for _ux in "$UX_ENGINE_DIR/bin/"*; do
    [ -f "$_ux" ] || continue
    ln -sfn "$_ux" "$HOME/.local/bin/$(basename "$_ux")"
    chmod +x "$_ux"
    _ux_linked="$_ux_linked $(basename "$_ux")"
  done
  [ -n "$_ux_linked" ] && log "ux-engine tools linked to ~/.local/bin/:$_ux_linked"
  unset _ux _ux_linked
  ensure_local_bin_on_path
fi

if [ -n "$_installed_scanners" ]; then
  if command -v node &>/dev/null; then
    log "Installed to ~/.local/bin/:$_installed_scanners"
  else
    warn "Installed$_installed_scanners but node is missing, so they will not run until you install node >= 18"
  fi
  ensure_local_bin_on_path
fi
unset _tool _installed_scanners

# brief-audio renders text to a listenable MP3 with Kokoro-82M, locally. It is
# deliberately not in the scanner loop above: those need node, this needs python
# and ffmpeg, and warning about the wrong missing dependency sends people to fix
# something unrelated. It builds its own venv at ~/.chewbacca/audio-venv on first
# run, so nothing heavy is installed here.
if [ -f "$SCRIPT_DIR/bin/brief-audio" ]; then
  link_tool brief-audio
  log "brief-audio installed to ~/.local/bin/"
  ensure_local_bin_on_path
fi

# list-audit is pure stdlib python, no venv and no network, so it installs with
# no dependency check at all. list-gate ships with it: audit reads a bought file,
# gate refuses to ship a generated one, and the Stop hook calls the gate by name.
for _tool in list-audit list-gate kit-debt handoff-check learn durable-check corpus preflight gtme-graph gtme-math gtme-library gtme-learning clay-fixture-check review-gate task-graph graph-fuse work-ledger fanout site-fast untrusted-screen model-route intro list-sift ux-do; do
  if [ -f "$SCRIPT_DIR/bin/$_tool" ]; then
    link_tool "$_tool"
    log "$_tool installed to ~/.local/bin/"
  fi
done
ensure_local_bin_on_path
unset _tool

# The display: hud draws interfaces on top of everything on screen, hud-listen
# turns what is said to it into an answer, hud-context reports what is in front
# of the person, hud-speak reads the answer aloud. They go in together because
# hud calls the others by path, so installing one alone gives a command that
# fails halfway.
_installed_hud=""
for _tool in hud hud-listen hud-context hud-watch hud-speak hud-guide hud-music superassistant chewbacca-mcp portal; do
  if [ -f "$SCRIPT_DIR/bin/$_tool" ]; then
    link_tool "$_tool"
    _installed_hud="$_installed_hud $_tool"
  fi
done

# Register the MCP server with every client already on this machine, so the
# person never sees a port or pastes a URL. Caleb's reaction to the localhost
# transport was "that means someone would have to open a browser, that's
# terrible UX", and he was right: once is still once too many. Idempotent, and
# it backs up each config before touching it.
if [ -x "$HOME/.local/bin/chewbacca-mcp" ]; then
  "$HOME/.local/bin/chewbacca-mcp" --register 2>/dev/null | sed 's/^/    /'
fi
if [ -n "$_installed_hud" ]; then
  log "Installed to ~/.local/bin/:$_installed_hud"
  # The commands are useless without the app that draws. Say so once, here,
  # rather than letting the first `hud draw` fail with a socket error.
  # On 2026-09-21 Caleb had merged the presence field and could not see it.
  # His Mac had the `hud` commands on it and no app for them to draw on,
  # because this section linked the commands and then warned about the app in
  # two lines, in the middle of a setup that prints hundreds, and nothing he
  # could run afterwards would have told him. An install that ends in an
  # instruction has not installed anything.
  if [ ! -d "/Applications/Kyber.app" ] && [ ! -d "$HOME/Applications/Kyber.app" ]; then
    if command -v swift >/dev/null 2>&1 && [ -x "$SCRIPT_DIR/hud/scripts/bundle.sh" ]; then
      log "Building the display. About a minute, once."
      if (cd "$SCRIPT_DIR/hud" && ./scripts/bundle.sh release >/dev/null 2>&1); then
        _dest="/Applications"
        [ -w "$_dest" ] || { _dest="$HOME/Applications"; mkdir -p "$_dest"; }
        if cp -r "$SCRIPT_DIR/hud/build/Kyber.app" "$_dest/" 2>/dev/null; then
          log "Installed Kyber.app to $_dest/. Open it, or run: hud open"
        else
          warn "built the display but could not copy it into $_dest"
        fi
        unset _dest
      else
        warn "the display did not build. Run it by hand to see why:"
        warn "  cd $SCRIPT_DIR/hud && ./scripts/bundle.sh"
      fi
    else
      warn "no Swift toolchain here, so the display cannot be built."
      warn "  xcode-select --install, then: cd $SCRIPT_DIR/hud && ./scripts/bundle.sh"
    fi
  fi
  # The voice with nothing to install: hud-speak needs uv and espeak-ng,
  # hud-voice is one Swift binary. Built rather than shipped, like the app.
  if [ ! -x "$HOME/.local/bin/hud-voice" ]; then
    warn "hud-voice is not built; replies are read by hud-speak, which needs uv and espeak-ng."
    warn "Build it: $(dirname "$0")/voice/build.sh, then HUD_SPEAKER=hud-voice for hud-listen."
  fi
  ensure_local_bin_on_path
  ensure_terminal_shell_guard
fi
unset _tool _installed_hud

# coursework reads a semester ledger built from your syllabi: what is due, what
# an absence costs, what each course allows you to use AI for. Deterministic, so
# Claude spends its tokens on judgment instead of re-reading a PDF.
# kits finds every kit on this machine by its .kit marker, so a session knows
# what has already been built instead of rebuilding it or answering turn by turn.
if [ -f "$SCRIPT_DIR/bin/kits" ]; then
  link_tool kits
  log "kits installed to ~/.local/bin/"
fi

if [ -f "$SCRIPT_DIR/bin/coursework" ]; then
  link_tool coursework
  COURSEWORK_HOME="${COURSEWORK_DIR:-$HOME/coursework}"
  mkdir -p "$COURSEWORK_HOME/courses" "$COURSEWORK_HOME/syllabi" "$COURSEWORK_HOME/templates"
  cp "$SCRIPT_DIR/templates/coursework/"*.yml "$COURSEWORK_HOME/templates/" 2>/dev/null || true
  mkdir -p "$COURSEWORK_HOME/texts"
  # A course textbook is half a million words, so it is ingested once into
  # $COURSEWORK_HOME/texts and searched from there. See texts/README.md.
  [ -f "$SCRIPT_DIR/bin/textbook" ] && link_tool textbook
  log "coursework installed to ~/.local/bin/, ledger at $COURSEWORK_HOME"
  echo "    Next: run /syllabus on a syllabus PDF to fill the ledger."
fi

# people keeps what you know about the people in your life: notes, circles, and
# who you are drifting out of touch with. One SQLite file on this machine, no
# account and no network. Needs node 22.5+ for the built-in sqlite module.
if [ -f "$SCRIPT_DIR/bin/people" ]; then
  link_tool people
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

# guide builds interactive study guides that remember what was missed, so the
# next session opens on the three questions they got wrong instead of the top.
if link_tool guide; then
  log "guide installed to ~/.local/bin/"
fi

# Hooks read their paths from here instead of having them baked in by string
# substitution. Edit this file to move your context repos later.
cat > "$HOME/.claude/d1-config.sh" << D1CONFIG
# Written by Chewbacca setup.sh. Safe to edit by hand.
PERSONAL_CONTEXT_DIR="$PC_DIR"
PUBLIC_CONTEXT_DIR="$CC_DIR"
CONTEXT_OWNER="$USER_NAME"

# Where this kit's own checkout lives, so kit-autopush.sh can push fixes to it
# without anybody remembering to. It falls back to the repo path in
# ~/.chewbacca/install-manifest.json, so moving the checkout and re-running
# setup is enough; this line is the override for a second checkout.
CHEWBACCA_REPO_DIR="$SCRIPT_DIR"
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


def _register(event, command, timeout=None, matcher=None, status=None):
    """Register one hook for `event`, replacing any earlier copy of it.

    `matcher` limits a PreToolUse/PostToolUse hook to the tools it has an
    opinion about. Without it a gate runs on every tool call in the session and
    pays a process spawn each time to exit 0.

    The events this file assigns outright (`h[event] = [...]`) reset their
    list every run. The ones it adds to did not: `setdefault(...).append(...)`
    appended another copy on every re-run, and `chewbacca update` re-runs
    setup by design. Two PermissionRequest hooks then fire for one prompt,
    the one that loses the ask-file race records the prompt as not held, and
    a voice "yes" presses Return in a tab that is showing no dialog.

    Matched on the command's basename, so moving the hooks directory still
    replaces rather than duplicates.
    """
    name = os.path.basename(command)
    entries = h.setdefault(event, [])
    entries[:] = [
        e for e in entries
        if not any(os.path.basename(str(hook.get("command", ""))) == name
                   for hook in e.get("hooks", []))
    ]
    hook = {"type": "command", "command": command}
    if timeout is not None:
        hook["timeout"] = timeout
    if status is not None:
        hook["statusMessage"] = status
    entry = {"hooks": [hook]}
    if matcher is not None:
        entry["matcher"] = matcher
    entries.append(entry)

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

h["PostToolUse"] = [
    {"matcher": "Write|Edit", "hooks": [{
        "type": "command",
        "command": hooks_dir + "/format-and-sync.sh",
        "statusMessage": "Formatting and syncing...",
        "async": True,
    }]},
    # write-log records which session wrote which path. Both authorship
    # guards read ~/.chewbacca/write-log.tsv: .githooks/pre-commit refuses an
    # index holding two authors, and stop-check attributes dirty files.
    #
    # THIS WAS MISSING UNTIL 2026-09-21 AND BOTH GUARDS WERE INERT EVERYWHERE.
    # The kit's settings/settings.json registered it; this installer never did,
    # so ~/.chewbacca/write-log.tsv did not exist on the author's own machine
    # and pre-commit silently allowed every commit. Its own test covers that
    # state as "no write log: stays silent", so nothing failed and nothing said
    # anything. Three commits swallowed another session's work while the guard
    # meant to stop it had never run once.
    #
    # Matcher includes Bash and NotebookEdit because this kit tells agents to
    # edit through Bash heredocs and sed, so Write|Edit alone misses the
    # dominant write path. That was the first version's bug: it logged nothing.
    #
    # $HOME, not $CLAUDE_PROJECT_DIR. Two sessions can collide in any repo, not
    # only one that happens to ship this hook, and the other three hooks here
    # are already installed to $HOME.
    {"matcher": "Write|Edit|Bash|NotebookEdit", "hooks": [{
        "type": "command",
        "command": hooks_dir + "/write-log.sh",
    }]},
]

h["SessionStart"] = [{"hooks": [{
    "type": "command",
    "command": hooks_dir + "/session-context.sh",
    "statusMessage": "Loading your context...",
}]}]

h["Stop"] = [{"hooks": [{
    # Finished work sitting on the machine because nobody asked the right
    # question. This pushes commits to the user's OWN origin only, never to an
    # upstream fork, never auto-committing, and only from directories listed in
    # AUTOPUSH_DIRS. Off by default: the variable is empty until someone sets it.
    "type": "command",
    "command": hooks_dir + "/auto-push.sh",
    "timeout": 30,
    "statusMessage": "Pushing finished work...",
}]}, {"hooks": [{
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
}]}, {"hooks": [{
    # SendMessage returning success means a message was accepted, not that an
    # agent is alive. On 2026-09-23 a resume of a subagent from a dead session
    # returned {"success": true}, nothing started, and the reply went out
    # saying it was running. Caleb caught it; ListAgents then showed zero
    # subagents. This refuses a reply claiming background work is in flight
    # unless something in the turn actually launched or a listing shows it.
    "type": "command",
    "command": hooks_dir + "/agent-claim-guard.sh",
    "timeout": 15,
    "statusMessage": "Checking claims about running agents...",
}]}, {"hooks": [{
    # A claim of a verified state needs evidence in the session, not
    # confidence. On 2026-09-21 a fix was reported as done three times and the
    # next screenshot showed the same bug, and several more "fixed" claims were
    # made while the code path being described was not executing at all. This
    # refuses a reply saying something is fixed, verified or passing unless a
    # command RAN after the last file was written, and refuses "safe to close"
    # without a passing closeout receipt for the current commits.
    "type": "command",
    "command": hooks_dir + "/vibe-guard.sh",
    "timeout": 15,
    "statusMessage": "Checking claims of doneness against evidence...",
}]}, {"hooks": [{
    # A closing message that hands over a command is a confession of stopping
    # early. The shell was right there.
    "type": "command",
    "command": hooks_dir + "/handoff-guard.sh",
    "timeout": 15,
    "statusMessage": "Checking the reply does not hand you a command...",
}]}, {"hooks": [{
    # A correction that changes only the reply changes nothing. This checks
    # that being corrected actually moved something in the kit.
    "type": "command",
    "command": hooks_dir + "/durable-guard.sh",
    "timeout": 15,
    "statusMessage": "Checking a correction actually changed the kit...",
}]}, {"hooks": [{
    # An outbound list reported as finished, unread. On 2026-09-20 five
    # investor lists were called done four times running, and reading the
    # OUTPUT each time found what the code review had missed: 2,121 people on
    # more than one list, eleven partners at one fund, info@ mailboxes, and 843
    # rows whose company name was the literal string "Company". It was written
    # up as guidance in a skill and then never fired, which is the failure it
    # exists to prevent, and it was registered nowhere at all until now.
    "type": "command",
    "command": hooks_dir + "/list-guard.sh",
    "timeout": 20,
    "statusMessage": "Checking an outbound list was actually read...",
}]}]

# Coursework context loads when a prompt mentions a class, so the ledger is in
# context before Claude answers rather than after it guesses.
_register("UserPromptSubmit", hooks_dir + "/coursework-context.sh", timeout=10)

# A kit already built is worth nothing if the next session answers the question
# in a chat window instead. This matches the prompt against every kit's
# use-when line and says nothing at all unless there is a real match.
_register("UserPromptSubmit", hooks_dir + "/kit-route.sh", timeout=10)

h["PreToolUse"] = [{"matcher": "Write", "hooks": [{
    "type": "command",
    "command": hooks_dir + "/env-guard.sh",
    "statusMessage": "Checking file safety...",
}]}]

# Layer 6. A browser hands you an addressable model of its own contents, and
# reading it as an image throws that away. On 2026-09-21 a form the user had
# open in Chrome got filled by screenshots and pixel clicks, one field per round
# trip, while `chewie web` sat unused: the routing table named no command for a
# browser, so the agent fell back to the layer that had one. The table was fixed
# the same day, which is exactly why this exists as well. Any use of the bridge
# clears the gate for the session, and `visual:` in the command declares real
# canvas work and goes through.
_register("PreToolUse", hooks_dir + "/browser-ux-guard.sh", timeout=10,
          matcher="Bash|mcp__peekaboo__.*",
          status="Checking this browser work is not being done through pixels...")

# Stage 8 of graph-engineering, knowledge fusion, which the skill calls the #1
# cause of useless graphs and which this machine kept skipping. On 2026-09-21 a
# session wrote a paying client's name into the notes off a FIRST NAME match
# and got the wrong person. Refuses a write that introduces "First Last" where
# that first name is already on the roster under a different surname.
_register("PreToolUse", hooks_dir + "/fusion-guard.sh", timeout=15,
          matcher="Write|Edit|MultiEdit",
          status="Checking a name against the roster...")

# The generated look is an empty deny list, so this refuses a UI write that
# carries it. It blocks ONLY on findings that cite a standard this kit did not
# write (WCAG, W3C, MDN), because a build-breaking gate made of house opinion
# is roughly 3.4x over the false-positive rate where tools get switched off;
# everything else prints and lets the write through.
#
# It was copied to ~/.claude/hooks by the block above and never registered
# here, so it only ever fired on the one machine where it had been added to
# settings.json by hand. That is the same class as hud.listening and
# kit-route.sh: the capability was present, good, and wired to nothing.
# Six local Whisper jobs at once took Caleb's load average to 50 on 2026-09-22
# while he was working, and he found out before this kit did. Network-bound
# fan-out stays free; this refuses only CPU-bound local inference and transcode
# run three or more wide, or run at all while the machine is already loaded.
_register("PreToolUse", hooks_dir + "/load-guard.sh", timeout=10,
          matcher="Bash",
          status="Checking this will not take over the machine...")

_register("PreToolUse", hooks_dir + "/ux-guard.sh", timeout=15,
          matcher="Write|Edit",
          status="Checking this UI is not the generated look...")

# Coursework is never turned in without being asked. This was a rule in prose
# that got broken twice in one night, so it became a gate.
_register("PreToolUse", hooks_dir + "/submit-guard.sh", timeout=10,
          matcher="mcp__chrome-devtools__.*|Bash|mcp__peekaboo__.*",
          status="Checking this is not a coursework submission...")

# Say the ranking rule out loud before ranking, and name what would falsify
# the answer. Running someone's list top to bottom is not a method.
_register("UserPromptSubmit", hooks_dir + "/method-guard.sh", timeout=8,
          status="Naming the process and the falsifier...")

# FOUR HOOKS THAT WERE LIVE ON THE AUTHOR'S MACHINE AND REGISTERED NOWHERE.
#
# Found 2026-09-22 by diffing every .sh in .claude/hooks against every
# _register call, after ux-guard turned out to have the same hole. The cp above
# puts all of them on disk, so `command -v` and a file-exists check both say
# installed, and on any machine but the one where they were hand-added to
# settings.json they never ran once.
#
# skill-route is the expensive one. kit-route was fixed on 2026-09-21 after 105
# skills sat unnamed while work started; skill-route is the half that routes to
# the skills themselves and it still had no registration.
_register("UserPromptSubmit", hooks_dir + "/skill-route.sh", timeout=8,
          status="Checking whether a skill already covers this...")

# ux-engine holds 18 research files, six stances, a motion constant table, a
# 24-entry effects catalog and 106 psychology principles, and a whole session
# of UI work on 2026-09-23 consulted none of it: the page shipped at 3
# animations against a reference's 214 while its own linter returned clean,
# because the linter scores the absence of tells and nothing scored ambition.
# Caleb: "no point of research if it doesn't get implemented."
#
# Puts two things in front of design work and only two, because a wall of
# doctrine reads the same as none: the constants that get violated most, and
# the avoid list of features that have actually lost a blind comparison here.
# The second one is the part that compounds.
_register("UserPromptSubmit", hooks_dir + "/design-context.sh", timeout=8)

_register("UserPromptSubmit", hooks_dir + "/ask-capture.sh", timeout=5)

# Jev's read of the task class where claude-model-router-hook's keywords are
# unsure, in 0.3 s instead of that router's 8 s haiku fallback. Advice only.
_register("UserPromptSubmit", hooks_dir + "/model-route.sh", timeout=6)

_register("Stop", hooks_dir + "/kit-autopush.sh", timeout=30,
          status="Pushing the kit...")

# The global instructions say never WebFetch a YouTube URL, because it returns
# no transcript. This hook makes that automatic instead of something to
# remember, and it had never been registered on any machine at all.
_register("UserPromptSubmit", hooks_dir + "/youtube-transcript-ready.sh", timeout=8)

# The kit learns from the session or the session did not finish. Caleb asked
# four times on 2026-09-20 whether Chewbacca had been updated with what a
# session learned and then said "I shouldn't hv to keep asking this bruv", so
# this was built to stop him having to ask. bin/kit-debt was installed and
# tested; the hook that calls it was never registered, so the gate built to
# answer that complaint has not fired once.
_register("Stop", hooks_dir + "/kit-debt.sh", timeout=15,
          status="Checking the kit learned something...")

# The pull half. kit-autopush made the remote the default for work leaving this
# machine; nothing made it the default for work arriving. `chewbacca update`
# could always pull and always needed somebody to remember, which is the exact
# sentence kit-autopush was written to retire.
#
# Fast-forward only, main only, origin only, and it refuses outright on a dirty
# working tree, so it cannot cost uncommitted work. Throttled to once an hour.
_register("SessionStart", hooks_dir + "/kit-autopull.sh", timeout=20,
          status="Pulling the kit...")

# The prose rules apply to files too, not only to replies. A draft that passes
# every detector can still carry six kickers.
_register("PostToolUse", hooks_dir + "/prose-guard.sh", timeout=20,
          matcher="Write|Edit",
          status="Checking the prose against the writing rules...")

# The untrusted-content rule, checked instead of hoped for. A page, a text or a
# mail body that addresses the agent gets its excerpt put in front of the model
# with the rule attached. Warns, never blocks. See the hook for the tool list.
_register("PostToolUse", hooks_dir + "/untrusted-screen.sh", timeout=15,
          matcher="WebFetch|Bash|mcp__claude-in-chrome__.*|mcp__plugin_playwright_playwright__.*",
          status="Screening what was just read for instructions aimed at the agent...")

h["Notification"] = [{"hooks": [{
    "type": "command",
    "command": "say 'Claude Code task complete' 2>/dev/null || true",
    "async": True,
}]}]

# The terminal loop: hud-listen hears when the remembered Claude Code tab is
# waiting on a permission, answers it by voice, and says when a turn ends.
# One wrapper for six events. Every session gets one line in
# agent-events.jsonl for the agent board (bin/agents); only the remembered
# tab's events reach the voice, and only its prompts are held. 45 s: the hook holds a
# permission prompt for 30 s while the voice asks, and needs room above that.
for _event in ("PermissionRequest", "PreToolUse", "PostToolUse", "PermissionDenied", "Stop", "SessionEnd"):
    _register(_event, hooks_dir + "/terminal-loop.sh", timeout=45)

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
install_agent_neutral_rule
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
  personal|student) STANDARDS="$SCRIPT_DIR/docs/CLAUDE-PERSONAL.md" ;;
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

# Count what LANDED, not what was offered.
#
# Every cp above is `2>/dev/null || true`, so a failure is silent by
# construction. These lines used to count the SOURCE directory and report that
# as the install, which means a run where nothing copied still printed "Rules
# installed to ~/.claude/rules/ (12 files)". On this machine seven of the nine
# rules CLAUDE.md imports were absent while setup had reported success, so every
# session silently loaded two standards instead of nine.
installed_count() {
  local src="$1" dst="$2" label="$3"
  local want have
  want=$(ls "$src"/*.md 2>/dev/null | wc -l | tr -d ' ')
  have=$(ls "$dst"/*.md 2>/dev/null | wc -l | tr -d ' ')
  if [ "$have" -lt "$want" ]; then
    warn "$label: $have of $want landed in $dst"
    warn "  Check permissions on that directory, then re-run setup."
  else
    log "$label installed to $dst ($have files)"
  fi
}
installed_count "$SCRIPT_DIR/.claude/commands" "$GLOBAL_CLAUDE/commands" "Commands"
installed_count "$SCRIPT_DIR/.claude/rules"    "$GLOBAL_CLAUDE/rules"    "Rules"
installed_count "$SCRIPT_DIR/.claude/agents"   "$GLOBAL_CLAUDE/agents"   "Subagents"
log "CLAUDE.md installed to ~/.claude/CLAUDE.md ($(basename "$STANDARDS"))"
fi

# ── Shared agent context ─────────────────────────────────────────────────────
if should_run agents; then
if [ "$ONLY_PORTABLE" -eq 0 ]; then install_backend_launchers; fi
install_agent_instructions
fi

# ── Skills and plugins ────────────────────────────────────────────────────────
if should_run skills; then
section "Installing skills"

mkdir -p "$GLOBAL_CLAUDE/skills"
# Symlink each skill, and count what landed.
#
# This was `cp -R ... 2>/dev/null || true`, which produced two failures at once
# and reported neither. Copies froze at whatever existed when setup last ran, so
# a skill fixed in the repo stayed broken on disk; and skills added since the
# last run were simply absent. Seven of twenty-seven were missing on this
# machine, `people`, `texts`, `study-guide` and `stack-rules` among them, which
# is why sentences about those subjects loaded no skill: there was nothing to
# load. A skill that is not installed is not a skill with a bad description.
#
# Only this repo's own skills are touched. ~/.claude/skills holds many skills
# from elsewhere and nothing here may remove or overwrite one of those.
_skills_want=0; _skills_have=0
for _sk in "$SCRIPT_DIR"/skills/*/; do
  [ -d "$_sk" ] || continue
  _skn="$(basename "$_sk")"
  _skills_want=$((_skills_want + 1))
  _dst="$GLOBAL_CLAUDE/skills/$_skn"
  # A real directory here is a copy from an older setup, or someone else's skill
  # of the same name. Replace our own copies; never touch a foreign one.
  if [ -d "$_dst" ] && [ ! -L "$_dst" ] && [ ! -f "$_dst/.chewbacca" ] && [ -f "$_sk/SKILL.md" ]; then
    if cmp -s "$_dst/SKILL.md" "$_sk/SKILL.md" 2>/dev/null || grep -q "^name: $_skn$" "$_dst/SKILL.md" 2>/dev/null; then
      rm -rf "$_dst"
    else
      warn "skill '$_skn' already exists and is not ours, leaving it alone"
      continue
    fi
  fi
  ln -sfn "$_sk" "$_dst"
  [ -f "$_dst/SKILL.md" ] && _skills_have=$((_skills_have + 1))
done
if [ "$_skills_have" -lt "$_skills_want" ]; then
  warn "skills: $_skills_have of $_skills_want linked into $GLOBAL_CLAUDE/skills"
else
  log "Skills linked to ~/.claude/skills/ ($_skills_have)"
fi
unset _sk _skn _dst _skills_want _skills_have
log "Skills installed to ~/.claude/skills/"

fi

# Split out from the skills above on 2026-09-19. Skills are plain markdown and
# work on any machine any agent runs on, but they lived inside this section, so
# the portable profile, which is the only non-macOS path, installed 57 commands
# and 14 rules and zero skills. The largest single piece of the kit was missing
# from every Windows and Linux install.
#
# The comment goes above the header, not below it: a section header has to be
# immediately followed by `if should_run` or the guard closes early and the
# section runs on every invocation, including --only.
# ── Plugins and MCP ───────────────────────────────────────────────────────────
if should_run plugins; then

# Nothing this installs may open a window or a browser tab on somebody's
# machine without being asked. Serena's upstream default does exactly that, and
# it is why a browser window appeared on a tester's computer on 2026-09-19 and
# he concluded the kit was dangerous. The logic lives in its own file so it can
# be tested; it could not be, inside a shell function in a 2,000-line installer.
if [ -x "$SCRIPT_DIR/bin/lib/seed-serena-config.sh" ]; then
  if [ -n "$(bash "$SCRIPT_DIR/bin/lib/seed-serena-config.sh")" ]; then
    log "Serena dashboard disabled (it opens a browser tab by default)"
  fi
fi

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
cap|https://github.com/CapSoftware/Cap|installed by `cap agents install --target claude`|see upstream|CapSoftware
cap-demo|https://github.com/CapSoftware/Cap|installed by `cap agents install --target claude`|see upstream|CapSoftware
deslop|https://github.com/31Carlton7/skills|deslop|see upstream|31Carlton7
no-ai-slop|https://github.com/petergyang/no-ai-slop|skills/no-ai-slop|MIT|petergyang
youtube-transcripts|https://github.com/calebnewtonusc/claude-youtube-transcripts|skills/youtube-transcripts|MIT|calebnewtonusc
UPSTREAM_SKILLS

# INSTALL AN AGENT ONLY IF THEY HAVE NONE.
#
# This used to install Claude Code whenever `claude` was missing, full
# stop. On 2026-09-19 that put Sam, who runs Codex, in front of a
# Claude credits purchase during the install of a kit sold as model
# agnostic. He said so and stopped: "how is this model agnostic? i
# don't want to add claude credits." A second tester said the same. Neither has
# onboarded since. Installing a second paid subscription nobody asked
# for is not a missing-dependency fix, it is the product contradicting
# its own claim on the last screen.
#
# If any supported agent is already here, use it and install nothing.
# The plugins that genuinely need Claude warn on their own.
KIT_AGENT=""
for a in claude codex gemini; do
  if command -v "$a" &>/dev/null; then KIT_AGENT="$a"; break; fi
done

if [ -n "$KIT_AGENT" ]; then
  log "using the agent already installed: $KIT_AGENT"
elif command -v npm &>/dev/null; then
  log "no coding agent found, installing Claude Code (the free tier works)"
  npm install -g @anthropic-ai/claude-code &>/dev/null \
    && { KIT_AGENT="claude"; log "claude CLI installed"; } \
    || warn "could not install an agent: npm install -g @anthropic-ai/claude-code"
else
  warn "no coding agent and no npm. Install Claude Code, Codex or Gemini CLI first."
fi

# `command -v claude` only proves a binary is on PATH. It does not prove
# the CLI can do anything, and on a machine where it was npm-installed a
# minute ago and never signed in, every plugin install below fails. Two
# people testing this on 2026-09-19 watched nineteen consecutive red
# lines scroll past, which reads as a broken product rather than as one
# optional step being unavailable. Ask it one cheap question first.
PLUGINS_OK=0
if command -v claude &>/dev/null; then
  if claude plugin marketplace list </dev/null &>/dev/null; then
    PLUGINS_OK=1
  else
    warn "Claude Code is installed but not signed in yet, so plugins were skipped."
    warn "  Sign in by running: claude"
    warn "  Then install them with: chewbacca setup --only plugins"
  fi
fi

if [ "$PLUGINS_OK" -eq 1 ]; then
  for m in \
    Egonex-AI/Understand-Anything \
    anthropics/claude-plugins-official \
    blader/humanizer \
    clay-run/agent-plugins; do
    claude plugin marketplace add "$m" </dev/null &>/dev/null || true
  done
  log "Marketplaces registered"

  PLUGIN_FAILED=0
  for p in \
    bigquery-data-analytics@claude-plugins-official \
    claude-md-management@claude-plugins-official \
    clay@clay-plugins \
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
    swift-lsp@claude-plugins-official \
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
  log "Plugins needing OAuth (Vercel, Railway) stay inert until you run /mcp and authorize."
elif ! command -v claude &>/dev/null; then
  warn "claude CLI still missing. Plugins skipped: install node, then re-run"
  warn "  chewbacca setup --only plugins"
fi

# MCP servers, curated from mcpmarket.com. See docs/EXTENSIONS.md.
#
# Two tiers on purpose. The keyless ones are installed outright. The ones
# needing an account are installed only when their variables are already
# exported, because `claude mcp add` will happily register a server that
# fails on every call, and a broken tool in the list is worse than a
# missing one: the agent keeps reaching for it.
# Same probe as the plugins above: a signed-out CLI registers nothing
# and warns once per server.
if [ "$PLUGINS_OK" -eq 1 ]; then
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
    link_tool "$HELPER"
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
  if command -v bd &>/dev/null; then
    log "bd already installed"
  else
    brew install beads &>/dev/null && log "bd installed" || warn "could not install bd"
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

# cap: Screen recording with spring-physics zoom that follows your clicks, scriptable with --json on every command
if [ "$(uname -s)" != "Darwin" ]; then
  :
elif ! command -v brew &>/dev/null; then
  warn "Homebrew not found, skipping Cap"
else
  if [ -d /Applications/Cap.app ]; then
    log "Cap already installed"
  elif brew install --cask cap &>/dev/null; then
    log "Cap installed"
  else
    warn "could not install Cap"
  fi
  CAP_CLI=/Applications/Cap.app/Contents/MacOS/cap-cli
  if [ -x "$CAP_CLI" ]; then
    if command -v cap &>/dev/null; then
      log "cap shim already on PATH"
    elif "$CAP_CLI" desktop install-cli &>/dev/null; then
      log "cap shim installed to ~/.local/bin"
    else
      warn "could not install the cap shim"
    fi
    # skill, not all: `all` would also register the cloud-only MCP server
    # described above. This installs Cap's own routing skill plus the
    # cap-demo skill, both of which drive the local CLI.
    if [ -d "$HOME/.claude/skills/cap" ]; then
      log "Cap Claude integration already installed"
    elif "$CAP_CLI" agents install --target claude --component skill --yes &>/dev/null; then
      log "Cap skills and MCP registered for Claude"
    else
      warn "could not install the Cap Claude integration"
    fi
  fi
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
  warn "uv not found, skipping macOS-use. Install uv, then re-run:"
  warn "  ./setup.sh --only tools"
else
  MU_DIR="$HOME/Projects/macOS-use"
  [ -d "$MU_DIR/.git" ] || git clone -q --depth 1 \
    https://github.com/browser-use/macOS-use.git "$MU_DIR" 2>/dev/null || true
  if [ -d "$MU_DIR" ]; then
    # macOS-use supplies the runtime and the venv; Chewbacca owns the
    # provider adapters and reads them out of its own bin/ via the
    # resolved symlink. The two copies that used to land in $MU_DIR were
    # writes into somebody else's checkout that nothing ever read, and
    # they overwrote any local work there. link_tool, not cp: bin/mac-use
    # walks its own symlink back to find the adapters, so a plain copy
    # points it at the wrong tree.
    link_tool mac-use
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

# yt-transcript: Transcript of any YouTube video, channel, or playlist, read without asking
if command -v yt-transcript &>/dev/null; then
  log "yt-transcript already installed"
else
  YT_DIR="$(mktemp -d)"
  if git clone -q --depth 1 https://github.com/calebnewtonusc/claude-youtube-transcripts \
      "$YT_DIR" 2>/dev/null && [ -x "$YT_DIR/install.sh" ]; then
    if (cd "$YT_DIR" && ./install.sh &>/dev/null); then
      log "yt-transcript installed"
    else
      warn "youtube-transcripts installer failed. Run it by hand: $YT_DIR/install.sh"
    fi
  else
    warn "could not clone claude-youtube-transcripts"
  fi
  rm -rf "$YT_DIR"
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

# Skill pack: gtm-engineer-skills. Linked per skill, not copied, so `git pull` in
# the clone updates every skill at once.
#
# Sent by Caleb 2026-09-23. MIT. Its scripts read SERPAPI_KEY from the
# environment when set, and fetch only Google autocomplete, SerpAPI and
# the site being audited.
PACK_DIR="$HOME/Projects/gtm-engineer-skills"
PACK_SKIP=""
if [ -d "$PACK_DIR/.git" ]; then
  log "gtm-engineer-skills already cloned, left alone"
elif git clone -q --depth 1 "https://github.com/onvoyage-ai/gtm-engineer-skills.git" "$PACK_DIR" 2>/dev/null; then
  log "gtm-engineer-skills cloned"
else
  warn "could not clone gtm-engineer-skills"
fi
if [ -d "$PACK_DIR/." ]; then
  PACK_N=0
  for SK in "$PACK_DIR"/./*/; do
    SK_NAME="$(basename "$SK")"
    [ -f "$SK/SKILL.md" ] || continue
    case " $PACK_SKIP " in *" $SK_NAME "*) continue;; esac
    [ -e "$GLOBAL_CLAUDE/skills/$SK_NAME" ] && continue
    ln -s "$SK" "$GLOBAL_CLAUDE/skills/$SK_NAME"
    PACK_N=$((PACK_N+1))
  done
  log "gtm-engineer-skills: $PACK_N skills linked"
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

  # site-fast: browser-use's jev-ultrafast agent, one Jev call per step. It
  # lives outside the repo because it pins its own Python environment.
  SITE_FAST_HOME="${SITE_FAST_HOME:-$HOME/dev/jev-ultrafast}"
  if command -v uv &>/dev/null; then
    if [ ! -d "$SITE_FAST_HOME/.git" ]; then
      git clone --quiet https://github.com/browser-use/jev-ultrafast "$SITE_FAST_HOME" \
        || warn "could not clone jev-ultrafast, so site-fast will not run"
    fi
    [ -d "$SITE_FAST_HOME/.git" ] && (cd "$SITE_FAST_HOME" && uv sync --quiet &>/dev/null) \
      && log "site-fast ready (jev-ultrafast in $SITE_FAST_HOME)"
  else
    warn "uv missing, so site-fast is skipped"
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
  elif [ "$FAST" -eq 1 ] || [ "$ONLY_PORTABLE" -eq 1 ] || [ -n "$SKIP_SECTIONS" ]; then
    # An install that left whole sections out on purpose is supposed to fail
    # the checks for those sections. Ending a successful install on "some
    # checks failed" tells the person their new tool is broken when it is
    # doing exactly what they asked, which is the single worst sentence to end
    # an install on. Portable skips nearly everything by design and hit this
    # too.
    log "Checks for the sections this install skipped did not pass, as expected."
    log "  Install the rest with: chewbacca setup"
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

# How to undo this, said before anyone has to ask.
#
# Not a `# ── ─` section header: this is part of the closing summary and
# runs with it. check_sections.py reads that header style as a new section
# needing a should_run guard, and on 2026-09-21 this block was written with
# one and failed the suite.
#
# THE FAILURE THIS EXISTS FOR, 2026-09-20. Sam installed the kit, a browser
# tab kept reopening, and he wrote: "this seems extremely dangerous to have on
# my computer. i don't even know how to remove this agent", then "seems like
# malware". The same afternoon, without having seen that, someone else said
# "make it clear it's not anything suspicious with the permissions stuff".
#
# Neither was a missing capability. uninstall.sh already existed, the manifest
# already recorded every path it wrote, and the dashboard popping the tab was
# fixed hours later. What was missing was saying any of it HERE, on the last
# screen a new person reads, at the moment they decide whether to trust this.
#
# The screen above this one lists what Claude can now read: the calendar, the
# contacts, the screen. Ending there, with no way back, is what reads as
# malware to a careful person, and a careful person is exactly the one worth
# keeping.
echo ""
echo -e "  ${BLD}If you want it gone:${NC}"
echo "    chewbacca uninstall --dry-run   lists every path, changes nothing"
echo "    chewbacca uninstall             removes exactly that list"
echo ""
echo "    Every path this wrote is recorded in"
echo "    ~/.chewbacca/install-manifest.json, so removal reads that file"
echo "    instead of guessing."
echo ""
# Say what actually leaves the Mac, not what sounds reassuring. An earlier
# draft of this block said "this installer sends nothing anywhere", which is
# false: the GitHub path below creates two repos and pushes to them.
echo -e "  ${BLD}What leaves this Mac:${NC}"
echo "    Your prompts go to Anthropic, the same as any Claude Code session."
if [ "$NO_GITHUB" -eq 1 ]; then
  echo "    Your second brain is a folder on this disk. Nothing here pushes it."
else
  echo "    Your second brain is pushed to two repos on your own GitHub account"
  echo "    ($GITHUB_USER), created above. Nowhere else."
fi
echo "    Nothing is encrypted at rest. Treat it like any folder on your Mac."
echo ""
sep
echo ""

#!/bin/bash
# Chewbacca: verify the install actually works.
#
# Every bug this kit shipped in its first six months failed silently. The 18
# rules files installed and were never loaded by anything. Prettier could not
# find node and exited 0. The sync hook swallowed its own git errors. None of
# it announced itself; you just got worse output and never knew why.
#
# So this asserts. Run it after setup.sh, and any time Claude starts behaving
# like it forgot the standards.
#
#   ./doctor.sh          check everything
#   ./doctor.sh --quiet  only print failures
#
# Exits non-zero if any check fails.

set -uo pipefail

GRN='\033[0;32m'; RED='\033[0;31m'; YLW='\033[1;33m'; BLD='\033[1m'; NC='\033[0m'
QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1

PASS=0; FAIL=0; WARN=0

ok()   { PASS=$((PASS+1)); [ "$QUIET" -eq 1 ] || echo -e "  ${GRN}pass${NC}  $1"; }
bad()  { FAIL=$((FAIL+1)); echo -e "  ${RED}FAIL${NC}  $1"; [ -n "${2:-}" ] && echo -e "        ${YLW}fix:${NC} $2"; }
warn() { WARN=$((WARN+1)); [ "$QUIET" -eq 1 ] || echo -e "  ${YLW}warn${NC}  $1"; }
section() { [ "$QUIET" -eq 1 ] || echo -e "\n${BLD}$1${NC}"; }

CLAUDE_DIR="$HOME/.claude"

# ── Toolchain ─────────────────────────────────────────────────────────────────
section "Toolchain"

command -v git >/dev/null 2>&1 &&
  ok "git present" ||
  bad "git missing" "xcode-select --install"

if [ -n "$(git config --global user.name 2>/dev/null)" ] &&
  [ -n "$(git config --global user.email 2>/dev/null)" ]; then
  ok "git identity: $(git config --global user.name)"
else
  bad "no global git identity, every commit will fail" \
    "git config --global user.name 'You'; git config --global user.email 'you@example.com'"
fi

command -v gh >/dev/null 2>&1 && ok "gh present" || bad "gh missing" "brew install gh"
gh auth status >/dev/null 2>&1 && ok "gh authenticated" || bad "gh not authenticated" "gh auth login"
command -v jq >/dev/null 2>&1 && ok "jq present (hooks parse their input with it)" || bad "jq missing, every hook will no-op" "brew install jq"

# ── The node-on-PATH trap ─────────────────────────────────────────────────────
section "Formatting"

# Hooks do not inherit an nvm-managed PATH. Testing with `env -i` reproduces the
# environment a hook actually gets, which is where prettier used to die quietly.
if env -i HOME="$HOME" PATH="/usr/bin:/bin" bash -c 'command -v node' >/dev/null 2>&1; then
  ok "node reachable from a bare hook environment"
elif [ -x "$CLAUDE_DIR/hooks/format-and-sync.sh" ]; then
  ok "node not on the default PATH, but format-and-sync.sh resolves it itself"
else
  warn "node is not on a bare PATH and the resolving hook is not installed"
fi

if [ -f "$CLAUDE_DIR/hooks/format-and-sync.sh" ]; then
  TMPF="$(mktemp -d)/probe.json"
  printf '{"a":1,   "b":[1,2 ,3]}' > "$TMPF"
  echo "{\"tool_input\":{\"file_path\":\"$TMPF\"}}" | "$CLAUDE_DIR/hooks/format-and-sync.sh" >/dev/null 2>&1
  if grep -q '"a": 1' "$TMPF" 2>/dev/null; then
    ok "format hook actually formats a file"
  else
    bad "format hook ran but changed nothing" "check that prettier is installed: npm i -g prettier"
  fi
  rm -rf "$(dirname "$TMPF")"
else
  warn "format-and-sync.sh not installed"
fi

# ── Settings and hooks ────────────────────────────────────────────────────────
section "Settings and hooks"

if [ -f "$CLAUDE_DIR/settings.json" ]; then
  if python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$CLAUDE_DIR/settings.json" 2>/dev/null; then
    ok "settings.json is valid JSON"
  else
    bad "settings.json is not valid JSON, Claude Code will ignore all of it" \
      "python3 -m json.tool ~/.claude/settings.json"
  fi
else
  bad "no ~/.claude/settings.json" "run setup.sh"
fi

for h in session-context format-and-sync stop-check env-guard; do
  f="$CLAUDE_DIR/hooks/$h.sh"
  if [ ! -f "$f" ]; then
    bad "hook missing: $h.sh" "run setup.sh, or copy .claude/hooks/ to ~/.claude/hooks/"
  elif [ ! -x "$f" ]; then
    bad "hook not executable: $h.sh" "chmod +x $f"
  else
    ok "hook installed: $h.sh"
  fi
done

# A hook that emits malformed JSON is worse than one that emits nothing.
if [ -x "$CLAUDE_DIR/hooks/env-guard.sh" ]; then
  OUT="$(echo '{"tool_input":{"file_path":"/tmp/probe/.env"}}' | "$CLAUDE_DIR/hooks/env-guard.sh" 2>/dev/null)"
  if [ -n "$OUT" ] && printf '%s' "$OUT" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
    ok "hooks emit valid JSON"
  else
    bad "env-guard produced no or malformed JSON" "bash -n ~/.claude/hooks/env-guard.sh"
  fi
fi

if [ -f "$CLAUDE_DIR/d1-config.sh" ]; then
  # shellcheck source=/dev/null
  . "$CLAUDE_DIR/d1-config.sh"
  ok "d1-config.sh present"
  for pair in "PERSONAL_CONTEXT_DIR:${PERSONAL_CONTEXT_DIR:-}" "PUBLIC_CONTEXT_DIR:${PUBLIC_CONTEXT_DIR:-}"; do
    name="${pair%%:*}"; dir="${pair#*:}"
    if [ -z "$dir" ]; then
      warn "$name not set"
    elif [ -d "$dir/.git" ]; then
      ok "$name is a git repo"
    else
      bad "$name points at $dir, which is not a git repo, so syncing silently does nothing" \
        "fix the path in ~/.claude/d1-config.sh"
    fi
  done
else
  warn "no d1-config.sh, context syncing is off"
fi

# The CLI half and the editor half are separate switches. defaultMode alone
# leaves you prompted inside VS Code, which is the most common way this kit
# looks broken when it is not.
EDITOR_BASE="$HOME/Library/Application Support"
[ -d "$EDITOR_BASE" ] || EDITOR_BASE="$HOME/.config"
EDITOR_FOUND=0
for ed in "Code" "Code - Insiders" "Cursor" "VSCodium" "Windsurf"; do
  f="$EDITOR_BASE/$ed/User/settings.json"
  [ -f "$f" ] || continue
  EDITOR_FOUND=1
  RESULT="$(python3 - "$f" << 'PYDOC' 2>/dev/null || echo unreadable
import json, sys
try:
    s = json.load(open(sys.argv[1]))
except Exception:
    print("unreadable"); raise SystemExit(0)
gate = s.get("claudeCode.allowDangerouslySkipPermissions") is True
mode = s.get("claudeCode.initialPermissionMode") == "bypassPermissions"
print("ok" if gate and mode else ("gate" if not gate else "mode"))
PYDOC
)"
  case "$RESULT" in
    ok)   ok "$ed will not prompt for permissions" ;;
    gate) warn "$ed: claudeCode.allowDangerouslySkipPermissions is not true, so bypass mode is ignored" ;;
    mode) warn "$ed: claudeCode.initialPermissionMode is not bypassPermissions" ;;
    *)    warn "$ed: settings.json could not be parsed" ;;
  esac
done
[ "$EDITOR_FOUND" -eq 1 ] || ok "no VS Code style editor installed, nothing to configure"

# The desktop app reads ~/.claude/settings.json like the CLI, so defaultMode
# covers it. Dispatched coding tasks are the one surface with a preference of
# their own, and it ships as acceptEdits.
CLAUDE_APP_DIR="$HOME/Library/Application Support/Claude"
[ -d "$CLAUDE_APP_DIR" ] || CLAUDE_APP_DIR="$HOME/.config/Claude"
if [ -f "$CLAUDE_APP_DIR/config.json" ]; then
  APP_MODE="$(python3 -c "
import json,sys
try: print(json.load(open(sys.argv[1])).get('dispatchCodeTasksPermissionMode','acceptEdits'))
except Exception: print('unreadable')" "$CLAUDE_APP_DIR/config.json" 2>/dev/null || echo unreadable)"
  case "$APP_MODE" in
    bypassPermissions) ok "Claude desktop app dispatches coding tasks without prompting" ;;
    unreadable)        warn "Claude desktop app config.json could not be parsed" ;;
    *)                 warn "Claude desktop app dispatchCodeTasksPermissionMode is $APP_MODE, so dispatched coding tasks still prompt" ;;
  esac
else
  ok "Claude desktop app not installed, nothing to configure"
fi

# bypassPermissions is ignored when it comes from a repo-committed file. Someone
# who put it in a project settings file gets no error, just prompts.
for f in .claude/settings.json .claude/settings.local.json; do
  [ -f "$f" ] || continue
  if python3 -c "
import json,sys
try: m = json.load(open(sys.argv[1])).get('permissions',{}).get('defaultMode')
except Exception: sys.exit(1)
sys.exit(0 if m in ('bypassPermissions','auto','dontAsk') else 1)" "$f" 2>/dev/null; then
    warn "$f sets defaultMode to a mode only the user tier can set. It is being ignored; move it to ~/.claude/settings.json"
  fi
done

# A managed policy beats everything above and is silent about it.
MANAGED="/Library/Application Support/ClaudeCode/managed-settings.json"
if [ -f "$MANAGED" ] && python3 -c "
import json,sys
try: v = json.load(open(sys.argv[1])).get('permissions',{}).get('disableBypassPermissionsMode')
except Exception: sys.exit(1)
sys.exit(0 if v == 'disable' else 1)" "$MANAGED" 2>/dev/null; then
  warn "managed settings set disableBypassPermissionsMode, which overrides every setting above"
fi

# ── Standards actually loading ────────────────────────────────────────────────
section "Standards"

CLAUDE_MD=""
for c in "$CLAUDE_DIR/CLAUDE.md" "./CLAUDE.md"; do
  [ -f "$c" ] && CLAUDE_MD="$c" && break
done

if [ -z "$CLAUDE_MD" ]; then
  bad "no CLAUDE.md found" "run setup.sh or install.sh"
else
  ok "CLAUDE.md found at $CLAUDE_MD"
  IMPORTS="$(grep -c '^@' "$CLAUDE_MD" 2>/dev/null || echo 0)"
  if [ "$IMPORTS" -eq 0 ]; then
    bad "CLAUDE.md has no @ imports, so the rules files load nothing" \
      "this is the bug that made all 18 rules inert; reinstall from the current kit"
  else
    ok "CLAUDE.md declares $IMPORTS imports"
    MISSING=0
    while read -r line; do
      path="${line#@}"
      path="${path/#\~/$HOME}"
      [ -f "$path" ] || { bad "import does not resolve: $line" "expected a file at $path"; MISSING=$((MISSING+1)); }
    done < <(grep '^@' "$CLAUDE_MD")
    [ "$MISSING" -eq 0 ] && ok "every import resolves to a real file"
  fi
fi

RULE_COUNT="$(ls "$CLAUDE_DIR"/rules/*.md 2>/dev/null | wc -l | tr -d ' ')"
[ "$RULE_COUNT" -gt 0 ] &&
  ok "$RULE_COUNT always-on rules installed" ||
  bad "no rules in ~/.claude/rules/" "run install.sh or setup.sh"

SKILL_COUNT="$(ls -d "$CLAUDE_DIR"/skills/*/ 2>/dev/null | wc -l | tr -d ' ')"
[ "$SKILL_COUNT" -gt 0 ] &&
  ok "$SKILL_COUNT skills installed" ||
  warn "no skills in ~/.claude/skills/, the 12 stack standards will never load"

AGENT_COUNT="$(ls "$CLAUDE_DIR"/agents/*.md 2>/dev/null | wc -l | tr -d ' ')"
[ "$AGENT_COUNT" -gt 0 ] &&
  ok "$AGENT_COUNT subagents installed" ||
  warn "no subagents in ~/.claude/agents/"

CMD_COUNT="$(ls "$CLAUDE_DIR"/commands/*.md 2>/dev/null | wc -l | tr -d ' ')"
[ "$CMD_COUNT" -gt 0 ] &&
  ok "$CMD_COUNT slash commands installed" ||
  warn "no commands in ~/.claude/commands/"

# ── macOS tools ───────────────────────────────────────────────────────────────
# These are optional add-ons, so a missing one warns rather than fails. A tool
# that is installed but unusable does fail: a granted-looking peekaboo that
# cannot capture is worse than no peekaboo, because Claude will keep trying.
section "macOS tools"

if [ "$(uname)" != "Darwin" ]; then
  warn "not macOS, skipping tool checks"
else
  if command -v peekaboo >/dev/null 2>&1; then
    if peekaboo permissions 2>/dev/null | grep -q "Denied"; then
      bad "peekaboo installed but missing permissions" \
        "System Settings > Privacy & Security > grant Screen Recording and Accessibility"
    else
      ok "peekaboo present and permitted"
    fi
    if command -v claude >/dev/null 2>&1; then
      claude mcp list 2>/dev/null | grep -q "^peekaboo:" &&
        ok "peekaboo MCP registered" ||
        warn "peekaboo MCP not registered (claude mcp add peekaboo --scope user -- peekaboo mcp serve)"
    fi
  else
    warn "peekaboo missing, Claude cannot see or drive the screen" 
  fi

  command -v summarize >/dev/null 2>&1 &&
    ok "summarize present" ||
    warn "summarize missing (brew install steipete/tap/summarize)"

  if command -v mac-use >/dev/null 2>&1; then
    if [ -x "$HOME/Projects/macOS-use/.venv/bin/python" ]; then
      ok "mac-use present"
    else
      bad "mac-use on PATH but its venv is missing, every run will exit 1" \
        "cd ~/Projects/macOS-use && uv venv --python 3.11 && uv pip install -e ."
    fi
  else
    warn "mac-use missing, no natural-language app automation"
  fi

  # Consent is granted to the terminal, not the binary, so a `mac` that works in
  # one terminal warns in another. That is worth reporting, not fixing here.
  if command -v mac >/dev/null 2>&1; then
    if mac doctor 2>/dev/null | grep -q ": granted"; then
      ok "mac present and permitted"
    else
      warn "mac installed but no capability granted yet (mac doctor)"
    fi
  else
    warn "mac missing, no Calendar/Contacts/Messages/Notes access"
  fi

  [ -d "/Applications/Plynn.app" ] &&
    ok "Plynn installed (hold fn to dictate)" ||
    warn "Plynn missing, no on-device dictation (bin/install-plynn.sh)"

  [ -d "/Applications/Maccy.app" ] &&
    ok "Maccy installed" ||
    warn "Maccy missing (brew install --cask maccy)"

  # No `case` here: macOS ships bash 3.2, which mis-parses a case pattern's
  # closing paren inside $( ).
  PACK_LINKS=$(find "$CLAUDE_DIR/skills" -maxdepth 1 -type l -exec readlink {} \; 2>/dev/null |
    grep -c "agent-scripts")
  if [ "$PACK_LINKS" -gt 0 ]; then
    ok "agent-scripts pack linked ($PACK_LINKS skills)"
    BROKEN=$(find "$CLAUDE_DIR/skills" -maxdepth 1 -type l ! -exec test -e {} \; -print 2>/dev/null | wc -l | tr -d ' ')
    [ "$BROKEN" -eq 0 ] &&
      ok "no dangling skill links" ||
      bad "$BROKEN dangling skill links in ~/.claude/skills" \
        "find ~/.claude/skills -maxdepth 1 -type l ! -exec test -e {} \\; -print"
  else
    warn "agent-scripts pack not linked (re-run setup.sh)"
  fi
fi

# ── Coursework ────────────────────────────────────────────────────────────────
section "Coursework"

COURSEWORK_HOME="${COURSEWORK_DIR:-$HOME/coursework}"
if command -v coursework >/dev/null 2>&1; then
  ok "coursework CLI on PATH"
  if [ -d "$COURSEWORK_HOME" ]; then
    CW_COURSES="$(ls "$COURSEWORK_HOME"/courses/*.yml 2>/dev/null | wc -l | tr -d ' ')"
    if [ "$CW_COURSES" -gt 0 ]; then
      ok "$CW_COURSES course file(s) in $COURSEWORK_HOME/courses"
      # `coursework check` exits non-zero on a ledger that parses but lies by
      # omission: a deadline with no source, a course with no AI policy.
      if coursework check >/dev/null 2>&1; then
        ok "ledger validates"
      else
        warn "ledger has gaps. Run: coursework check"
      fi
    else
      warn "no course files yet. Run /syllabus on a syllabus PDF."
    fi
  else
    warn "no ledger at $COURSEWORK_HOME. Run setup.sh, or mkdir -p $COURSEWORK_HOME/courses"
  fi
else
  warn "coursework not on PATH, so /due, /week, and /attendance have no data source"
fi

# ── Commit attribution ────────────────────────────────────────────────────────
# Off by default here on purpose. Catching this after a hundred commits means
# rewriting every one of them and force-pushing a public branch.
section "Commit attribution"

CO_AUTH=$(python3 -c "
import json, pathlib
p = pathlib.Path.home() / '.claude/settings.json'
try:
    print(json.loads(p.read_text()).get('includeCoAuthoredBy', 'unset'))
except Exception:
    print('unreadable')
" 2>/dev/null)

case "$CO_AUTH" in
  False) ok "commits are attributed to you alone" ;;
  unset) warn "includeCoAuthoredBy is unset, so commits get a Co-Authored-By: Claude trailer" ;;
  *) bad "Claude is co-authoring your commits (includeCoAuthoredBy=$CO_AUTH)" \
    "set \"includeCoAuthoredBy\": false in ~/.claude/settings.json" ;;
esac

# ── Writing rules ─────────────────────────────────────────────────────────────
# The rules are only real if something checks them. A CLAUDE.md section that
# nobody enforces is a suggestion.
section "Writing rules"

if command -v slop-check >/dev/null 2>&1; then
  ok "slop-check on PATH"
  if [ -x "$CLAUDE_DIR/hooks/slop-guard.sh" ]; then
    if grep -q "slop-guard" "$CLAUDE_DIR/settings.json" 2>/dev/null; then
      ok "slop guard wired to the Stop hook"
    else
      bad "slop-guard.sh installed but not wired to any hook" \
        "re-run setup.sh, or add it to hooks.Stop in ~/.claude/settings.json"
    fi
  else
    warn "slop-guard.sh missing, so nothing checks what Claude writes"
  fi
else
  warn "slop-check missing (re-run setup.sh)"
fi

# ── Secrets ───────────────────────────────────────────────────────────────────
section "Secrets"

LEAKS="$(grep -rlE 'Bearer [A-Za-z0-9_-]{32}|sk-ant-[A-Za-z0-9]{20}|ghp_[A-Za-z0-9]{20}' \
  "$CLAUDE_DIR/commands" "$CLAUDE_DIR/rules" "$CLAUDE_DIR/skills" 2>/dev/null | head -5)"
if [ -n "$LEAKS" ]; then
  bad "hardcoded credential in installed files:" "use an env var instead"
  printf '        %s\n' $LEAKS
else
  ok "no hardcoded credentials in commands, rules, or skills"
fi

# ── Verdict ───────────────────────────────────────────────────────────────────
echo ""
if [ "$FAIL" -eq 0 ]; then
  echo -e "${GRN}${BLD}$PASS passed${NC}${GRN}, $WARN warnings, 0 failures.${NC}"
  exit 0
fi
echo -e "${RED}${BLD}$FAIL failed${NC}${RED}, $WARN warnings, $PASS passed.${NC}"
exit 1

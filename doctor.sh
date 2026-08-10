#!/bin/bash
# D1 Vibe Coding: verify the install actually works.
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

CMD_COUNT="$(ls "$CLAUDE_DIR"/commands/*.md 2>/dev/null | wc -l | tr -d ' ')"
[ "$CMD_COUNT" -gt 0 ] &&
  ok "$CMD_COUNT slash commands installed" ||
  warn "no commands in ~/.claude/commands/"

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

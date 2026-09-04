#!/usr/bin/env bash
# chewbacca status: what is installed, what is on, what is stale.
#
# doctor says whether the install is broken. This says what the install IS.
# Nobody could answer "what is actually turned on right now" without reading
# four files in three directories.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STATE="$HOME/.chewbacca"
CLAUDE_DIR="$HOME/.claude"
BLD='\033[1m'; DIM='\033[2m'; GRN='\033[0;32m'; YLW='\033[1;33m'; NC='\033[0m'

JSON=0
[ "${1:-}" = "--json" ] && JSON=1

count() { ls -1 "$1" 2>/dev/null | wc -l | tr -d ' '; }
age_days() {
  [ -f "$1" ] || { echo -1; return; }
  local mt now
  mt=$(stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0)
  now=$(date +%s)
  echo $(( (now - mt) / 86400 ))
}

VERSION_REPO="$(cat "$ROOT/VERSION" 2>/dev/null || echo unknown)"
VERSION_INST="$(cat "$STATE/version" 2>/dev/null || echo unrecorded)"
PROFILE="$(cat "$CLAUDE_DIR/.chewbacca-profile" 2>/dev/null || echo unknown)"
MODE="$(python3 -c "import json,sys;print(json.load(open('$CLAUDE_DIR/settings.json')).get('permissions',{}).get('defaultMode','default'))" 2>/dev/null || echo unknown)"
SKILLS="$(count "$CLAUDE_DIR/skills")"
CMDS="$(count "$CLAUDE_DIR/commands")"
RULES="$(count "$CLAUDE_DIR/rules")"
HOOKS="$(count "$CLAUDE_DIR/hooks")"
AGENTS="$(count "$CLAUDE_DIR/agents")"
DOCTOR_AGE="$(age_days "$STATE/doctor.log")"
DOCTOR_RESULT="never run"
if [ -f "$STATE/doctor.log" ]; then
  # grep -c exits 1 on zero matches, which turned "0 failing" into two lines.
  DF=$(grep -c '^FAIL' "$STATE/doctor.log" 2>/dev/null) || DF=0
  DW=$(grep -c '^warn' "$STATE/doctor.log" 2>/dev/null) || DW=0
  DOCTOR_RESULT="$DF failing, $DW warning"
fi
STATE_SIZE="$(du -sh "$STATE" 2>/dev/null | cut -f1 || echo 0)"
PEOPLE=0
[ -f "$STATE/people/people.db" ] && PEOPLE="$(sqlite3 "$STATE/people/people.db" 'select count(*) from people' 2>/dev/null || echo unknown)"

if [ "$JSON" -eq 1 ]; then
  printf '{"version_repo":"%s","version_installed":"%s","profile":"%s","permission_mode":"%s",' \
    "$VERSION_REPO" "$VERSION_INST" "$PROFILE" "$MODE"
  printf '"skills":%s,"commands":%s,"rules":%s,"hooks":%s,"subagents":%s,' \
    "$SKILLS" "$CMDS" "$RULES" "$HOOKS" "$AGENTS"
  printf '"people":"%s","state_size":"%s","doctor_age_days":%s,"doctor":"%s"}\n' \
    "$PEOPLE" "$STATE_SIZE" "$DOCTOR_AGE" "$DOCTOR_RESULT"
  exit 0
fi

echo -e "${BLD}Chewbacca${NC} $VERSION_REPO  ${DIM}($ROOT)${NC}"
[ "$VERSION_REPO" != "$VERSION_INST" ] &&
  echo -e "  ${YLW}installed version is $VERSION_INST. Run: chewbacca setup${NC}"
echo
echo -e "${BLD}Install${NC}"
printf '  %-22s %s\n' "profile" "$PROFILE"
printf '  %-22s %s\n' "permission mode" "$MODE"
printf '  %-22s %s\n' "skills" "$SKILLS"
printf '  %-22s %s\n' "slash commands" "$CMDS"
printf '  %-22s %s\n' "always-on rules" "$RULES"
printf '  %-22s %s\n' "hooks" "$HOOKS"
printf '  %-22s %s\n' "subagents" "$AGENTS"
echo
echo -e "${BLD}Your data${NC}"
printf '  %-22s %s\n' "people" "$PEOPLE"
printf '  %-22s %s\n' "state on disk" "$STATE_SIZE"
printf '  %-22s %s\n' "state directory" "$STATE"
echo
echo -e "${BLD}Health${NC}"
if [ "$DOCTOR_AGE" -lt 0 ]; then
  printf '  %-22s %s\n' "doctor" "never run. Run: chewbacca doctor"
else
  printf '  %-22s %s\n' "doctor" "$DOCTOR_RESULT, ${DOCTOR_AGE}d ago"
fi
if [ -f "$STATE/logs/hooks.log" ]; then
  SLOW="$(sort -t'|' -k3 -rn "$STATE/logs/hooks.log" 2>/dev/null | head -1 | cut -d'|' -f2,3 | tr '|' ' ')"
  [ -n "$SLOW" ] && printf '  %-22s %s\n' "slowest hook" "${SLOW}ms"
fi
echo -e "\n${DIM}chewbacca doctor for what is broken, chewbacca log for what it has been doing.${NC}"

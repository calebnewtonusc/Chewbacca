#!/usr/bin/env bash
# chewbacca import: restore a bundle written by chewbacca export.
set -uo pipefail
SRC="${1:-}"
[ -f "$SRC" ] || { echo "usage: chewbacca import <bundle.tar.gz>" >&2; exit 2; }
STATE="$HOME/.chewbacca"
CLAUDE_DIR="$HOME/.claude"
GRN='\033[0;32m'; YLW='\033[1;33m'; NC='\033[0m'
DRY=0
[ "${2:-}" = "--dry-run" ] && DRY=1

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
tar -xzf "$SRC" -C "$TMP"
B="$TMP/chewbacca-export"
[ -d "$B" ] || { echo "not a chewbacca export bundle" >&2; exit 1; }

echo "From: $(python3 -c "import json;d=json.load(open('$B/MANIFEST.json'));print(d['host'], d['created'], 'version', d['version'])" 2>/dev/null || echo unknown)"
[ "$DRY" -eq 1 ] && echo -e "${YLW}Dry run. Nothing will be written.${NC}"

restore() {
  local from="$1" to="$2"
  [ -e "$B/$from" ] || return 0
  if [ -e "$to" ]; then
    echo "  $to exists, saving yours to ${to}.before-import"
    [ "$DRY" -eq 0 ] && cp -R "$to" "${to}.before-import"
  fi
  [ "$DRY" -eq 0 ] && mkdir -p "$(dirname "$to")" && cp -R "$B/$from" "$to"
  echo "  restored $from"
}

mkdir -p "$STATE"
restore people "$STATE/people"
restore version "$STATE/version"
restore profile "$CLAUDE_DIR/.chewbacca-profile"
restore coursework "$HOME/coursework"
if [ -d "$B/own-skills" ]; then
  for d in "$B"/own-skills/*/; do
    restore "own-skills/$(basename "$d")" "$CLAUDE_DIR/skills/$(basename "$d")"
  done
fi
echo
echo -e "${GRN}Done.${NC} settings.json was NOT overwritten: this machine's paths and"
echo "permissions are its own. Run chewbacca doctor to confirm."

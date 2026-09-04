#!/usr/bin/env bash
# chewbacca skills: list, search, or show a skill.
#
# 78 skills install and there was no way to see them without ls-ing a
# directory of symlinks and opening each SKILL.md by hand.
set -uo pipefail
DIRS=("$HOME/.claude/skills")
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

desc_of() {
  # Frontmatter description, first line only, quotes stripped.
  sed -n '/^description:/,/^[a-z_]*:/p' "$1" 2>/dev/null | head -1 |
    sed 's/^description: *//; s/^"//; s/"$//' | cut -c1-100
}
origin_of() {
  local d="$1"
  if [ -L "$d" ]; then
    local t; t="$(readlink "$d")"
    case "$t" in
      "$ROOT"/*) echo "this kit" ;;
      *) echo "$(basename "$(dirname "$(dirname "$t")")")" ;;
    esac
  else
    echo "local"
  fi
}

cmd="${1:-list}"
case "$cmd" in
list | "")
  n=0
  for base in "${DIRS[@]}"; do
    [ -d "$base" ] || continue
    for d in "$base"/*/; do
      [ -f "$d/SKILL.md" ] || continue
      name="$(basename "$d")"
      printf "  ${BLD}%-24s${NC} ${DIM}%-14s${NC} %s\n" \
        "$name" "$(origin_of "${d%/}")" "$(desc_of "$d/SKILL.md")"
      n=$((n + 1))
    done
  done
  echo
  echo "$n skills. chewbacca skills show <name> for the whole thing."
  ;;
search)
  q="${2:-}"
  [ -z "$q" ] && { echo "usage: chewbacca skills search <term>" >&2; exit 2; }
  for base in "${DIRS[@]}"; do
    [ -d "$base" ] || continue
    grep -ril "$q" "$base"/*/SKILL.md 2>/dev/null | while read -r f; do
      name="$(basename "$(dirname "$f")")"
      hits="$(grep -ic "$q" "$f")"
      printf "  ${BLD}%-24s${NC} %s hit(s)  %s\n" "$name" "$hits" "$(desc_of "$f")"
    done
  done
  ;;
show)
  name="${2:-}"
  [ -z "$name" ] && { echo "usage: chewbacca skills show <name>" >&2; exit 2; }
  f="$HOME/.claude/skills/$name/SKILL.md"
  [ -f "$f" ] || { echo "no skill named '$name'. chewbacca skills list" >&2; exit 1; }
  "${PAGER:-cat}" "$f"
  ;;
--json)
  printf '['
  first=1
  for d in "$HOME/.claude/skills"/*/; do
    [ -f "$d/SKILL.md" ] || continue
    [ $first -eq 0 ] && printf ','
    printf '{"name":"%s","origin":"%s"}' "$(basename "$d")" "$(origin_of "${d%/}")"
    first=0
  done
  printf ']\n'
  ;;
*)
  echo "usage: chewbacca skills [list|search <term>|show <name>|--json]" >&2
  exit 2
  ;;
esac

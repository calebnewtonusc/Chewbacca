#!/usr/bin/env bash
# chewbacca commands: list, search, or show a slash command.
#
# 57 of them, discoverable only by ls-ing a directory and opening files. The
# kit's own argument is that you should rarely need one, which is not a reason
# for the ones that exist to be unfindable.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DIR="$HOME/.claude/commands"
[ -d "$DIR" ] || DIR="$ROOT/.claude/commands"
BLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

desc_of() {
  sed -n '/^description:/{s/^description: *//; s/^"//; s/"$//; p; q;}' "$1" 2>/dev/null | cut -c1-96
}
hint_of() {
  sed -n '/^argument-hint:/{s/^argument-hint: *//; p; q;}' "$1" 2>/dev/null
}

case "${1:-list}" in
list | "")
  n=0
  for f in "$DIR"/*.md; do
    [ -f "$f" ] || continue
    name="$(basename "$f" .md)"
    hint="$(hint_of "$f")"
    printf "  ${BLD}/%-16s${NC} ${DIM}%-14s${NC} %s\n" "$name" "${hint:-}" "$(desc_of "$f")"
    n=$((n + 1))
  done
  echo
  echo "$n commands. chewbacca commands show <name> for the whole thing."
  echo "You rarely need any of them. Describing what you want loads the right skill."
  ;;
search)
  q="${2:-}"
  [ -z "$q" ] && { echo "usage: chewbacca commands search <term>" >&2; exit 2; }
  for f in "$DIR"/*.md; do
    [ -f "$f" ] || continue
    grep -qil "$q" "$f" || continue
    printf "  ${BLD}/%-16s${NC} %s\n" "$(basename "$f" .md)" "$(desc_of "$f")"
  done
  ;;
show)
  name="${2:-}"
  [ -z "$name" ] && { echo "usage: chewbacca commands show <name>" >&2; exit 2; }
  f="$DIR/${name#/}.md"
  [ -f "$f" ] || { echo "no command named '${name#/}'. chewbacca commands list" >&2; exit 1; }
  "${PAGER:-cat}" "$f"
  ;;
--json)
  printf '['
  first=1
  for f in "$DIR"/*.md; do
    [ -f "$f" ] || continue
    [ $first -eq 0 ] && printf ','
    printf '{"name":"%s","description":"%s"}' "$(basename "$f" .md)" "$(desc_of "$f" | sed 's/"/\\"/g')"
    first=0
  done
  printf ']\n'
  ;;
*)
  echo "usage: chewbacca commands [list|search <term>|show <name>|--json]" >&2
  exit 2
  ;;
esac

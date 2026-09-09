#!/bin/bash
# What Karthik and Sagar shipped in Amber since you last looked.
#
# Chewbacca's people layer is a port of Amber's, with their permission, so their
# architecture decisions are upstream of ours. This tells you what moved without
# you having to remember to go look.
#
#   amber-pull            since your last run
#   amber-pull 14         last 14 days
#   amber-pull --clone    also fetch the repos locally

set -euo pipefail
ORG=amberintelligence
PROJECTS="${HOME}/Desktop/2026-Code/projects"
STATE="${HOME}/.chewbacca/amber-last-pull"
CLONE=0
DAYS=""

for a in "$@"; do
  case "$a" in
    --clone) CLONE=1 ;;
    ''|*[!0-9]*) ;;
    *) DAYS="$a" ;;
  esac
done

if [ -n "$DAYS" ]; then
  SINCE=$(date -u -v-"${DAYS}"d +%Y-%m-%dT%H:%M:%SZ)
elif [ -f "$STATE" ]; then
  SINCE=$(cat "$STATE")
else
  SINCE=$(date -u -v-14d +%Y-%m-%dT%H:%M:%SZ)
fi

printf '\n  \033[1mAmber since %s\033[0m\n' "${SINCE%T*}"

found=0
for repo in $(gh repo list "$ORG" --limit 50 --json name -q '.[].name' 2>/dev/null); do
  log=$(gh api "repos/$ORG/$repo/commits?since=$SINCE&per_page=100" \
        -q '.[] | "    \(.commit.author.date[0:10])  \(.commit.author.name[0:14] | .[0:14])  \(.commit.message | split("\n")[0][0:92])"' 2>/dev/null || true)
  [ -z "$log" ] && continue
  found=1
  n=$(printf '%s\n' "$log" | wc -l | tr -d ' ')
  printf '\n  \033[36m%s\033[0m  \033[2m%s commits\033[0m\n%s\n' "$repo" "$n" "$log"
  if [ "$CLONE" = 1 ]; then
    if [ -d "$PROJECTS/$repo/.git" ]; then
      git -C "$PROJECTS/$repo" fetch --all --quiet && printf '    \033[2mfetched\033[0m\n'
    else
      gh repo clone "$ORG/$repo" "$PROJECTS/$repo" -- --quiet && printf '    \033[2mcloned\033[0m\n'
    fi
  fi
done

[ "$found" = 0 ] && printf '\n  nothing new\n'
date -u +%Y-%m-%dT%H:%M:%SZ > "$STATE"
printf '\n'

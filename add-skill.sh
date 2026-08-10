#!/bin/bash
# Install a Claude skill from a git repo, without vendoring it.
#
# Cloning beats copying: the skill stays updatable, its LICENSE travels with it,
# and you do not silently inherit terms you never read. That last part matters.
# One popular skills repo advertises Apache 2.0 on its badge while shipping four
# skills marked Proprietary and one under AGPL-3.0, which would relicense an MIT
# project by contagion. So this prints the declared license before it installs.
#
#   ./add-skill.sh <git-url>
#   ./add-skill.sh <git-url> --path skills/no-ai-slop
#   ./add-skill.sh <git-url> --project        install to ./.claude/skills instead
#
# Exits non-zero if nothing was installed.

set -uo pipefail

GRN='\033[0;32m'; RED='\033[0;31m'; YLW='\033[1;33m'; BLD='\033[1m'; NC='\033[0m'

URL=""; SUBPATH=""; DEST="$HOME/.claude/skills"
while [ $# -gt 0 ]; do
  case "$1" in
    --path) SUBPATH="${2:-}"; shift 2 ;;
    --project) DEST="$(pwd)/.claude/skills"; shift ;;
    -h | --help) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) URL="$1"; shift ;;
  esac
done

if [ -z "$URL" ]; then
  echo -e "${RED}Need a git URL.${NC} Try: ./add-skill.sh --help"
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo -e "\n${BLD}Cloning${NC} $URL"
if ! git clone -q --depth 1 "$URL" "$TMP/repo" 2>/dev/null; then
  echo -e "  ${RED}FAIL${NC}  could not clone. Check the URL and your network."
  exit 1
fi

# Locate the skill. Either the caller named it, or the repo root is the skill,
# or there is exactly one SKILL.md somewhere inside.
if [ -n "$SUBPATH" ]; then
  SKILL_DIR="$TMP/repo/$SUBPATH"
  [ -f "$SKILL_DIR/SKILL.md" ] || {
    echo -e "  ${RED}FAIL${NC}  no SKILL.md at --path $SUBPATH"
    exit 1
  }
elif [ -f "$TMP/repo/SKILL.md" ]; then
  SKILL_DIR="$TMP/repo"
else
  mapfile -t FOUND < <(find "$TMP/repo" -name SKILL.md -not -path "*/.git/*" | sort)
  if [ "${#FOUND[@]}" -eq 0 ]; then
    echo -e "  ${RED}FAIL${NC}  no SKILL.md anywhere in this repo."
    exit 1
  elif [ "${#FOUND[@]}" -gt 1 ]; then
    echo -e "  ${YLW}This repo holds ${#FOUND[@]} skills. Pick one with --path:${NC}"
    for f in "${FOUND[@]}"; do
      rel="$(dirname "${f#"$TMP/repo/"}")"
      echo "    --path $rel"
    done
    exit 1
  fi
  SKILL_DIR="$(dirname "${FOUND[0]}")"
fi

NAME="$(grep -m1 '^name:' "$SKILL_DIR/SKILL.md" 2>/dev/null | sed 's/^name: *//' | tr -d '"')"
[ -n "$NAME" ] || NAME="$(basename "$SKILL_DIR")"

# Surface the license before anything is written.
LICENSE_LINE="$(grep -m1 '^license:' "$SKILL_DIR/SKILL.md" 2>/dev/null | sed 's/^license: *//')"
echo -e "\n${BLD}Skill:${NC}   $NAME"
if [ -z "$LICENSE_LINE" ]; then
  echo -e "${BLD}License:${NC} ${YLW}none declared in SKILL.md${NC}, check the repo before redistributing"
else
  case "$(printf '%s' "$LICENSE_LINE" | tr '[:upper:]' '[:lower:]')" in
    *proprietary* | *agpl*)
      echo -e "${BLD}License:${NC} ${RED}$LICENSE_LINE${NC}"
      echo -e "  ${YLW}Installing for your own use is fine. Do not redistribute this,${NC}"
      echo -e "  ${YLW}and do not commit it into a repo under a different license.${NC}"
      ;;
    *) echo -e "${BLD}License:${NC} $LICENSE_LINE" ;;
  esac
fi

if [ -d "$DEST/$NAME" ]; then
  echo -e "\n  ${YLW}$NAME is already installed at $DEST/$NAME${NC}"
  read -rp "  Overwrite? [y/N]: " REPLY
  [[ "$REPLY" =~ ^[Yy]$ ]] || { echo "  Left alone."; exit 0; }
  rm -rf "${DEST:?}/${NAME:?}"
fi

mkdir -p "$DEST/$NAME"
cp -R "$SKILL_DIR/." "$DEST/$NAME/"

# Carry the license along even when it lives at the repo root.
if [ ! -f "$DEST/$NAME/LICENSE" ] && [ ! -f "$DEST/$NAME/LICENSE.txt" ]; then
  for l in LICENSE LICENSE.txt LICENSE.md; do
    [ -f "$TMP/repo/$l" ] && cp "$TMP/repo/$l" "$DEST/$NAME/$l" && break
  done
fi

# Record where it came from, so it can be updated later without guesswork.
{
  echo "source: $URL"
  [ -n "$SUBPATH" ] && echo "path: $SUBPATH"
  echo "installed: $(date -u +%Y-%m-%d)"
} > "$DEST/$NAME/.source"

echo -e "\n  ${GRN}installed${NC}  $DEST/$NAME"
echo -e "  Run ${BLD}/reload-skills${NC} in Claude Code, or start a new session.\n"

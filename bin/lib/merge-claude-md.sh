#!/usr/bin/env bash
# Install the standards into a CLAUDE.md without destroying what is there.
#
#   merge-claude-md.sh <target CLAUDE.md> <standards file>
#
# Anyone who already had a CLAUDE.md lost it, with no backup and no warning.
# That is a bad first thing for an installer to do to a file somebody wrote by
# hand. Three cases:
#
#   no file          write the standards
#   a file we wrote  replace only the region between our markers
#   somebody's file  keep it, put it below the standards, back up the original
#
# Extracted from setup.sh so it can be tested. It could not be, inside 1,700
# lines that also clone repos and install Homebrew.
set -uo pipefail

TARGET="${1:-}"
STANDARDS="${2:-}"
[ -n "$TARGET" ] && [ -f "$STANDARDS" ] || {
  echo "usage: merge-claude-md.sh <target> <standards>" >&2; exit 2; }

BEGIN="<!-- CHEWBACCA:BEGIN -->"
END="<!-- CHEWBACCA:END -->"

if [ ! -f "$TARGET" ]; then
  mkdir -p "$(dirname "$TARGET")"
  { echo "$BEGIN"; cat "$STANDARDS"; echo "$END"; } > "$TARGET"
  echo "wrote"
  exit 0
fi

if grep -q "$BEGIN" "$TARGET" 2>/dev/null; then
  python3 - "$TARGET" "$STANDARDS" <<'PY'
import pathlib, re, sys
target, standards = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
body = standards.read_text(encoding="utf-8")
new = "<!-- CHEWBACCA:BEGIN -->\n" + body + "<!-- CHEWBACCA:END -->"
text = target.read_text(encoding="utf-8")
# A lambda, not a replacement string: the standards contain backslashes and
# group references, and re.sub would interpret them.
target.write_text(
    re.sub(r"<!-- CHEWBACCA:BEGIN -->.*?<!-- CHEWBACCA:END -->", lambda m: new, text, flags=re.S),
    encoding="utf-8")
PY
  echo "updated"
  exit 0
fi

if cmp -s "$STANDARDS" "$TARGET"; then
  { echo "$BEGIN"; cat "$STANDARDS"; echo "$END"; } > "$TARGET"
  echo "adopted"
  exit 0
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$TARGET.yours-$STAMP"
cp "$TARGET" "$BACKUP"
{
  echo "$BEGIN"
  cat "$STANDARDS"
  echo "$END"
  echo
  echo "---"
  echo
  echo "# Yours"
  echo
  echo "Everything below was in your CLAUDE.md before Chewbacca was installed."
  echo "It is kept, and it wins where it disagrees with anything above, because"
  echo "later instructions take precedence. The original is at"
  echo "$(basename "$BACKUP")."
  echo
  cat "$BACKUP"
} > "$TARGET.new"
mv "$TARGET.new" "$TARGET"
echo "merged"

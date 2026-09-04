#!/usr/bin/env bash
# chewbacca export: bundle this machine's kit state so a second Mac is not
# a fresh start, and so uninstalling is not the same as losing everything.
set -uo pipefail
STATE="$HOME/.chewbacca"
CLAUDE_DIR="$HOME/.claude"
OUT="${1:-$HOME/chewbacca-export-$(date +%Y%m%d-%H%M%S).tar.gz}"
GRN='\033[0;32m'; DIM='\033[2m'; NC='\033[0m'

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
BUNDLE="$TMP/chewbacca-export"
mkdir -p "$BUNDLE"

copy() { [ -e "$1" ] && cp -R "$1" "$BUNDLE/$2" 2>/dev/null && echo "  included $2"; }

echo "Bundling..."
copy "$STATE/people" people
copy "$STATE/version" version
copy "$CLAUDE_DIR/.chewbacca-profile" profile
copy "$CLAUDE_DIR/settings.json" settings.json
copy "$STATE/install-manifest.json" install-manifest.json
[ -d "$HOME/coursework" ] && copy "$HOME/coursework" coursework

# Anything the user wrote themselves, which setup did not put there.
mkdir -p "$BUNDLE/own-skills"
for d in "$CLAUDE_DIR"/skills/*/; do
  [ -L "${d%/}" ] && continue
  [ -f "$d/SKILL.md" ] || continue
  cp -R "$d" "$BUNDLE/own-skills/" 2>/dev/null && echo "  included own-skills/$(basename "$d")"
done
rmdir "$BUNDLE/own-skills" 2>/dev/null || true

cat > "$BUNDLE/MANIFEST.json" <<JSON
{
  "created": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "host": "$(hostname -s)",
  "version": "$(cat "$STATE/version" 2>/dev/null || echo unknown)",
  "note": "Restore with: chewbacca import <this file>"
}
JSON

tar -czf "$OUT" -C "$TMP" chewbacca-export
echo -e "\n${GRN}Wrote${NC} $OUT  ${DIM}($(du -h "$OUT" | cut -f1))${NC}"
echo -e "${DIM}This holds real personal data. Treat it like your keychain.${NC}"

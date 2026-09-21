#!/usr/bin/env bash
# Turn off Serena's dashboard before Serena ever runs.
#
#   seed-serena-config.sh [config-path]
#
# Nothing this kit installs may open a window or a browser tab on somebody's
# machine without being asked. Serena's upstream default does exactly that: it
# starts a web dashboard and opens a browser tab the first time it runs. Sagar
# installed Chewbacca on 2026-09-19, a browser window appeared on his computer
# on its own, and his conclusion was that the kit is dangerous. That is the
# correct conclusion to draw about software that opens windows unannounced, and
# it is fatal for a kit whose install line is `curl | bash`.
#
# Serena writes this file on its first run, so the only way to change the
# default is to get there first. It accepts a partial config and fills the rest
# in itself. An existing file is edited in place, never replaced, because
# everything else in it is the user's.
#
# Extracted from setup.sh so it can be tested. Escaping a shell function out of
# a 2,000-line installer inside a test string does not work, and two tests that
# looked like they were checking this were really checking their own quoting.
set -uo pipefail

CFG="${1:-$HOME/.serena/serena_config.yml}"
KEYS="web_dashboard web_dashboard_open_on_launch gui_log_window"

sedi() {
  if [ "$(uname)" = "Darwin" ]; then sed -i '' "$@"; else sed -i "$@"; fi
}

mkdir -p "$(dirname "$CFG")" 2>/dev/null || exit 0

if [ ! -f "$CFG" ]; then
  cat > "$CFG" <<'SERENA'
# Written by Chewbacca before Serena's first run. Serena fills in every other
# setting itself. These three exist so that installing this kit never makes a
# window appear on your screen that you did not ask for.
web_dashboard: false
web_dashboard_open_on_launch: false
gui_log_window: false
SERENA
  echo changed
  exit 0
fi

changed=0
for key in $KEYS; do
  if grep -qE "^${key}:[[:space:]]*true" "$CFG" 2>/dev/null; then
    sedi "s/^${key}:[[:space:]]*true/${key}: false/" "$CFG"
    changed=1
  elif ! grep -qE "^${key}:" "$CFG" 2>/dev/null; then
    printf '%s: false\n' "$key" >> "$CFG"
    changed=1
  fi
done
[ "$changed" -eq 1 ] && echo changed
exit 0

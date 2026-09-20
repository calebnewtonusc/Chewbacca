#!/bin/bash
# Claude Code -> the terminal loop (docs/superpowers/specs/2026-09-20-terminal-loop-design.md).
#
# Not sourcing lib.sh on purpose: its helpers read stdin, and the event JSON
# on stdin is the whole point here. Hooks run without a login shell, so PATH
# may not have ~/.local/bin; fall back to where setup.sh links chewie.
CHEWIE="$(command -v chewie 2>/dev/null || echo "$HOME/.local/bin/chewie")"
[ -x "$CHEWIE" ] || exit 0
exec "$CHEWIE" terminal hook

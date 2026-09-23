#!/bin/bash
# Claude Code -> the terminal loop.
#
# Not sourcing lib.sh on purpose: its helpers read stdin, and the event JSON
# on stdin is the whole point here. Hooks run without a login shell, so PATH
# may not have ~/.local/bin; fall back to where setup.sh links chewie.
CHEWIE="$(command -v chewie 2>/dev/null || echo "$HOME/.local/bin/chewie")"
[ -x "$CHEWIE" ] || exit 0
# Never exec: a chewie that predates the `terminal` verb answers with an
# argparse error and exit 2, and on a PermissionRequest exit 2 is a blocking
# error that refuses the tool call. Seen on 2026-09-20 when tests/run.sh ran
# this wrapper against ~/.local/bin/chewie linked to an older checkout. The
# error stays on stderr, stdout stays empty, and the tab carries on.
"$CHEWIE" terminal hook
exit 0

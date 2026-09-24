#!/bin/bash
# UserPromptSubmit: Jev's read of the task class, where the keyword router
# is unsure. After 0xNatoshi/jev-codex-router.
#
# claude-model-router-hook sends prompts its keywords cannot place to
# `claude -p --model haiku`, capped at 8 s. Timed 2026-09-24 on two such
# prompts: 9.4 s (past the cap, so no answer at all) and 7.5 s, each blocking
# the prompt the whole time; its cache held two classifications, ever. Jev
# answers the same question well inside this hook's timeout (its accuracy on
# labelled prompts is kept private: TypeSafe's agreement 2.3(f) bars
# publishing Jev performance results). Advice only: the plugin owns the model
# setting and this never writes it.
[ "${MODEL_ROUTE:-on}" = "off" ] && exit 0
TOOL="$(dirname "${BASH_SOURCE[0]}")/../../bin/model-route"
[ -x "$TOOL" ] || TOOL="$(command -v model-route)"
[ -n "$TOOL" ] || exit 0
exec "$TOOL" --hook

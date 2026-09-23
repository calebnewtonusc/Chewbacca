#!/bin/bash
# Timing, logging, a watchdog and an output cap. See lib.sh.
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" 2>/dev/null || true
type hook_init >/dev/null 2>&1 && hook_init design-context.sh 6
# Put the design research in front of the work, at the moment the work starts.
#
# ux-engine holds 18 research files, six stances, a motion constant table, a
# 24-entry effects catalog and 106 psychology principles. On 2026-09-23 a whole
# session of UI work consulted none of it, shipped a page at 3 animations
# against a reference's 214, and its own linter returned clean because the
# linter scores the absence of tells and nothing scored ambition. Caleb: "no
# point of research if it doesn't get implemented."
#
# Two things go in, and only two, because a wall of doctrine is the same as no
# doctrine:
#
#   1. THE AVOID LIST. Features that have actually lost a blind paired
#      comparison in this project, worst first, human overrules counted triple.
#      This is the part that compounds: every judgment recorded makes the next
#      build start better, which is the only mechanism here that improves with
#      time rather than staying the same size.
#
#   2. THE HARD CONSTANTS. The handful of numbers that get violated most, with
#      the ceiling stated. Measured, not preferences.
#
# Everything else stays a lookup, because research/12 is explicit that a
# reference library is not a retrieval store: "It is training data for a
# classifier, and it only works while you are actively judging items against
# each other."
set -uo pipefail

PAYLOAD=$(cat)
command -v jq >/dev/null 2>&1 || exit 0
PROMPT=$(printf '%s' "$PAYLOAD" | jq -r '.prompt // empty')
[ -n "$PROMPT" ] || exit 0

# Only fire on work that actually renders something. A shell-script session
# must not carry the animation rules.
echo "$PROMPT" | grep -qiE 'design|ui|ux|css|animat|scroll|hover|layout|landing|hero|component|page|site|website|gizmo|svg|motion|typograph|spacing|color|colour' || exit 0

ENGINE="$HOME/Desktop/2026-Code/ux-engine"
[ -d "$ENGINE" ] || exit 0

AVOID=""
if [ -x "$ENGINE/bin/ux-trial" ]; then
  AVOID=$(cd "$ENGINE" && ./bin/ux-trial avoid 2>/dev/null | head -14)
fi

# Count what the loop has actually learned, so the reply can be honest about
# how much this is worth. One trial is an anecdote, not a classifier.
TRIALS=0
if [ -f "$ENGINE/trials/log.jsonl" ]; then
  TRIALS=$(wc -l < "$ENGINE/trials/log.jsonl" | tr -d ' ')
fi

CONTEXT=$(cat <<EOF
Design work. The measured constants, and what this project has already learned.

HARD NUMBERS, all measured rather than preferred:
- Stagger: 30-80ms per item, and (n-1)*step must stay under 400ms TOTAL.
  Cap the item count, not the delay. Most violated constant there is.
- Press: 100-160ms, scale(0.97), ease-out. Never ease-in. Press and release
  must not share a duration. Over 200ms at press frequency becomes latency.
- Hover: 50-150ms, and gated behind @media (hover: hover) and (pointer: fine)
  or touch fires a false hover on every tap.
- Scroll reveal: travel 16-32px. 400px is a ride, not a reveal.
- Loops: linear only. An eased loop pulses.
- Generative SVG: 3-12% ink coverage. Over 15% is mud. Hairlines 0.12-0.25
  stroke on a 100-unit viewBox.
- Entrance order follows READING order. Decoration arrives last. Staggering by
  DOM position builds a cascade that fights the reader.
- Not pure black, not pure white. One accent in at most four named places.
  No drop shadows in dark UI: a four-step surface ladder plus 1px hairlines.

BEFORE BUILDING:
- Name the stance and what it refuses (tools/stances.py has six). A page
  committed to none is what reads as derivative.
- research/12: subtraction is not generated as a candidate unless you say so.
  Removal is free and costs nothing. Uncued, people subtract 41% of the time;
  told removal is free, 61%. Try removing something before adding.

AFTER BUILDING, run these rather than assuming:
  ux-crawl <url> --states film,hover,focus,narrow
  ux-film lenses/<name>/film.json        what the motion actually DOES
  ux-compose --effects a,b,c             whether the effects fight each other
  ux-lint <paths>                        generated-look tells

LEARNED IN THIS PROJECT ($TRIALS trial(s) recorded so far):
$AVOID
EOF
)

jq -n --arg c "$CONTEXT" \
  '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $c}}'

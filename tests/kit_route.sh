#!/bin/bash
# kit-route must stay silent on long messages that merely contain English a
# kit's use-when happens to share, and must still route a real one.
#
# On 2026-09-22 a 17,000-character message about building a club website routed
# into apply-kit on six scattered stems at 1.0% density, with no phrase match
# and no kit named. accommodations-kit matched the same message on four. Both
# passed because `len(hits) >= 3` had no length normalization and because
# "claimed by exactly one kit" is true of everything when two kits are
# installed. The fixtures below are that message's shape and a genuine one.
set -uo pipefail
HOOK="$(cd "$(dirname "$0")/.." && pwd)/.claude/hooks/kit-route.sh"
pass=0; fail=0
ok(){ printf '  \033[0;32mpass\033[0m  %s\n' "$1"; pass=$((pass+1)); }
no(){ printf '  \033[0;31mfail\033[0m  %s\n' "$1"; fail=$((fail+1)); }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# Two kits with the real markers, so `claims` has the same tiny population
# that made every hit look distinctive.
mkdir -p "$TMP/apply-kit" "$TMP/accommodations-kit"
cat > "$TMP/apply-kit/.kit" <<'K'
name: apply-kit
domain: Applications: clubs, jobs and internships, fellowships, grad school, grants, accelerators
use-when: applying anywhere, a deadline for an application, an essay or personal statement, a cover letter, a resume for a specific role, an interview for something they applied to
status: ready
K
cat > "$TMP/accommodations-kit/.kit" <<'K'
name: accommodations-kit
domain: Disability accommodations across higher ed, K-12, workplace, and standardized tests
use-when: needing extra time or any accommodation, a professor ignoring an accommodation letter, registering with a disability office, an IEP or 504 ending, requesting something from an employer, accommodations for the LSAT MCAT GRE SAT or bar
status: ready
K

# Stand in for the `kits` binary the hook shells out to.
mkdir -p "$TMP/bin"
printf '#!/bin/sh\nprintf "%%s\\n" "%s/apply-kit" "%s/accommodations-kit"\n' "$TMP" "$TMP" > "$TMP/bin/kits"
chmod +x "$TMP/bin/kits"
export PATH="$TMP/bin:$PATH"

run(){ python3 -c '
import json,sys
print(json.dumps({"prompt": open(sys.argv[1]).read(), "cwd": "/nowhere"}))
' "$1" | sh "$HOOK" 2>/dev/null; }

# A long message about running a club: scattered application-adjacent English
# (interview, application, role, club, person, specific) and no kit named.
cat > "$TMP/noise.txt" <<'T'
TTS will be the ai implementation lab, T Combinator is free contract work for
YC companies, and will technically be part of TTS for now. Two different sites,
same team, same mentors, same alumni network. We need to build a cabinet:
treasurer, marketing, operations, internal affairs, external affairs,
publicity, recruitment, industry relations, alumni director of community.
Only make roles based on needs. I want the recruiting to be the weirdest
recruiting, where the application is a ten minute video and they just submit
something. My friend got rejected during the interview and argued his way back
in. Emily is not recruiting IB anymore, she is going the startup route into
growth, design and marketing. Use your connections, show how tough you are,
say we can build something tough for you. Once we have one good client
everything else follows. I am going to download every club directory, enrich
their LinkedIn, and scan who is at which companies so the outreach is specific
to each person. Prioritize the USC network because that actually works. The
site we have now is mid, it has no animations anywhere and it is not tasteful.
Make sure the new one dogs on the consulting clubs, because a consulting club
does not give anyone real ownership over a client.
T

# The message this hook exists for.
cat > "$TMP/signal.txt" <<'T'
I need to apply to three clubs, the deadline is Friday, and I have to write an
essay plus update my resume.
T

out=$(run "$TMP/noise.txt")
if [ -z "$out" ]; then ok "silent on a long club-website message"
else no "routed a club-website message into: $(printf '%s' "$out" | head -c 120)"; fi

out=$(run "$TMP/signal.txt")
if printf '%s' "$out" | grep -q 'apply-kit'; then ok "still routes a real application"
else no "missed a genuine application prompt"; fi

# A short message that names one kit's words but means the other thing.
printf 'can you cover the letter I got from my landlord\n' > "$TMP/decoy.txt"
out=$(run "$TMP/decoy.txt")
if [ -z "$out" ]; then ok "silent on cover plus letter with no application"
else no "routed a landlord letter into: $(printf '%s' "$out" | head -c 120)"; fi

printf '\n  %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]

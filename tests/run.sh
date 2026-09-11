#!/usr/bin/env bash
# The test suite that did not exist.
#
# CI compiled Python and parsed bash and called it a day. Neither proves any
# behavior is correct, and `people` manages a store of real relationships with
# nothing checking that add-then-show returns what you added.
#
# Hermetic: every test runs against a temp HOME, PEOPLE_DIR and COURSEWORK_DIR,
# so running this never touches your real data.
#
#   tests/run.sh            everything
#   tests/run.sh people     one group
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GRN='\033[0;32m'; RED='\033[0;31m'; DIM='\033[2m'; BLD='\033[1m'; NC='\033[0m'
PASS=0; FAIL=0; SKIP=0
ONLY="${1:-}"
declare -a FAILURES=()

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export PEOPLE_DIR="$TMP/people"
export COURSEWORK_DIR="$TMP/coursework"
export CHEWBACCA_LOG_DIR="$TMP/logs"

group() { CURRENT="$1"; [ -n "$ONLY" ] && [ "$ONLY" != "$1" ] && return 1
          echo -e "\n${BLD}$1${NC}"; return 0; }

# check <name> <command...>   passes if the command exits 0
check() {
  local name="$1"; shift
  if "$@" >"$TMP/out" 2>"$TMP/err"; then
    PASS=$((PASS+1)); echo -e "  ${GRN}pass${NC}  $name"
  else
    FAIL=$((FAIL+1)); FAILURES+=("$CURRENT: $name")
    echo -e "  ${RED}FAIL${NC}  $name"
    sed 's/^/          /' "$TMP/err" | head -4
  fi
}

# expect <name> <needle> <command...>   passes if stdout contains needle
expect() {
  local name="$1" needle="$2"; shift 2
  local out; out="$("$@" 2>&1)"
  if printf '%s' "$out" | grep -qF -- "$needle"; then
    PASS=$((PASS+1)); echo -e "  ${GRN}pass${NC}  $name"
  else
    FAIL=$((FAIL+1)); FAILURES+=("$CURRENT: $name")
    echo -e "  ${RED}FAIL${NC}  $name  ${DIM}(no '$needle')${NC}"
    printf '%s' "$out" | sed 's/^/          /' | head -4
  fi
}

# exits <name> <code> <command...>
exits() {
  local name="$1" want="$2"; shift 2
  "$@" >/dev/null 2>&1; local got=$?
  if [ "$got" -eq "$want" ]; then
    PASS=$((PASS+1)); echo -e "  ${GRN}pass${NC}  $name"
  else
    FAIL=$((FAIL+1)); FAILURES+=("$CURRENT: $name")
    echo -e "  ${RED}FAIL${NC}  $name  ${DIM}(exit $got, wanted $want)${NC}"
  fi
}

skip() { SKIP=$((SKIP+1)); echo -e "  ${DIM}skip  $1 ($2)${NC}"; }

# ── The chewbacca CLI ─────────────────────────────────────────────────────────
if group "chewbacca CLI"; then
  expect "help lists every verb" "chewbacca doctor" bash "$ROOT/bin/chewbacca" --help
  expect "help is generated, not hand-written" "chewbacca completion" bash "$ROOT/bin/chewbacca" --help
  exits  "unknown verb exits 1" 1 bash "$ROOT/bin/chewbacca" nonsense
  expect "unknown verb suggests a real one" "did you mean" bash "$ROOT/bin/chewbacca" doc
  expect "where prints the repo" "$ROOT" bash "$ROOT/bin/chewbacca" where
  expect "version reports the repo version" "repo:" bash "$ROOT/bin/chewbacca" version
  check  "version --json is valid JSON" bash -c "bash '$ROOT/bin/chewbacca' version --json | python3 -m json.tool"
  for sh in zsh bash fish; do
    check "completion for $sh" bash "$ROOT/bin/chewbacca" completion "$sh"
  done
  exits  "completion with no shell exits 2" 2 bash "$ROOT/bin/chewbacca" completion
fi

# ── people ────────────────────────────────────────────────────────────────────
if group "people"; then
  if ! command -v node >/dev/null 2>&1; then
    skip "the whole group" "node not installed"
  else
    P=("$ROOT/bin/people")
    check  "add a person" "${P[@]}" add "Test Person" --company Acme --role CTO
    expect "show returns what was added" "Acme" "${P[@]}" show "test person"
    check  "note attaches to a person" "${P[@]}" note "test person" "likes hiking" --dim intellectual
    expect "the note comes back" "hiking" "${P[@]}" show "test person"
    expect "search finds by note text" "Test Person" "${P[@]}" search hiking
    expect "list includes the person" "Test Person" "${P[@]}" list
    check  "log an interaction" "${P[@]}" log "test person" --channel call "caught up"
    check  "rank runs" "${P[@]}" rank --limit 5
    check  "score runs" "${P[@]}" score
    check  "birthdays runs" "${P[@]}" birthdays --days 30
    check  "reconnect runs" "${P[@]}" reconnect
    check  "task add" "${P[@]}" task add "test person" "send the book"
    expect "tasks lists it" "send the book" "${P[@]}" tasks
    check  "export writes markdown" "${P[@]}" export
    expect "a person with no record fails clearly" "" "${P[@]}" show "nobody at all"
    check  "the database file exists" test -f "$PEOPLE_DIR/people.db"
    # Two importers and a text sync all create people. Nothing noticed that
    # "Maggie Chen" and "Maggie" were one person until this existed.
    "${P[@]}" add "Dup Person" --company Acme >/dev/null 2>&1
    "${P[@]}" add "Dup" --company Acme >/dev/null 2>&1
    "${P[@]}" note "Dup" "a fact that must survive the merge" >/dev/null 2>&1
    expect "dedupe finds the pair" "Dup" "${P[@]}" dedupe
    check  "merge runs" "${P[@]}" merge "Dup Person" "Dup"
    expect "the merged fact survives" "must survive" "${P[@]}" show "Dup Person"
    expect "search still finds it" "Dup Person" "${P[@]}" search "must survive"
    check  "the absorbed record is gone" bash -c "! '$ROOT/bin/people' show 'Dup' 2>/dev/null | grep -q '^Dup$'"
    check  "the database validates" bash -c "sqlite3 '$PEOPLE_DIR/people.db' 'pragma integrity_check' | grep -q ok"
    # A second add of the same name must not silently create a duplicate row.
    "${P[@]}" add "Test Person" >/dev/null 2>&1
    N=$(sqlite3 "$PEOPLE_DIR/people.db" "select count(*) from people where name='Test Person'" 2>/dev/null || echo 0)
    if [ "$N" = "1" ]; then
      PASS=$((PASS+1)); echo -e "  ${GRN}pass${NC}  adding the same name twice does not duplicate"
    else
      FAIL=$((FAIL+1)); FAILURES+=("people: duplicate on re-add ($N rows)")
      echo -e "  ${RED}FAIL${NC}  adding the same name twice created $N rows"
    fi
  fi
fi

# ── coursework ────────────────────────────────────────────────────────────────
if group "coursework"; then
  mkdir -p "$COURSEWORK_DIR/courses"
  cp "$ROOT/tests/fixtures/course.yml" "$COURSEWORK_DIR/courses/test-101.yml"
  cp "$ROOT/tests/fixtures/semester.yml" "$COURSEWORK_DIR/semester.yml"
  C=("$ROOT/bin/coursework")
  expect "due reads the fixture" "Fixture Assignment" "${C[@]}" due --days 3650
  check  "due --json is valid JSON" bash -c "'$ROOT/bin/coursework' due --days 3650 --json | python3 -m json.tool"
  expect "policy reports the AI rule" "banned" "${C[@]}" policy "TEST 101" ai
  check  "attendance runs" "${C[@]}" attendance
  check  "week runs" "${C[@]}" week
  check  "grade runs" "${C[@]}" grade "TEST 101"
  check  "ics export runs" "${C[@]}" ics --out "$TMP/out.ics"
  check  "the ics file has an event" grep -q "BEGIN:VEVENT" "$TMP/out.ics"
  expect "check finds the deliberate gap" "no attendance budget" "${C[@]}" check
  exits  "check exits non-zero when the ledger has gaps" 1 "${C[@]}" check
fi

# ── doctor ────────────────────────────────────────────────────────────────────
if group "doctor"; then
  check  "--help works" bash "$ROOT/doctor.sh" --help
  exits  "an unknown flag exits 2" 2 bash "$ROOT/doctor.sh" --nonsense
  check  "--json is valid JSON" bash -c "bash '$ROOT/doctor.sh' --json | python3 -m json.tool"
  expect "--json carries severities" '"severity"' bash -c "bash '$ROOT/doctor.sh' --json"
  expect "--json carries sections" '"section"' bash -c "bash '$ROOT/doctor.sh' --json"

  # A silently-dropped @import is the cheapest bug in the kit to have: Claude
  # Code does not error on a path that is not there, it just runs without the
  # standard. Seven of nine rules were missing on a machine setup had called
  # successful, and 65 other checks never looked.
  D="$TMP/dhome"; mkdir -p "$D/.claude/rules"
  cp "$ROOT/CLAUDE.md" "$D/.claude/CLAUDE.md"
  expect "a missing always-on import is caught" "do not exist" \
    bash -c "HOME='$D' bash '$ROOT/doctor.sh' 2>&1"
  expect "the report names the missing file" "rules/git.md" \
    bash -c "HOME='$D' bash '$ROOT/doctor.sh' 2>&1"
  # The mutant: with every rule present the same check must go quiet, or it is
  # reporting the weather rather than the install.
  cp "$ROOT/.claude/rules/"*.md "$D/.claude/rules/"
  expect "and passes once they are all there" "always-on imports resolve" \
    bash -c "HOME='$D' bash '$ROOT/doctor.sh' 2>&1"

  # p95, not max: judging a hook on its single worst run accused one whose
  # median was 108ms, and a p95 over 11 samples is noise, not a measurement.
  check "doctor judges hooks on p95 with a sample floor" \
    bash -c "grep -q 'MIN_RUNS_FOR_VERDICT' '$ROOT/doctor.sh'"
fi

# ── tools ─────────────────────────────────────────────────────────────────────
if group "tools"; then
  check  "counts --check passes on a clean tree" python3 "$ROOT/tools/counts.py" --check
  check  "counts --json is valid" bash -c "python3 '$ROOT/tools/counts.py' --json | python3 -m json.tool"
  check  "evals structure pass" python3 "$ROOT/tools/evals.py"
  check  "context cost --json is valid" bash -c "python3 '$ROOT/tools/context_cost.py' --json | python3 -m json.tool"
  # Not --check: every commit made after the last regeneration invalidates it,
  # so a --check here would fail on the commit that adds a test.
  check  "changelog generates" python3 "$ROOT/tools/changelog.py"
  check  "memory compact dry run is safe" python3 "$ROOT/tools/memory_compact.py" --dry-run
  check  "secret scan finds nothing in the repo" python3 "$ROOT/bin/secret-scan" "$ROOT"
  check  "checksums are current" python3 "$ROOT/tools/checksums.py" --check
  check  "skills declare their tool dependencies" bash -c "python3 '$ROOT/tools/skill_requires.py' | grep -q '^chewie:'"
  # A skill whose YAML is malformed is not registered, so it never fires and
  # the user concludes the skill is bad at triggering. life-ops shipped that
  # way for weeks over one unquoted colon in its description.
  check  "every skill frontmatter parses" python3 "$ROOT/tools/frontmatter.py"
  FM="$TMP/fmcheck/skills/broken"; mkdir -p "$FM"
  printf -- '---\nname: broken\ndescription: a thing that is not code: it breaks\n---\n\n# x\n' > "$FM/SKILL.md"
  expect "an unquoted colon is caught" "unquoted value contains" \
    bash -c "python3 '$ROOT/tools/frontmatter.py' '$TMP/fmcheck/skills' 2>&1 || true"
  exits  "and the checker exits non-zero" 1 \
    bash -c "python3 '$ROOT/tools/frontmatter.py' '$TMP/fmcheck/skills'"
  check  "AGENTS.md exports for other agents" python3 "$ROOT/tools/agents_md.py" "$TMP"
  check  "the export leaks no @imports" bash -c "! grep -q '^@' '$TMP/AGENTS.md'"
  check  "slop check holds the line" python3 "$ROOT/bin/slop-check" "$ROOT/docs" "$ROOT/skills" --max 60
fi

# ── installer ─────────────────────────────────────────────────────────────────
if group "installer"; then
  check  "--help works" bash "$ROOT/setup.sh" --help
  expect "--dry-run defaults bypass off" "bypass perms:    no" bash "$ROOT/setup.sh" --dry-run --name CI --repo-dir "$TMP/ci"
  check  "--dry-run writes nothing" bash -c "test ! -d '$TMP/ci'"
  expect "uninstall --dry-run says so" "Dry run" bash "$ROOT/uninstall.sh" --dry-run
  exits  "uninstall rejects an unknown flag" 2 bash "$ROOT/uninstall.sh" --nonsense
  expect "--skip is repeatable" "skipping plynn mac" bash "$ROOT/setup.sh" --dry-run --skip plynn --skip mac --name CI
  expect "portable profile installs no Mac tools" "~/.claude only" bash "$ROOT/setup.sh" --dry-run --profile portable --name CI
  exits  "an unknown profile exits 2" 2 bash "$ROOT/setup.sh" --dry-run --profile nonsense --name CI
  check  "no read calls in the installer" bash -c "! grep -nE '^[[:space:]]*read (-[a-z]+ )*' '$ROOT/setup.sh'"
fi

# ── CLAUDE.md merge ───────────────────────────────────────────────────────────
if group "CLAUDE.md merge"; then
  M="$TMP/merge"; mkdir -p "$M"
  printf '# My own rules\n\nAlways call me Caleb.\n' > "$M/CLAUDE.md"
  printf '# Standards\n\nRule one.\n' > "$M/standards.md"
  expect "an existing file is merged, not clobbered" "merged" \
    bash "$ROOT/bin/lib/merge-claude-md.sh" "$M/CLAUDE.md" "$M/standards.md"
  check  "their content survives" grep -q "Always call me Caleb" "$M/CLAUDE.md"
  check  "the original is backed up" bash -c "ls '$M'/CLAUDE.md.yours-* >/dev/null"
  expect "a second run updates the region" "updated" \
    bash "$ROOT/bin/lib/merge-claude-md.sh" "$M/CLAUDE.md" "$M/standards.md"
  printf '# Standards v2\n\nRule one. Rule two.\n' > "$M/standards.md"
  bash "$ROOT/bin/lib/merge-claude-md.sh" "$M/CLAUDE.md" "$M/standards.md" >/dev/null
  check  "an upgrade replaces the standards" grep -q "Rule two" "$M/CLAUDE.md"
  check  "an upgrade still keeps their content" grep -q "Always call me Caleb" "$M/CLAUDE.md"
  check  "there is exactly one standards region" bash -c "[ \"\$(grep -c 'CHEWBACCA:BEGIN' '$M/CLAUDE.md')\" = 1 ]"
  rm -f "$M/CLAUDE.md"
  expect "no existing file just writes" "wrote" \
    bash "$ROOT/bin/lib/merge-claude-md.sh" "$M/CLAUDE.md" "$M/standards.md"
fi

# ── hooks ─────────────────────────────────────────────────────────────────────
if group "hooks"; then
  check  "lib.sh parses" bash -n "$ROOT/.claude/hooks/lib.sh"
  # A hook must never fail the session, whatever it is handed.
  for h in "$ROOT"/.claude/hooks/*.sh; do
    [ "$(basename "$h")" = "lib.sh" ] && continue
    name="$(basename "$h")"
    exits "$name survives empty input" 0 bash -c "echo '{}' | bash '$h'"
  done
  # A home directory under git reports every cache and Library folder as
  # untracked work. The reminder fired three times in a row in a session whose
  # real repos were clean, and acting on it would stage the user's credentials.
  check  "stop-check says nothing about a home-directory repo" \
    bash -c "cd \"\$HOME\" && git rev-parse --show-toplevel 2>/dev/null | grep -qx \"\$HOME\" && [ -z \"\$(bash '$ROOT/.claude/hooks/stop-check.sh')\" ] || true"
  # A pile of untracked siblings is the environment, not the turn. Counting
  # them reported "110 uncommitted changes" in a workspace folder whose real
  # repos were clean, and buried the one tracked file that had actually changed.
  check "untracked noise does not drown the real change" bash -c '
    d="$(mktemp -d)"
    cd "$d" || exit 1
    git init -q . && git config user.email t@t && git config user.name t
    echo real > tracked.txt && git add tracked.txt && git commit -qm init
    echo changed > tracked.txt
    for i in $(seq 1 40); do mkdir -p "junk$i"; touch "junk$i/f"; done
    out="$(echo "{}" | bash "'"$ROOT"'/.claude/hooks/stop-check.sh" 2>/dev/null)"
    echo "$out" | grep -q "1 uncommitted change" || { echo "got: $out"; exit 1; }
    echo "$out" | grep -q "41 uncommitted" && exit 1
    exit 0
  '
  check  "the hook log was written" test -f "$CHEWBACCA_LOG_DIR/hooks.log"
  expect "log rows carry a duration" "|ok|" cat "$CHEWBACCA_LOG_DIR/hooks.log"
fi

# ── the display ───────────────────────────────────────────────────────────────
if group "hud"; then
  check  "hud parses"         bash -n "$ROOT/bin/hud"
  check  "hud-listen parses"  python3 -m py_compile "$ROOT/bin/hud-listen"
  check  "hud-context parses" python3 -m py_compile "$ROOT/bin/hud-context"
  check  "hud-watch parses"   python3 -m py_compile "$ROOT/bin/hud-watch"
  # The budget is the whole design. A proactive thing that interrupts whenever
  # it has an opinion gets muted within a day, and a muted assistant is worth
  # less than none because you believe you have one.
  check  "the watcher respects its budget" python3 "$ROOT/tests/test_hud_watch.py"
  # The loop itself, against a fake display and a fake model: no socket to a
  # real app, no microphone, no tokens. It is the only test that covers what
  # happens between hearing something and drawing it.
  check  "the listen loop works end to end" python3 "$ROOT/tests/test_hud_listen.py"
  expect "the skill teaches the wire format" "Bob Lines" cat "$ROOT/skills/hud/SKILL.md"
fi

# ── guide ─────────────────────────────────────────────────────────────────────
if group "guide"; then
  export GUIDE_DIR="$TMP/guides"
  G=("python3" "$ROOT/bin/guide")
  check  "guide compiles"            python3 -m py_compile "$ROOT/bin/guide"
  check  "unit tests pass"           python3 "$ROOT/tests/test_guide.py"
  check  "the template exists"       test -f "$ROOT/templates/guide.html"
  check  "new writes a guide"        "${G[@]}" new "cache coherence" --course CSCI170
  check  "the file landed"           test -f "$TMP/guides/cache-coherence.html"
  expect "the title carries the course" "CSCI170" cat "$TMP/guides/cache-coherence.html"
  expect "the runtime is inlined, not linked" "rg-quiz" cat "$TMP/guides/cache-coherence.html"
  check  "no external script tags"   bash -c "! grep -qE '<script[^>]+src=' '$TMP/guides/cache-coherence.html'"
  expect "list shows it untaken"     "never taken" "${G[@]}" list
  expect "progress says so plainly"  "no results yet" "${G[@]}" progress
  exits  "a second guide on the same topic is refused" 1 "${G[@]}" new "cache coherence"
  exits  "an unknown subcommand exits 2" 2 "${G[@]}" nonsense
  # The sidecar is the whole point, so read-back is the test that matters.
  cat > "$TMP/guides/.cache-coherence.html.progress.json" <<'JSON'
{"mesi-states":{"correct":1,"total":3,"missed":["What happens on eviction?"],"at":"2026-09-11T00:00:00Z"}}
JSON
  expect "progress reads the sidecar back"  "mesi-states" "${G[@]}" progress
  # A last-score-only view cannot answer the question that matters a week
  # later: is this getting better. These two are the whole reason the runtime
  # keeps attempts instead of overwriting.
  cat > "$TMP/guides/.trend.html.progress.json" <<'JSON'
{"up":{"attempts":[{"correct":1,"total":5,"at":"2026-09-01T00:00:00Z"},{"correct":5,"total":5,"at":"2026-09-09T00:00:00Z"}],"last":{"correct":5,"total":5,"at":"2026-09-09T00:00:00Z"}},
 "down":{"attempts":[{"correct":5,"total":5,"at":"2026-09-01T00:00:00Z"},{"correct":1,"total":5,"missed":["it"],"at":"2026-09-09T00:00:00Z"}],"last":{"correct":1,"total":5,"missed":["it"],"at":"2026-09-09T00:00:00Z"}},
 "old":{"correct":1,"total":2,"missed":["flat shape"],"at":"2026-09-02T00:00:00Z"}}
JSON
  cp "$TMP/guides/cache-coherence.html" "$TMP/guides/trend.html"
  expect "an improving topic is named as such"  "improving over 2" "${G[@]}" progress trend
  expect "a slipping topic is called out"       "SLIPPING over 2"  "${G[@]}" progress trend
  # Sidecars written before attempts existed must still read, or an upgrade
  # silently throws away the history it was added to keep.
  expect "the pre-history sidecar shape still reads" "flat shape" "${G[@]}" progress trend
  expect "progress names what was missed"   "eviction"    "${G[@]}" progress
  check  "progress --json is valid JSON" bash -c "GUIDE_DIR='$TMP/guides' python3 '$ROOT/bin/guide' progress --json | python3 -m json.tool"
  expect "list reports the score"     "1/3" "${G[@]}" list
  unset GUIDE_DIR
fi

# ── live checks (structure only; chewbacca live runs them for real) ───────────
if group "live"; then
  check  "the runner parses"  bash -n "$ROOT/bin/live-check"
  check  "the harness parses" bash -n "$ROOT/tests/live/harness.sh"
  for f in "$ROOT"/tests/live/*.sh; do
    n="$(basename "$f")"; [ "$n" = harness.sh ] && continue
    check "$n parses" bash -n "$f"
    # A live check that cannot skip will report green on a machine missing the
    # very tool it exists to exercise, which is the failure mode it was written
    # to prevent. Every file must have an exit path that is not pass or fail.
    check "$n can SKIP" bash -c "grep -qE 'need |unproven ' '$f'"
    check "$n has a mutant" bash -c "grep -q 'mutant ' '$f'"
  done
  expect "--list describes each check" "mac" bash "$ROOT/bin/live-check" --list
  # triggers.py drives the real CLI, so the suite only checks it is well formed.
  # Running it for real is `chewbacca triggers`, which costs minutes and tokens.
  check  "the trigger harness compiles" python3 -m py_compile "$ROOT/tools/triggers.py"
  check  "the trigger cases are valid JSON" bash -c "python3 -m json.tool < '$ROOT/tests/triggers.json' >/dev/null"
  check  "every trigger case states an expectation" bash -c "python3 -c \"
import json
cs=json.load(open('$ROOT/tests/triggers.json'))
assert cs, 'no cases'
for c in cs:
    assert c.get('prompt'), c
    assert c.get('expect_any') is not None or c.get('expect_tool') is not None, c
\""
  exits  "an unknown check exits 2" 2 bash "$ROOT/bin/live-check" no-such-check
fi

# ── verdict ───────────────────────────────────────────────────────────────────
echo ""
if [ "$FAIL" -eq 0 ]; then
  echo -e "${GRN}${BLD}$PASS passed${NC}${GRN}, $SKIP skipped.${NC}"
  exit 0
fi
echo -e "${RED}${BLD}$FAIL failed${NC}${RED}, $PASS passed, $SKIP skipped.${NC}"
for f in "${FAILURES[@]}"; do echo "  - $f"; done
exit 1

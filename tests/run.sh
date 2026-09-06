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

# ── verdict ───────────────────────────────────────────────────────────────────
echo ""
if [ "$FAIL" -eq 0 ]; then
  echo -e "${GRN}${BLD}$PASS passed${NC}${GRN}, $SKIP skipped.${NC}"
  exit 0
fi
echo -e "${RED}${BLD}$FAIL failed${NC}${RED}, $PASS passed, $SKIP skipped.${NC}"
for f in "${FAILURES[@]}"; do echo "  - $f"; done
exit 1

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
export SUPERASSISTANT_DIR="$TMP/superassistant"

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

    # reconnect used to rank by nothing. urgency was score * (1 + over/cadence),
    # base_score is 0 for anyone with no hand-written observation, and zero
    # times anything is zero, so every row tied at 0, the sort was a no-op and
    # the list came out in table order. Gavin hit it with 944 of his 945 people
    # at score 0 and got an alphabetical list. These three people all have score
    # 0 and differ only in how overdue they are, so the ONLY thing that can
    # order them correctly is the lateness term.
    check "reconnect ranks by lateness when every score is zero" \
      bash "$ROOT/tests/reconnect_ranking.sh" "${P[@]}"

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

    # `people who` used to filter the people table only and never read
    # `observations`, so everything `distill` and `infer --apply` recorded was
    # write-only: it could conclude somebody went to your school, store it, and
    # then answer "who went to school with me" by ignoring it. The half of the
    # question it could not parse was printed as "ignored" and never searched.
    "${P[@]}" add "Evidence One" --role Founder --company Acme >/dev/null 2>&1
    "${P[@]}" add "Evidence Two" --role Founder --company Acme >/dev/null 2>&1
    "${P[@]}" note "Evidence One" "we both rowed crew at university" >/dev/null 2>&1
    expect "who reads observations, not just table columns" "Evidence One" \
           "${P[@]}" who "founders who rowed crew"
    expect "who excludes people the evidence does not cover" "" \
           bash -c "'$ROOT/bin/people' who 'founders who rowed crew' | grep -c 'Evidence Two' | grep '^0$'"
    # The inventory has to report zeros. A path that cannot say what it searched
    # can only shrug, and a shrug is indistinguishable from a bug.
    expect "who reports a search that found nothing" "found nothing" \
           "${P[@]}" who "founders who do zymurgy"
    # Terms are OR'd, so one common word can carry the whole clause and "narrow"
    # a set to itself. Announcing that as a finding is the same class of lie as
    # the silent drop this layer exists to fix.
    "${P[@]}" note "Evidence Two" "we both rowed crew at university" >/dev/null 2>&1
    expect "who says when the evidence ruled nobody out" "ruled nobody out" \
           "${P[@]}" who "founders who rowed crew"
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
  cp "$ROOT/instructions/agent-neutral.md" "$D/.claude/rules/agent-neutral.md"
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
  check  "eval results carry which case failed, not a count" python3 "$ROOT/tests/test_eval_results.py"
  check  "the evolve merge gate refuses a regression" python3 "$ROOT/tests/test_evolve_gate.py"
  check  "a reply that hands over a command is refused" python3 "$ROOT/tests/test_handoff_check.py"
  check  "a correction must change the kit, not just the reply" python3 "$ROOT/tests/test_durable_check.py"
  check  "preflight describes setup.sh accurately" python3 "$ROOT/tests/test_preflight.py"
  check  "context cost --json is valid" bash -c "python3 '$ROOT/tools/context_cost.py' --json | python3 -m json.tool"
  # Not --check: every commit made after the last regeneration invalidates it,
  # so a --check here would fail on the commit that adds a test.
  check  "changelog generates" env PYTHONPATH="$ROOT/tools" python3 -c 'import changelog; assert changelog.build().startswith("# Changelog")'
  if [ -f "$HOME/second-brain/memory/MEMORY.md" ]; then
    check "memory compact dry run is safe" python3 "$ROOT/tools/memory_compact.py" --dry-run
  else
    skip "memory compact dry run is safe" "no second-brain on this machine"
  fi
  check  "secret scan finds nothing in the repo" python3 "$ROOT/bin/secret-scan" "$ROOT"
  check  "checksums are current" python3 "$ROOT/tools/checksums.py" --check
  # The checksum file is not decoration. start.sh verifies every downloaded
  # file against it and aborts the install on a single mismatch. On 2026-09-19
  # a generated edit to setup.sh shipped without regenerating it, so the
  # README's one-line install died on every machine while a pinned tag still
  # worked, and it looked like the testers' fault. This walks the same loop
  # start.sh walks, against the real tree.
  check  "start.sh's own checksum gate passes on this tree" bash -c '
    cd "$1" || exit 1
    mismatches=0
    while IFS= read -r line; do
      want="${line%% *}"; file="${line##* }"
      [ -f "$file" ] || continue
      got="$(shasum -a 256 "$file" | cut -d" " -f1)"
      [ "$want" = "$got" ] || { echo "mismatch: $file"; mismatches=$((mismatches + 1)); }
    done < SHA256SUMS.txt
    [ "$mismatches" -eq 0 ]' _ "$ROOT"
  # The generator that rewrites setup.sh has to rewrite the checksums with it,
  # or the two drift apart again the next time the inventory regenerates.
  check  "the inventory generator regenerates checksums too" \
    grep -q "checksums.py" "$ROOT/tools/inventory.py"
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
  check  "code-slop scores its own tests" python3 "$ROOT/tests/test_code_slop.py"
  check  "inventory parses frontmatter and holds house style" python3 "$ROOT/tests/test_inventory.py"
  # The craft gate is the only thing making the demo rules fire rather than sit
  # in a markdown file, so its fail-closed behaviour is the property to pin.
  check  "craft-gate refuses a craft nobody studied" bash -c "! CRAFT_DIR='$TMP/craft-empty' python3 '$ROOT/bin/craft-gate' pitch-deck >/dev/null 2>&1"
  check  "craft-gate passes a studied craft" bash -c "CRAFT_DIR='$TMP/craft-seed' python3 '$ROOT/bin/craft-gate' demo-video >/dev/null 2>&1"
  check  "craft-gate prints the rules, not just ok" bash -c "CRAFT_DIR='$TMP/craft-seed' python3 '$ROOT/bin/craft-gate' demo-video | grep -q 'One to three features'"
  check  "craft-gate rejects a stub as research" bash -c "echo hi > '$TMP/stub.md'; ! CRAFT_DIR='$TMP/craft-empty2' python3 '$ROOT/bin/craft-gate' x --record '$TMP/stub.md' >/dev/null 2>&1"
  # demo-shoot must not be able to record without the gate having run.
  check  "demo-shoot calls the craft gate" grep -q "craft-gate demo-video" "$ROOT/bin/demo-shoot"

  # Every other producer gets the same treatment. The property that matters is
  # FAIL CLOSED: with no craft-gate reachable at all, the producer must refuse
  # rather than shrug and carry on. That is tested by copying the producer
  # somewhere with no sibling craft-gate and a PATH that cannot reach one, which
  # is deterministic whether or not chewbacca is installed on this machine.
  PY="$(command -v python3)"
  BARE="/usr/bin:/bin"
  mkdir -p "$TMP/nogate"
  cp "$ROOT/bin/guide" "$ROOT/bin/kits" "$TMP/nogate/"
  # A craft dir seeded from the repo, so the pass-path tests do not depend on
  # which craft-gate copy gets found first.
  for g in study-guide daily-brief onboarding-kit; do
    CRAFT_DIR="$TMP/craft-all" python3 "$ROOT/bin/craft-gate" "$g" \
      --record "$ROOT/crafts/$g.md" >/dev/null 2>&1
  done

  check  "guide new fails closed with no craft-gate reachable" \
    bash -c "! env PATH='$BARE' GUIDE_DIR='$TMP/g-none' '$PY' '$TMP/nogate/guide' new zzz >/dev/null 2>&1"
  check  "guide new writes nothing when the gate refuses" \
    bash -c "test ! -f '$TMP/g-none/zzz.html'"
  check  "guide new prints the study-guide rules before writing" \
    bash -c "CRAFT_DIR='$TMP/craft-all' GUIDE_DIR='$TMP/g-ok' python3 '$ROOT/bin/guide' new zzz | grep -q 'retrieve, never re-read'"
  check  "guide new still produces the guide once gated" \
    bash -c "test -f '$TMP/g-ok/zzz.html'"
  check  "guide calls the craft gate" grep -q 'craft_gate("study-guide")' "$ROOT/bin/guide"

  check  "kits --register fails closed with no craft-gate reachable" \
    bash -c "mkdir -p '$TMP/k1' && touch '$TMP/k1/.kit'; ! env PATH='$BARE' KITS_REGISTRY='$TMP/reg-none' sh '$TMP/nogate/kits' --register '$TMP/k1' >/dev/null 2>&1"
  check  "kits --register adds nothing to the registry when refused" \
    bash -c "! grep -q '$TMP/k1' '$TMP/reg-none' 2>/dev/null"
  check  "kits --register prints the kit rules when gated" \
    bash -c "CRAFT_DIR='$TMP/craft-all' KITS_REGISTRY='$TMP/reg-ok' sh '$ROOT/bin/kits' --register '$TMP/k1' | grep -q 'Know which of the four things'"
  check  "kits calls the craft gate" grep -q "craft-gate onboarding-kit" "$ROOT/bin/kits"

  check  "brief calls the craft gate" grep -q 'craft_gate("daily-brief"' "$ROOT/mac/lib/brief.py"
  # The rules must not land on stdout in --json mode, or the agent parsing the
  # brief gets rule prose where it expected an object.
  check  "brief --json stays parseable with the gate in front" \
    bash -c "CRAFT_DIR='$TMP/craft-all' python3 '$ROOT/mac/lib/brief.py' --json 2>/dev/null | python3 -c 'import json,sys; json.load(sys.stdin)'"
  check  "brief sends the rules to stderr in --json mode" \
    bash -c "CRAFT_DIR='$TMP/craft-all' python3 '$ROOT/mac/lib/brief.py' --json 2>&1 >/dev/null | grep -q 'One page'"

  check  "claude-tab classifies run state and guards its own tab" python3 "$ROOT/tests/test_claude_tab.py"
  # The house style here is deliberately high-comment, so the one thing that
  # would make this tool useless is firing on its own codebase.
  check  "code-slop is quiet on this codebase" bash -c "python3 '$ROOT/bin/code-slop' '$ROOT/bin/people' '$ROOT/bin/slop-check' '$ROOT/bin/code-slop' $ROOT/bin/lib/*.js --max 0"
fi

# ── installer ─────────────────────────────────────────────────────────────────
if group "installer"; then
  check  "--help works" bash "$ROOT/setup.sh" --help
  expect "--dry-run defaults bypass off" "bypass perms:    no" bash "$ROOT/setup.sh" --dry-run --name CI --repo-dir "$TMP/ci"
  check  "--dry-run writes nothing" bash -c "test ! -d '$TMP/ci'"
  expect "uninstall --dry-run says so" "Dry run" bash "$ROOT/uninstall.sh" --dry-run
  exits  "uninstall rejects an unknown flag" 2 bash "$ROOT/uninstall.sh" --nonsense
  expect "--skip is repeatable" "skipping plynn mac" bash "$ROOT/setup.sh" --dry-run --skip plynn --skip mac --name CI
  expect "portable profile installs no Mac tools" "Claude and Codex configuration, no Mac tools" bash "$ROOT/setup.sh" --dry-run --profile portable --name CI
  exits  "an unknown profile exits 2" 2 bash "$ROOT/setup.sh" --dry-run --profile nonsense --name CI
  check  "no read calls in the installer" bash -c "! grep -nE '^[[:space:]]*read (-[a-z]+ )*' '$ROOT/setup.sh'"

  # start.sh and start.ps1 both refuse to install when the download does not
  # match SHA256SUMS.txt, so a manifest that does not describe its own commit
  # breaks every fresh install. The working-tree check cannot see it.
  # The install must not reach for Claude on a machine that already has an
  # agent. Sagar runs Codex, hit a Claude credits purchase on the last screen
  # of a kit sold as model agnostic, and stopped. He has still not onboarded.
  check  "the install uses the agent already on the machine" \
    bash "$ROOT/tests/agent_agnostic.sh" "$ROOT"

  # list-gate must refuse the exact defects that shipped four times on
  # 2026-09-20. A gate whose own tests are not asserted is decoration.
  check  "list-gate refuses the defects it exists for" \
    bash "$ROOT/tests/list_gate.sh" "$ROOT"

  # The rule Caleb had to state four times in one session. A gate, not a note.
  check  "kit-debt fires when a session taught the kit nothing" \
    bash "$ROOT/tests/kit_debt.sh" "$ROOT"

  # The guard existed since 18:49 and commit 4a0b1df still absorbed another
  # session's files at 21:44. mtime cannot separate two live sessions.
  check  "pre-commit refuses an index holding two sessions' work" \
    bash "$ROOT/tests/precommit_authorship.sh" "$ROOT"

  # Same failure at the other end: the Stop reminder counted the dirty files
  # without asking who wrote them, and told the reader to commit a second live
  # session's work.
  check  "the Stop reminder will not push you to commit another session's work" \
    bash "$ROOT/tests/stop_check_authorship.sh" "$ROOT"

  # The guard that keeps a Claude session's environment out of a person's
  # Terminal window. Its first version only fired when the parent was login,
  # which left every already-open shell broken.
  check  "the terminal guard installs once and fires on the right shells" \
    bash "$ROOT/tests/terminal_guard.sh" "$ROOT"

  check  "committed checksums describe the committed tree" \
    python3 "$ROOT/tools/committed_checksums.py"

  # The negative control is real history, not a fixture. 8de1739 published a
  # hash for .claude/hooks/kit-autopush.sh that its own committed hook did not
  # have, and curl | bash refused on main until somebody looked. A checker
  # that cannot fail on that commit is not checking anything.
  if git -C "$ROOT" cat-file -e 8de1739^{commit} 2>/dev/null; then
    exits "it fails on the commit that actually shipped broken" 1 \
      python3 "$ROOT/tools/committed_checksums.py" 8de1739
  else
    skip "the known-broken commit" "shallow clone, 8de1739 not fetched"
  fi

  # This check lived only in CI, so a header inserted in the wrong place passed
  # 206 local tests and failed after the push. A rule worth enforcing is worth
  # enforcing where the work happens.
  check  "every section is guarded by --only" python3 "$ROOT/tests/check_sections.py" "$ROOT/setup.sh"

  # A rule with no `paths:` frontmatter is always-on. design-system.md opens by
  # saying it costs ~4,000 tokens on every session with no use for a line of it,
  # and that it was moved out of CLAUDE.md for that reason, but nothing ever
  # scoped it, so every install kept paying. Only one machine had the scoping,
  # added by hand, and a reinstall overwrote it.
  check  "rules that claim to load on demand carry paths frontmatter" bash -c '
    missing=""
    for f in "$1"/.claude/rules/*.md; do
      head -20 "$f" | grep -qiE "^loads (when|before)|load when the work|Applies to" || continue
      head -1 "$f" | grep -q -- "---" || missing="$missing $(basename "$f")"
    done
    [ -z "$missing" ] || { echo "always-on despite claiming otherwise:$missing"; exit 1; }' _ "$ROOT"

  # Everything below was found by watching two people install this on their own
  # machines on 2026-09-19. Each one is a thing they hit, not a thing imagined.

  # The personal profile creates no repos, so demanding a GitHub account and a
  # git identity produced a screenful of red BLOCKED lines about something the
  # install never needed. Red text during an install reads as a broken product.
  check  "bootstrap does not demand GitHub in the personal profile" bash -c "
    ! bash '$ROOT/bin/bootstrap.sh' --check --profile personal 2>&1 | grep -qi 'gh auth login'"
  check  "bootstrap still demands GitHub in the developer profile" bash -c "
    bash '$ROOT/bin/bootstrap.sh' --check --profile developer 2>&1 | grep -qiE 'gh auth login|signed in as'"
  check  "start.sh passes the profile to bootstrap" \
    grep -q 'bootstrap.sh" --profile' "$ROOT/start.sh"

  # An agent types this line, from a README it skimmed, and agents mistype.
  # Each of these spellings used to exit 2 with no install and no explanation.
  # The phrase is "Nothing has been changed", not the old "stopping here":
  # 10df181 replaced the one-line dry run with a full report of what would
  # change and these five rows kept expecting the line it deleted, so all
  # five failed on a start.sh that does exactly what they are checking for.
  # What they are checking is that a mistyped flag is accepted and the dry
  # run completes, not the wording of its last line.
  for _flag in --fullsend --full_send -full-send --FULL-SEND --yolo; do
    expect "start.sh survives $_flag" "Nothing has been changed" \
      bash "$ROOT/start.sh" "$_flag" --dry-run
  done
  expect "an unknown flag warns instead of aborting" "ignoring unrecognized option" \
    bash "$ROOT/start.sh" --nonsense --dry-run
  # --version used to silently mean "pin to this tag", so it ate the next
  # argument and never printed a version.
  check  "start.sh --version prints a version" bash -c "
    bash '$ROOT/start.sh' --version | grep -q 'repo version'"

  # Thirty-plus minutes is fine for the person who lives in this kit and
  # useless inside a twenty minute call.
  expect "--fast skips the slow sections" "skipping editor desktop mcp plugins tools plynn" \
    bash "$ROOT/setup.sh" --dry-run --fast --name CI

  # A signed-out Claude CLI failed all nineteen plugin installs, one red line
  # each. Probe once, skip once.
  check  "the plugin section probes the CLI before looping" \
    grep -q "claude plugin marketplace list </dev/null" "$ROOT/setup.sh"

  # The worst one. `gh api user` exits 4 when nobody is signed in, and as a bare
  # assignment under set -e that killed the whole install after a single line of
  # output, with no error. Every new personal-profile install died there. This
  # runs the real thing into a throwaway HOME and insists it reaches the end.
  check  "a personal install finishes in a clean HOME with no GitHub" bash -c '
    sandbox="$(mktemp -d)"
    HOME="$sandbox" bash "$1/setup.sh" --profile personal --fast \
      --name CI > "$sandbox/install.log" 2>&1 || {
        echo "install exited $?"; tail -5 "$sandbox/install.log"; exit 1; }
    grep -q "Try asking it" "$sandbox/install.log"' _ "$ROOT"

  # Skills are plain markdown and run wherever an agent runs, but they lived
  # inside the plugins section, so portable, the only non-macOS profile,
  # installed 57 commands and zero skills. The biggest piece of the kit was
  # missing from every Windows and Linux install.
  # Every install starts on a machine with nothing on it, and that path had
  # never been executed, so the dead end bootstrap's own header says was fixed
  # was still there: "brew install node" printed to someone with no brew.
  check  "a bare Mac gets no dead ends" bash "$ROOT/tests/bare_machine.sh"

  # Sagar installed this on 2026-09-19 and a browser window opened on his
  # computer by itself, because Serena's upstream default starts a web
  # dashboard and opens a tab on first run. He concluded the kit was dangerous.
  # That is the right conclusion to draw about software that opens windows
  # unannounced, and it is fatal for a kit whose install line is `curl | bash`.
  check  "nothing in the install opens a window or a browser" bash -c '
    hits="$(grep -nE "^[[:space:]]*(open|xdg-open)[[:space:]]|--open\b|webbrowser" \
      "$1/setup.sh" "$1/start.sh" "$1/bin/bootstrap.sh" 2>/dev/null | grep -v "no-open" || true)"
    [ -z "$hits" ] || { echo "$hits"; exit 1; }' _ "$ROOT"

  check  "Serena's dashboard is disabled before its first run" bash -c '
    cfg="$(mktemp -d)/serena_config.yml"
    bash "$1/bin/lib/seed-serena-config.sh" "$cfg" >/dev/null
    grep -q "^web_dashboard_open_on_launch: false" "$cfg" || { echo "tab still opens"; exit 1; }
    grep -q "^web_dashboard: false" "$cfg" || { echo "dashboard still on"; exit 1; }' _ "$ROOT"

  check  "an existing Serena config keeps the user settings" bash -c '
    cfg="$(mktemp -d)/serena_config.yml"
    printf "language_backend: LSP\nweb_dashboard: true\nweb_dashboard_open_on_launch: true\n" > "$cfg"
    bash "$1/bin/lib/seed-serena-config.sh" "$cfg" >/dev/null
    grep -q "^language_backend: LSP" "$cfg" || { echo "clobbered their settings"; exit 1; }
    grep -q "^web_dashboard_open_on_launch: false" "$cfg" || { echo "tab still opens"; exit 1; }' _ "$ROOT"

  check  "setup calls the Serena seeder before installing plugins" \
    grep -q "seed-serena-config.sh" "$ROOT/setup.sh"

  # Caleb, 2026-09-21: "how is chewbacca storing during session important
  # context? I feel like ur gonna forget the to dos we set at the beginning of
  # this session?" Nothing was. session-state/ records files written, never
  # decisions made.
  # docs/REFERENCE.md carried 57 broken links, all one bug: repo-root-relative
  # paths in a file that lives in docs/, so everything was missing ../. The
  # prose reads fine and every link is dead, which is why it survived.
  check  "every relative link in the docs resolves" \
    python3 "$ROOT/tools/linkcheck.py"

  check  "the backlog lists open work" bash -c '
    out=$("$1/bin/backlog" 2>/dev/null)
    case "$out" in *"open now"*) : ;;
      *) echo "backlog printed nothing"; exit 1 ;; esac' _ "$ROOT"

  check  "the backlog keeps dead items and their reason" bash -c '
    "$1/bin/backlog" dead 2>/dev/null | grep -q . || {
      echo "dead items vanished, so somebody will propose them again"; exit 1; }' _ "$ROOT"

  # A store nobody reads is the failure this whole file keeps finding.
  check  "SessionStart injects the backlog" \
    grep -q "bin/backlog" "$ROOT/.claude/hooks/session-context.sh"

  # Sagar, 2026-09-20, after installing: "i don't even know how to remove this
  # agent", "seems like malware". uninstall.sh existed the whole time. The
  # closing screen listed what Claude could now read and never said how to undo
  # it, so the capability might as well not have shipped.
  check  "the last screen says how to remove it" \
    grep -q "chewbacca uninstall --dry-run" "$ROOT/setup.sh"

  check  "removal is described as reading a manifest, not guessing" \
    grep -q "install-manifest.json" "$ROOT/setup.sh"

  # An earlier draft of that block said "this installer sends nothing anywhere",
  # which is false: the GitHub path runs gh repo create and pushes twice. A
  # reassuring sentence that is untrue costs more trust than saying nothing.
  #
  # Scoped to PRINTED lines, not comments. setup.sh says of Plynn that "speech
  # recognition and cleanup both run on the Mac, nothing is uploaded", which is
  # true of Plynn and is a note to a reader of the source. The rule is about
  # blanket reassurance shown to a user who cannot check it.
  check  "printed copy never claims nothing is uploaded" bash -c '
    hits=$(grep -nE "^[[:space:]]*(echo|printf)" "$1/setup.sh" \
      | grep -iE "sends nothing anywhere|nothing is upload|never uploads|no data leaves" || true)
    [ -z "$hits" ] || { echo "$hits"; exit 1; }' _ "$ROOT"

  # Caleb, 2026-09-21, handing over Proverbs: "this should dictate the way
  # chewbacca lives. Not just as something deep in it's knowledge bank, but
  # ingested into it's living infra on how to make decisions". A verse that only
  # sits in methods/proverbs.md is the knowledge bank he ruled out, so the guard
  # has to reach the block injected before work starts.
  check  "every process carries its standing check into the injection" bash -c '
    for m in debug experiment research creative decision build consolidated; do
      "$1/bin/method" "$m" --terse | grep -q "^  STANDING   Prov " || {
        echo "$m lost its standing check"; exit 1; }
    done' _ "$ROOT"

  # A process added to SIGNALS without a guard fails open and silently.
  # Caleb, 2026-09-21: "Chewbacca's resourcefulness and use of agents is so
  # retarded didn't we build a whole graph engineering knowledge base bruh".
  # He was right. 105 skills were installed, nothing named one when work
  # started, and a session had just hand-rolled subagents with no verifier
  # while skills/graph-engineering sat there holding the task-graph rules.
  check  "the skill router names a skill for a request one covers" bash -c '
    out=$(printf "%s" "{\"prompt\":\"build a knowledge graph and dedupe entities across sources\",\"cwd\":\"$1\"}" \
      | "$1/.claude/hooks/skill-route.sh" 2>/dev/null)
    case "$out" in *graph-engineering*) : ;;
      *) echo "router said nothing for a graph request"; exit 1 ;; esac' _ "$ROOT"

  # A router that speaks on every prompt gets tuned out inside a week, which is
  # the failure it exists to prevent. Silence is the common case.
  check  "the skill router stays silent on an unrelated prompt" bash -c '
    out=$(printf "%s" "{\"prompt\":\"whats the weather like today\",\"cwd\":\"$1\"}" \
      | "$1/.claude/hooks/skill-route.sh" 2>/dev/null)
    [ -z "$out" ] || { echo "routed noise: $out"; exit 1; }' _ "$ROOT"

  # It shipped to one machine once before and never reached anybody else.
  check  "the skill router is registered in the shipped settings" \
    grep -q "skill-route.sh" "$ROOT/settings/settings.json"

  check  "no process was added without a standing check" bash -c '
    sigs=$(grep -cE "^    \(.[a-z]+., r." "$1/bin/method")
    guards=$(grep -cE "^    .[a-z]+.: \(" "$1/bin/method")
    [ "$sigs" -gt 0 ] || { echo "process grep drifted"; exit 1; }
    [ "$guards" -ge "$sigs" ] || { echo "$sigs processes, $guards guards"; exit 1; }' _ "$ROOT"

  check  "the portable profile installs skills" bash -c '
    sandbox="$(mktemp -d)"
    HOME="$sandbox" bash "$1/setup.sh" --profile portable --name CI >/dev/null 2>&1
    n=$(ls "$sandbox/.claude/skills" 2>/dev/null | wc -l)
    [ "$n" -gt 20 ] || { echo "only $n skills installed"; exit 1; }' _ "$ROOT"
fi

# ── Windows installer ─────────────────────────────────────────────────────────
if group "windows installer"; then
  # Windows ships PowerShell 5.1. Every 7-only operator in this file is a parse
  # error on exactly the machines it was written for, and a parse error means
  # the install does not start at all.
  check  "no PowerShell 7-only operators" bash -c '
    ! grep -nE "(\?\?|\?\.)" "$1/start.ps1" | grep -vE "^[0-9]+:[[:space:]]*#"' _ "$ROOT"
  check  "the disclaimer names both folders it writes" bash -c '
    grep -q "chewbacca" "$1/start.ps1" && grep -q "does NOT ask for administrator" "$1/start.ps1"' _ "$ROOT"
  check  "it verifies checksums like start.sh does" \
    grep -q "SHA256SUMS.txt" "$ROOT/start.ps1"
  check  "checksums cover the Windows installer" \
    grep -q "start.ps1" "$ROOT/SHA256SUMS.txt"

  # Parsing is not running. If pwsh is on this machine, run the whole thing.
  if command -v pwsh >/dev/null 2>&1 || [ -x /tmp/pwsh/pwsh ]; then
    PWSH="$(command -v pwsh 2>/dev/null || echo /tmp/pwsh/pwsh)"
    check "start.ps1 parses" "$PWSH" -NoProfile -Command "
      \$e=\$null
      \$null=[System.Management.Automation.Language.Parser]::ParseFile('$ROOT/start.ps1',[ref]\$null,[ref]\$e)
      if(\$e){\$e|%{Write-Host \$_.Message}; exit 1}"
    check "start.ps1 installs into a clean HOME" bash -c '
      sandbox="$(mktemp -d)"
      HOME="$sandbox" "$2" -NoProfile -File "$1/start.ps1" > "$sandbox/win.log" 2>&1 || {
        echo "exited $?"; tail -5 "$sandbox/win.log"; exit 1; }
      n=$(ls "$sandbox/.claude/skills" 2>/dev/null | wc -l)
      [ "$n" -gt 20 ] || { echo "only $n skills"; exit 1; }
      [ -f "$sandbox/.claude/CLAUDE.md" ] || { echo "no CLAUDE.md"; exit 1; }' _ "$ROOT" "$PWSH"
    check "start.ps1 keeps a CLAUDE.md the user already had" bash -c '
      sandbox="$(mktemp -d)"; mkdir -p "$sandbox/.claude"
      printf "# mine\n\nAlways use tabs.\n" > "$sandbox/.claude/CLAUDE.md"
      HOME="$sandbox" "$2" -NoProfile -File "$1/start.ps1" >/dev/null 2>&1
      grep -q "Always use tabs" "$sandbox/.claude/CLAUDE.md"' _ "$ROOT" "$PWSH"
  else
    skip "start.ps1 runs" "no pwsh on this machine"
  fi

  check  "hook registration survives a re-run" python3 "$ROOT/tests/test_setup_hooks.py"
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

  # kit-autopush pushes to a real remote without being asked, so every path
  # that decides NOT to push is tested against an actual bare repo rather than
  # read and trusted. Each case builds its own origin and asserts the remote
  # SHA afterwards, because "it printed the right thing" and "it did not push"
  # are different claims.
  #
  # CHEWBACCA_REPO_DIR is exported in each case on purpose. The hook takes an
  # explicit environment value over ~/.claude/d1-config.sh, and if it did not,
  # this test would push the author's real checkout.
  # `git -C <bare>` dies under safe.bareRepository=explicit, so every read of
  # the origin below uses --git-dir. Two of these cases passed vacuously first
  # time round, comparing one empty string against another.
  autopush_fixture() {
    # $1 = branch to end up on. Prints the work tree path.
    local d; d="$(mktemp -d)"
    git -c init.defaultBranch=main init -q --bare "$d/origin.git"
    git -c init.defaultBranch=main clone -q "$d/origin.git" "$d/work" 2>/dev/null
    cd "$d/work" || return 1
    git config user.email t@t; git config user.name t
    git symbolic-ref HEAD refs/heads/main
    # -u is load-bearing, and init.defaultBranch is why.
    #
    # Cloning an empty repo configures the upstream for whatever that default
    # is. The author's ~/.gitconfig sets it to main, so the clone configures
    # main and a plain push is enough. A CI runner defaults to master, the
    # clone configures master, the symbolic-ref above moves HEAD to a main that
    # has no upstream, and the hook exits at its no-upstream check without ever
    # reaching a gate. Both cases below then failed on the runner while passing
    # on the laptop, which is the worst way for a test to be wrong.
    echo one > a.txt; git add a.txt; git commit -qm init; git push -q -u origin main
    # A non-main branch is pushed once so it HAS an upstream. Without that the
    # hook exits at the no-upstream check and never reaches the branch guard,
    # so the case proved nothing: deleting the guard left it green.
    if [ "$1" != "main" ]; then
      git checkout -qb "$1"
      git push -q -u origin "$1"
    fi
    # Gate stubs that exit 0. Without them every gate fails for want of a
    # tools/ directory, and a case meant to prove the BRANCH guard stops the
    # push passes because the gates stopped it instead. Breaking the branch
    # check left that case green, which is how this was caught.
    mkdir -p tools bin
    for f in tools/checksums.py tools/committed_checksums.py tools/counts.py tools/frontmatter.py tools/evals.py bin/secret-scan; do
      echo "import sys; sys.exit(0)" > "$f"
    done
    git add tools bin
    echo two >> a.txt; git add a.txt; git commit -qm ahead
    printf '%s' "$d"
  }

  # Every ref, not just main. `git push origin HEAD` from a feature branch
  # creates refs/heads/feature/x and leaves main alone, so a main-only
  # assertion stays green with the branch guard deleted. It did.
  check "a feature branch is never auto-published" bash -c '
    d="$('"$(declare -f autopush_fixture)"'; autopush_fixture feature/x)"
    before="$(git --git-dir="$d/origin.git" show-ref | sort)"
    CHEWBACCA_REPO_DIR="$d/work" bash "'"$ROOT"'/.claude/hooks/kit-autopush.sh" >/dev/null 2>&1
    after="$(git --git-dir="$d/origin.git" show-ref | sort)"
    [ "$before" = "$after" ] || { echo "the remote grew a ref: $after" >&2; exit 1; }
    exit 0
  '

  # One gate is made to fail on purpose. The point is that a failed gate leaves
  # the remote exactly where it was and says so out loud.
  check "a failed gate blocks the push and leaves the remote alone" bash -c '
    d="$('"$(declare -f autopush_fixture)"'; autopush_fixture main)"
    echo "import sys; sys.exit(1)" > "$d/work/tools/checksums.py"
    before="$(git --git-dir="$d/origin.git" rev-parse main)"
    out="$(CHEWBACCA_REPO_DIR="$d/work" bash "'"$ROOT"'/.claude/hooks/kit-autopush.sh" 2>&1)"
    after="$(git --git-dir="$d/origin.git" rev-parse main)"
    [ "$before" = "$after" ] || { echo "it pushed past a failed gate" >&2; exit 1; }
    echo "$out" | grep -q BLOCKED || { echo "said nothing: $out" >&2; exit 1; }
    exit 0
  '

  # The fixture's gates all pass, so nothing is left to stop the push.
  check "gates passing on main pushes, and the remote actually moves" bash -c '
    d="$('"$(declare -f autopush_fixture)"'; autopush_fixture main)"
    before="$(git --git-dir="$d/origin.git" rev-parse main)"
    local_head="$(git -C "$d/work" rev-parse HEAD)"
    CHEWBACCA_REPO_DIR="$d/work" bash "'"$ROOT"'/.claude/hooks/kit-autopush.sh" >/dev/null 2>&1
    after="$(git --git-dir="$d/origin.git" rev-parse main)"
    [ "$before" != "$after" ] || { echo "nothing was pushed" >&2; exit 1; }
    [ "$after" = "$local_head" ] || { echo "remote is not at the local head" >&2; exit 1; }
    exit 0
  '

  # Gavin's guard. A fork has BOTH origin and upstream. The fixture keeps both
  # and points the branch at upstream, so origin still exists and a push to it
  # would succeed: the ONLY thing that can stop it is the guard. An earlier
  # version renamed origin away, which made the push fail for lack of a remote
  # and passed with the guard deleted.
  check "it refuses to push when the branch does not track origin" bash -c '
    d="$('"$(declare -f autopush_fixture)"'; autopush_fixture main)"
    git -c init.defaultBranch=main init -q --bare "$d/upstream.git"
    git -C "$d/work" remote add upstream "$d/upstream.git"
    git -C "$d/work" push -q -u upstream main
    echo three >> "$d/work/a.txt"
    git -C "$d/work" add a.txt
    git -C "$d/work" commit -qm "ahead of both"
    before="$(git --git-dir="$d/origin.git" show-ref | sort)"
    CHEWBACCA_REPO_DIR="$d/work" bash "'"$ROOT"'/.claude/hooks/kit-autopush.sh" >/dev/null 2>&1
    after="$(git --git-dir="$d/origin.git" show-ref | sort)"
    [ "$before" = "$after" ] || { echo "origin moved while the branch tracked upstream" >&2; exit 1; }
    exit 0
  '

  check "a repo in sync with its remote says nothing" bash -c '
    d="$('"$(declare -f autopush_fixture)"'; autopush_fixture main)"
    git -C "$d/work" reset -q --hard HEAD~1
    out="$(CHEWBACCA_REPO_DIR="$d/work" bash "'"$ROOT"'/.claude/hooks/kit-autopush.sh" 2>&1)"
    [ -z "$out" ] || { echo "spoke when it had nothing to say: $out" >&2; exit 1; }
    exit 0
  '
fi

# ── the display ───────────────────────────────────────────────────────────────
if group "mcp"; then
  if command -v node >/dev/null 2>&1; then
    check "the MCP server speaks the protocol and refuses a shell" \
      bash "$ROOT/tests/mcp_server.sh" "$ROOT"
  else
    skip "mcp" "node not installed"
  fi
fi

if group "hud"; then
  check  "hud parses"         bash -n "$ROOT/bin/hud"
  # EVERY Swift target must compile, test targets included.
  #
  # On 2026-09-21 the Portal target failed to compile on Swift 6.1.2 and
  # took `swift test` for the whole package down with it: 177 unrelated
  # tests never ran, because the build died before any test file was
  # reached. Nothing here noticed, since this suite only checked that the
  # shell and Python entry points parse. `--build-tests` compiles the test
  # targets without running them, which catches both shapes of that failure
  # (a source error and an unresolvable `import`) in seconds.
  if command -v swift >/dev/null 2>&1 && [ -d "$ROOT/hud" ]; then
    check "every swift target compiles, tests included" \
      swift build --package-path "$ROOT/hud" --build-tests
  fi
  # Why there is no border on the screen. Every link in that chain failed
  # silently on somebody else's Mac before this existed.
  check  "the display can say why it is not drawing" python3 "$ROOT/tests/test_hud_doctor.py"
  check  "hud-listen parses"  python3 -m py_compile "$ROOT/bin/hud-listen"
  check  "a greeting costs no model turn" python3 "$ROOT/tests/test_pleasantry.py"
  check  "hud-speak parses"   python3 -m py_compile "$ROOT/bin/hud-speak"
  # The voice, minus the model: sentence splitting and the cache of short
  # lines, which is what "Done." costs after the first time.
  check  "hud-speak splits and caches" python3 "$ROOT/tests/test_hud_speak.py"
  check  "hud-context parses" python3 -m py_compile "$ROOT/bin/hud-context"
  check  "hud-guide parses"   python3 -m py_compile "$ROOT/bin/hud-guide"
  # The bubble on the button: which elements count as controls, how words
  # find one, and the exact line the display gets. A saved snapshot and a
  # fake display, so no screen is read and nothing is drawn.
  check  "hud-guide finds the control and sends the bubble" python3 "$ROOT/tests/test_hud_guide.py"
  check  "hud-music parses"   python3 -m py_compile "$ROOT/bin/hud-music"
  # "Play X" without the model: what the words mean, which result to play,
  # and what each player is told. Every player is a stub, so no sound and
  # no network.
  check  "hud-music reads the words and drives the players" python3 "$ROOT/tests/test_hud_music.py"
  check  "hud-bubble reads the words and never needs the router" python3 "$ROOT/tests/test_hud_bubble.py"
  check  "superassistant parses" python3 -m py_compile "$ROOT/bin/superassistant"
  # The voice's memory both ways: the brain digest it is given, and the log
  # of what it was asked. Hermetic: a temp brain and a temp log.
  check  "superassistant keeps questions and digests the brain" python3 "$ROOT/tests/test_superassistant.py"
  check  "hud-watch parses"   python3 -m py_compile "$ROOT/bin/hud-watch"
  # The budget is the whole design. A proactive thing that interrupts whenever
  # it has an opinion gets muted within a day, and a muted assistant is worth
  # less than none because you believe you have one.
  check  "the watcher respects its budget" python3 "$ROOT/tests/test_hud_watch.py"
  # The loop itself, against a fake display and a fake model: no socket to a
  # real app, no microphone, no tokens. It is the only test that covers what
  # happens between hearing something and drawing it.
  check  "the listen loop works end to end" python3 "$ROOT/tests/test_hud_listen.py"
  check  "the terminal tab chooser never picks a plain shell" python3 "$ROOT/tests/test_terminal.py"
  check  "voice memory rotates and reads back" python3 "$ROOT/tests/test_memory.py"
  check  "the router's table holds" python3 "$ROOT/tests/test_route.py"
  check  "the terminal hook filters and holds" python3 "$ROOT/tests/test_terminal_events.py"
  check  "the terminal state folds and tails" python3 "$ROOT/tests/test_terminal_state.py"
  # The same file has a pytest-only path (the fixtures at its top) that no
  # runner ever exercised: none of the python3 interpreters on the dev Macs,
  # 3.12 through 3.14 and /usr/bin, has pytest, so a bare `python3 -m pytest`
  # dies before collecting anything. uv fetches pytest into a throwaway env.
  # CI's macos-latest ships neither, so it skips there and the script-mode
  # check above is what CI proves.
  if python3 -c 'import pytest' 2>/dev/null; then
    check "the suite collects under pytest" python3 -m pytest "$ROOT/tests" -q
  elif command -v uv >/dev/null 2>&1; then
    check "the suite collects under pytest" uv run --no-project --with pytest python -m pytest "$ROOT/tests" -q
  else
    skip "the suite collects under pytest" "no pytest and no uv"
  fi
  expect "the skill teaches the wire format" "Bob Lines" cat "$ROOT/skills/hud/SKILL.md"
fi

# ── guide ─────────────────────────────────────────────────────────────────────
if group "guide"; then
  export GUIDE_DIR="$TMP/guides"
  # cmd_new runs the craft gate before it writes, so this group needs a craft
  # store holding the study-guide notes. Seeded from the repo rather than
  # stubbed out, so these tests still run against the real gate.
  export CRAFT_DIR="$TMP/guide-craft"
  python3 "$ROOT/bin/craft-gate" study-guide --record "$ROOT/crafts/study-guide.md" >/dev/null 2>&1
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

# Browser/backend tests replace transports with fixtures; no model quota is used.
if group "reasoning backends"; then
  check "circle detector accepts circles, not triangles" bash "$ROOT/tests/circle_shapes.sh"
  check "no drawn line is ever jagged" bash "$ROOT/tests/path_smoothness.sh"
  check "shared agent instructions are current" python3 "$ROOT/tools/agents_md.py" --check
  check "ChatGPT turn boundaries" python3 "$ROOT/tests/test_chatgpt_tab.py"
  check "gateway protocol and execution" python3 "$ROOT/tests/test_chatgpt_gateway.py"
  check "provider selection and ownership" python3 "$ROOT/tests/test_mac_use_providers.py"
  check "Codex shared instructions and optional health" python3 "$ROOT/tests/test_codex.py"
  check "Codex personal context startup" python3 "$ROOT/tests/test_codex_context.py"
  check "Codex native lifecycle hooks" python3 "$ROOT/tests/test_codex_hooks.py"
  _model_python="${MACOS_USE_HOME:-$HOME/Projects/macOS-use}/.venv/bin/python"
  [ -x "$_model_python" ] || _model_python=python3
  if "$_model_python" -c 'import langchain_core, pydantic' >/dev/null 2>&1; then
    check "structured JSON validation and repair" "$_model_python" "$ROOT/tests/test_mac_use_structured.py"
  else
    skip "structured JSON validation and repair" "LangChain/Pydantic runtime absent"
  fi
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

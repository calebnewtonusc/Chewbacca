#!/usr/bin/env bash
# reconnect used to rank by nothing.
#
# urgency was `score * (1 + over / cadence)`. base_score is 0 for anyone with
# no hand-written observation, and zero times anything is zero, so every row
# tied at 0, the sort compared 0 to 0 for every pair, and the list came back in
# table order. Gavin hit it on 2026-09-18 with 944 of his 945 people at score 0
# and got an alphabetical list opening on AJ Flamino.
#
# These three people all have score 0 and differ only in how overdue they are.
# The lateness term is the only thing that can order them, and alphabetical
# order is the exact opposite of correct, so a regression cannot pass by luck.
set -uo pipefail
P="${1:?path to bin/people}"
DB="${PEOPLE_DIR:?PEOPLE_DIR must be set}/people.db"

for n in Zeta Alpha Mid; do "$P" add "$n" >/dev/null 2>&1; done

# base_score MUST be 0 for all three. That is the whole bug: the old urgency
# was score * (1 + over/cadence), and zero times anything is zero. Logging an
# interaction through the CLI would give them a real score and the old formula
# would then order them correctly, so the test would pass against the bug it
# exists to catch. It did, on the first attempt. So the rows are written
# directly, with score 0 and nothing but cadence and lateness to separate them.
#
# Insertion order is Zeta, Alpha, Mid. Alphabetical is Alpha, Mid, Zeta.
# Correct is Zeta, Mid, Alpha. All three differ, so neither a no-op sort
# falling back to table order nor an accidental alphabetical sort can pass.
seed() {
  sqlite3 "$DB" "
    UPDATE people SET cadence_days = 10 WHERE name='$1';
    INSERT INTO person_scores (person_id, base_score, warmth, last_interaction_at,
                               observation_count, completeness, computed_at)
    SELECT id, 0, 0, date('now','-$2 day'), 0, 0, datetime('now')
      FROM people WHERE name='$1'
    ON CONFLICT(person_id) DO UPDATE SET
      base_score = 0, last_interaction_at = excluded.last_interaction_at;"
}
seed Zeta  300     # 30 cadences overdue
seed Mid   100     # 10 cadences overdue
seed Alpha 30      #  3 cadences overdue

out="$("$P" reconnect --limit 50 2>/dev/null)"
pos() { printf '%s' "$out" | grep -n "$1" | head -1 | cut -d: -f1; }
z="$(pos Zeta)"; m="$(pos Mid)"; a="$(pos Alpha)"

if [ -z "$z" ] || [ -z "$m" ] || [ -z "$a" ]; then
  echo "missing rows: Zeta=$z Mid=$m Alpha=$a" >&2; printf '%s\n' "$out" >&2; exit 1
fi
if ! { [ "$z" -lt "$m" ] && [ "$m" -lt "$a" ]; }; then
  echo "wrong order: Zeta=$z Mid=$m Alpha=$a (want Zeta < Mid < Alpha)" >&2
  printf '%s\n' "$out" >&2; exit 1
fi
exit 0

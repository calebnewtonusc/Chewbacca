#!/bin/bash
# list-gate must FAIL on the defects that shipped four times on 2026-09-20,
# and PASS on a clean list. A gate that never fires is decoration.
set -uo pipefail
GATE="$(dirname "$0")/../bin/list-gate"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok()  { printf '  \033[0;32mpass\033[0m  %s\n' "$1"; pass=$((pass+1)); }
no()  { printf '  \033[0;31mfail\033[0m  %s\n' "$1"; fail=$((fail+1)); }

H='record_id,full_name,title,organization,email'
printf '%s\nA1,Jane Roe,Partner,Acme Ventures,jane@acme.com\nA2,John Doe,General Partner,Beta Capital,john@beta.com\n' "$H" > "$TMP/clean.csv"
"$GATE" "$TMP/clean.csv" >/dev/null 2>&1 && ok "clean list passes" || no "clean list should pass"

printf '%s\nB1,Jane Roe,Partner,Acme Ventures,info@acme.com\n' "$H" > "$TMP/role.csv"
"$GATE" "$TMP/role.csv" >/dev/null 2>&1 && no "shared mailbox should fail" || ok "shared mailbox fails"

printf '%s\nC1,Jane Roe,Analyst,Acme Ventures,jane@acme.com\n' "$H" > "$TMP/junior.csv"
"$GATE" "$TMP/junior.csv" >/dev/null 2>&1 && no "junior title should fail" || ok "junior title fails"

printf '%s\nD1,Jane Roe,Partner,Company,jane@acme.com\n' "$H" > "$TMP/placeholder.csv"
"$GATE" "$TMP/placeholder.csv" >/dev/null 2>&1 && no "placeholder org should fail" || ok "placeholder org fails (case-insensitive)"

# one firm under two spellings on one list: the a16z bug
printf '%s\nE1,Jane Roe,Partner,Andreessen Horowitz,jane@a16z.com\nE2,Bob Poe,Partner,Andreessen Horowitz LLC,bob@a16z.com\n' "$H" > "$TMP/firm.csv"
"$GATE" "$TMP/firm.csv" >/dev/null 2>&1 && no "same firm twice should fail" || ok "same firm under two spellings fails"

# same person on two lists: the 2,121 bug
printf '%s\nF1,Jane Roe,Partner,Acme Ventures,jane@acme.com\n' "$H" > "$TMP/l1.csv"
printf '%s\nF1,Jane Roe,Partner,Acme Ventures,jane@acme.com\n' "$H" > "$TMP/l2.csv"
"$GATE" "$TMP/l1.csv" "$TMP/l2.csv" >/dev/null 2>&1 && no "cross-list duplicate should fail" || ok "cross-list duplicate fails"

printf '%s\nG1,Jane Roe,Partner,Ficial Services Ltd,jane@acme.com\n' "$H" > "$TMP/nan.csv"
"$GATE" "$TMP/nan.csv" >/dev/null 2>&1 && no "NaN corruption should fail" || ok "NaN-strip corruption fails"

"$GATE" "$TMP/clean.csv" --expect sequoia >/dev/null 2>&1 && no "recall miss should fail" || ok "recall test fails when an expected firm is absent"

: > "$TMP/empty.csv"
"$GATE" "$TMP/empty.csv" >/dev/null 2>&1 && no "empty file should fail" || ok "empty file fails"

echo "  ${pass} passed, ${fail} failed"
[ "$fail" -eq 0 ]

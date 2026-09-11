#!/usr/bin/env bash
# The shared spine of the live checks.
#
# tests/run.sh is hermetic: temp HOME, temp stores, no real binaries. It proves
# the kit's own logic and it cannot prove the claim that actually matters, which
# is that `mac`, `peekaboo`, `people` and `claude` do on this machine what the
# skills tell Claude they do. doctor.sh asks whether a binary is installed. A
# binary can be installed, on PATH, and refused by TCC every single call.
#
# Three states, and the middle one is the whole point:
#
#   PASS  the real tool did the thing
#   FAIL  the real tool was there and did not
#   SKIP  the tool is absent or unpermitted, so nothing was proven
#
# A SKIP is never a PASS. A suite that quietly turns missing dependencies into
# green is the failure these exist to catch.
#
# Every assertion carries a MUTANT: a variant that breaks the thing the check
# claims to hold up, which must fail. An assertion no mutant can break is
# measuring the weather. `mutant` inverts the sense, so it reads the same way.
#
# Scratch only. A check that writes outside $LIVE_SCRATCH is a bug in the check.

set -uo pipefail

# macOS ships no coreutils `timeout`, and a live check that hangs on a TCC
# prompt blocks CI forever. perl is in the base system on every supported macOS.
lt() { perl -e 'alarm shift; exec @ARGV' "$@"; }
export -f lt

GRN='\033[0;32m'; RED='\033[0;31m'; YEL='\033[0;33m'; DIM='\033[2m'; NC='\033[0m'
_pass=0; _fail=0; _skip=0
CHECK_NAME="$(basename "${BASH_SOURCE[1]:-live}" .sh)"

LIVE_SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/chewbacca-live-$CHECK_NAME-XXXXXX")"
trap 'rm -rf "$LIVE_SCRATCH"' EXIT

# ok <label> <command...>   the command exits 0
ok() {
  local label="$1"; shift
  if "$@" >"$LIVE_SCRATCH/.out" 2>"$LIVE_SCRATCH/.err"; then
    _pass=$((_pass+1)); printf "  ${GRN}PASS${NC}  %s\n" "$label"
  else
    _fail=$((_fail+1)); printf "  ${RED}FAIL${NC}  %s\n" "$label"
    sed 's/^/          /' "$LIVE_SCRATCH/.err" | head -3
  fi
}

# says <label> <needle> <command...>   stdout contains needle
says() {
  local label="$1" needle="$2"; shift 2
  local out; out="$("$@" 2>&1)"
  if printf '%s' "$out" | grep -qF -- "$needle"; then
    _pass=$((_pass+1)); printf "  ${GRN}PASS${NC}  %s\n" "$label"
  else
    _fail=$((_fail+1)); printf "  ${RED}FAIL${NC}  %s  ${DIM}(no '%s')${NC}\n" "$label" "$needle"
    printf '%s' "$out" | sed 's/^/          /' | head -3
  fi
}

# mutant <label> <command...>   the command MUST fail; a pass here means the
# assertion above it proves nothing, because the break did not move it.
mutant() {
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then
    _fail=$((_fail+1))
    printf "  ${RED}FAIL${NC}  mutant survived: %s\n" "$label"
    printf "          ${DIM}the check above it cannot fail, so it is not a check${NC}\n"
  else
    _pass=$((_pass+1)); printf "  ${DIM}mut${NC}   %s ${DIM}(dies, as it must)${NC}\n" "$label"
  fi
}

# need <binary> [hint]   SKIP the whole file when the dependency is absent
need() {
  local bin="$1" hint="${2:-}"
  if ! command -v "$bin" >/dev/null 2>&1; then
    printf "  ${YEL}SKIP${NC}  %s is not on PATH ${DIM}%s${NC}\n" "$bin" "$hint"
    printf "\nSKIPPED  %s\n" "$CHECK_NAME"
    exit 77
  fi
}

# unproven <why>   SKIP mid-file: the tool is here but cannot answer (no TCC
# grant, no display, no data). Not a failure of the kit, and not a pass either.
unproven() {
  _skip=$((_skip+1)); printf "  ${YEL}SKIP${NC}  %s\n" "$1"
}

finish() {
  printf "\n"
  if [ "$_fail" -eq 0 ]; then
    printf "${GRN}%s: %d passed${NC}, %d unproven\n" "$CHECK_NAME" "$_pass" "$_skip"
    exit 0
  fi
  printf "${RED}%s: %d FAILED${NC}, %d passed, %d unproven\n" "$CHECK_NAME" "$_fail" "$_pass" "$_skip"
  exit 1
}

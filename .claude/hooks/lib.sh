#!/usr/bin/env bash
# Shared hook runtime: timing, a log, a watchdog, and an output cap.
#
# Eight hooks ran before every session and none of them left a trace. A hook
# that failed degraded every session silently, a slow one taxed every session
# invisibly, and a chatty one could eat the context window before the user
# typed. Every hook sources this on line 3 and gets all four for free.
#
# Contract for a hook:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" 2>/dev/null || true
#   hook_init <name> [timeout_seconds]
# Everything after that is timed, logged, and killed if it hangs.

CHEWBACCA_LOG_DIR="${CHEWBACCA_LOG_DIR:-$HOME/.chewbacca/logs}"
CHEWBACCA_HOOK_LOG="$CHEWBACCA_LOG_DIR/hooks.log"
# A hook is not allowed to spend more of the user's context than this. The
# session-context hook once emitted an unbounded coursework dump.
CHEWBACCA_HOOK_MAX_BYTES="${CHEWBACCA_HOOK_MAX_BYTES:-8000}"

_hook_ms() { python3 -c 'import time;print(int(time.time()*1000))' 2>/dev/null || echo 0; }

hook_init() {
  _HOOK_NAME="${1:-$(basename "${BASH_SOURCE[1]:-hook}")}"
  _HOOK_TIMEOUT="${2:-10}"
  _HOOK_START="$(_hook_ms)"
  mkdir -p "$CHEWBACCA_LOG_DIR" 2>/dev/null || true

  # Watchdog. A hook that hangs blocks the session with no error and no
  # explanation, which is the worst failure this kit has shipped.
  if [ "$_HOOK_TIMEOUT" -gt 0 ] 2>/dev/null; then
    ( sleep "$_HOOK_TIMEOUT"
      kill -0 $$ 2>/dev/null && {
        _hook_log timeout "killed after ${_HOOK_TIMEOUT}s"
        kill -9 $$ 2>/dev/null
      } ) >/dev/null 2>&1 &
    _HOOK_WATCHDOG=$!
  fi
  trap '_hook_finish $?' EXIT
}

_hook_log() {
  local status="$1" detail="${2:-}" ms=0
  [ -n "${_HOOK_START:-}" ] && ms=$(( $(_hook_ms) - _HOOK_START ))
  printf '%s|%s|%s|%s|%s\n' \
    "$(date '+%Y-%m-%d %H:%M:%S')" "${_HOOK_NAME:-unknown}" "$ms" "$status" "$detail" \
    >> "$CHEWBACCA_HOOK_LOG" 2>/dev/null || true
  # Keep the log from growing without bound. 5000 lines is weeks of sessions.
  if [ -f "$CHEWBACCA_HOOK_LOG" ] && [ "$(wc -l < "$CHEWBACCA_HOOK_LOG" 2>/dev/null || echo 0)" -gt 5000 ]; then
    tail -3000 "$CHEWBACCA_HOOK_LOG" > "$CHEWBACCA_HOOK_LOG.tmp" 2>/dev/null &&
      mv "$CHEWBACCA_HOOK_LOG.tmp" "$CHEWBACCA_HOOK_LOG" 2>/dev/null || true
  fi
}

_hook_finish() {
  local rc="${1:-0}"
  [ -n "${_HOOK_WATCHDOG:-}" ] && kill -9 "$_HOOK_WATCHDOG" 2>/dev/null
  if [ "$rc" -eq 0 ]; then _hook_log ok "${_HOOK_DETAIL:-}"; else _hook_log "exit$rc" "${_HOOK_DETAIL:-}"; fi
}

# Annotate this run's single log line. Calling _hook_log directly logs a second
# row for one run, which made every cache hit look like two hook invocations.
hook_note() { _HOOK_DETAIL="$1"; }

# Print, but never more than the cap. Context the user did not ask for is
# still context the user pays for.
hook_emit() {
  local text; text="$(cat)"
  local n=${#text}
  if [ "$n" -gt "$CHEWBACCA_HOOK_MAX_BYTES" ]; then
    printf '%s' "${text:0:$CHEWBACCA_HOOK_MAX_BYTES}"
    printf '\n\n[%s truncated %s of %s characters to stay inside its context budget]\n' \
      "${_HOOK_NAME:-hook}" "$((n - CHEWBACCA_HOOK_MAX_BYTES))" "$n"
    _hook_log truncated "$n chars"
  else
    printf '%s' "$text"
  fi
}

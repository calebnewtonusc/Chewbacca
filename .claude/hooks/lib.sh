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
  type hook_cache_release >/dev/null 2>&1 && hook_cache_release
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

# A cache with exactly one writer.
#
# On 2026-09-15 at 19:20 five tabs opened in the same second, and eight
# SessionStart hooks were killed by their own watchdogs. Nothing was slow: both
# hooks run in about 0.13s alone. They all missed a cold cache at once and all
# did the identical computation, and the contention is what blew the 5s and 8s
# budgets. Those five tabs started with none of the user's context, which is the
# failure this exists to prevent.
#
#   hook_cache_ready <cache> <ttl_seconds> [source_dir ...]
#     0  serve the file: it is fresh, or it is stale and somebody else is
#        already refreshing it
#     1  this process holds the lock and must recompute
#     2  nothing to serve and somebody else is refreshing; exit quietly
#
# The lock is a directory because mkdir is the only atomic create-or-fail
# primitive portable shell has. It carries its holder's pid, so a lock orphaned
# by the watchdog's kill -9 is reclaimed by the next session instead of wedging
# every session after it.
_hook_cache_fresh() {
  local cache="$1" ttl="$2"; shift 2
  [ "${CHEWBACCA_NO_CACHE:-0}" = "1" ] && return 1
  [ -f "$cache" ] || return 1
  local mt age d
  mt=$(stat -f %m "$cache" 2>/dev/null || stat -c %Y "$cache" 2>/dev/null || echo 0)
  age=$(( $(date +%s) - mt ))
  [ "$age" -lt "$ttl" ] || return 1
  # A context file edited since the cache was written takes effect in the next
  # session rather than whenever the TTL happens to run out.
  for d in "$@"; do
    [ -d "$d" ] || continue
    [ -n "$(find "$d" -newer "$cache" -type f -print -quit 2>/dev/null)" ] && return 1
  done
  return 0
}

hook_cache_ready() {
  local cache="$1" ttl="${2:-900}"; shift 2
  _HOOK_CACHE_LOCK="$cache.lock"
  mkdir -p "$(dirname "$cache")" 2>/dev/null || true

  if _hook_cache_fresh "$cache" "$ttl" "$@"; then
    hook_note "cache hit"
    return 0
  fi

  if [ -d "$_HOOK_CACHE_LOCK" ]; then
    local holder; holder="$(cat "$_HOOK_CACHE_LOCK/pid" 2>/dev/null)"
    if [ -z "$holder" ] || ! kill -0 "$holder" 2>/dev/null; then
      rm -rf "$_HOOK_CACHE_LOCK" 2>/dev/null || true
    fi
  fi

  if mkdir "$_HOOK_CACHE_LOCK" 2>/dev/null; then
    echo $$ > "$_HOOK_CACHE_LOCK/pid" 2>/dev/null || true
    _HOOK_CACHE_HELD=1
    return 1
  fi

  # Another session is computing the identical answer.
  #
  # A stale copy is served at once: it is close enough, and waiting on somebody
  # else to finish is exactly the contention this is here to remove.
  if [ -f "$cache" ]; then
    hook_note "stale, another session is refreshing"
    return 0
  fi

  # No copy at all, which is the genuinely cold start: the first tab of the day,
  # or five opened at once after the cache expired. Exiting here would hand the
  # winner its context and leave every other tab blind, so wait the winner out.
  # The winner takes about a second; this caps at a third of the tightest hook
  # watchdog (5s), so the wait can never be what kills the hook.
  local waited=0 cap="${CHEWBACCA_CACHE_WAIT_MS:-3000}"
  while [ "$waited" -lt "$cap" ]; do
    sleep 0.1
    waited=$((waited + 100))
    if [ -s "$cache" ]; then
      hook_note "waited ${waited}ms for another session to build it"
      return 0
    fi
    # The winner died without writing. Its lock is gone, so take the work over
    # rather than waiting out the full cap for a file nobody is writing.
    if [ ! -d "$_HOOK_CACHE_LOCK" ] && mkdir "$_HOOK_CACHE_LOCK" 2>/dev/null; then
      echo $$ > "$_HOOK_CACHE_LOCK/pid" 2>/dev/null || true
      _HOOK_CACHE_HELD=1
      hook_note "took over after ${waited}ms"
      return 1
    fi
  done
  hook_note "gave up after ${cap}ms"
  return 2
}

hook_cache_release() {
  [ "${_HOOK_CACHE_HELD:-0}" = "1" ] && rm -rf "${_HOOK_CACHE_LOCK:-/nonexistent}" 2>/dev/null
  _HOOK_CACHE_HELD=0
}

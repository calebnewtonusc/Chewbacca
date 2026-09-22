#!/bin/bash
# Timing, logging, a watchdog and an output cap. See lib.sh.
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" 2>/dev/null || true
type hook_init >/dev/null 2>&1 && hook_init load-guard.sh 10
# PreToolUse: HARD BLOCK on fanning out CPU-bound local work onto Caleb's Mac.
#
# Written 2026-09-22. Building a video corpus, this kit ran six local Whisper
# transcriptions at once with `xargs -P 6`. Twenty minutes later Caleb asked
# "Why is my computer so laggy rn". The fifteen-minute load average was 50, and
# two ~1GB mlx_whisper workers then survived the first `pkill` because their
# command line was `python -c "import mlx_whisper"` and the pattern matched the
# parent instead.
#
# He was not annoyed at the work: "Wait I didn't say stop if it ws for good
# reason that's chill". He was annoyed that his machine became unusable while
# he was on it, and that nobody noticed until he said so.
#
# WHY PROSE DID NOT CATCH THIS. The kit's parallelism rule says independent
# calls go in one message and never sequential when parallel works, and it is
# right, because tool calls and subagents are network-bound and close to free.
# Local inference is not that. Six Whisper jobs is six cores, which on a laptop
# is the whole machine. The rule never made the CPU-bound versus IO-bound
# distinction, so following it exactly produced this.
#
# Two ways through, both of which the agent can take itself:
#
#   1. Run it serially at lowest priority, which is what shipped in the end:
#        for x in ...; do nice -n 19 <heavy> "$x"; done
#      Slower in wall clock, invisible to the person using the machine, and it
#      still finishes. A command carrying `nice -n 10` or higher passes.
#
#   2. If the fan-out is genuinely worth the machine, say so out loud first:
#        touch ~/.chewbacca/load-authorized
#      Good for 10 minutes, same shape as submit-guard.
#
# It also refuses heavy local work of ANY width when the machine is already
# under load, because the second job is what turns a slow machine into an
# unusable one.

set -uo pipefail

payload="$(cat)"
tool="$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null)"
[ "$tool" = "Bash" ] || exit 0
cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -n "$cmd" ] || exit 0

lower="$(printf '%s' "$cmd" | tr '[:upper:]' '[:lower:]')"

# Local inference and transcode, the things that actually saturate cores.
# Deliberately NOT a general "python" or "node": this fires on named heavy
# binaries only, so writing a script that happens to mention them is safe.
heavy=0
case "$lower" in
  *whisper*|*mlx_whisper*|*mlx-whisper*|*yt-transcript*|*ffmpeg*|*ollama\ run*\
  |*llama-cli*|*llama-server*|*stable-diffusion*|*comfyui*|*"blender -b"*\
  |*"torch.compile"*|*upscayl*|*handbrakecli*) heavy=1 ;;
esac
[ "$heavy" = 1 ] || exit 0

# Reading about it is not running it. submit-guard learned this the hard way
# when a note ABOUT the rule tripped the rule on its first day.
#
# But the exemption only applies to a command that is ONLY a read. The first
# version keyed on the leading word, and `cat ids.txt | xargs -P 6 -I{}
# yt-transcript {}` starts with cat, so the guard exempted the exact command
# that caused the incident it was written for. A leading verb does not
# describe a pipeline.
if ! printf '%s' "$cmd" | grep -qE '[|;&]|xargs|parallel'; then
  case "$lower" in
    cat\ *|less\ *|head\ *|tail\ *|grep\ *|rg\ *|wc\ *|ls\ *|find\ *|echo\ *) exit 0 ;;
  esac
fi
# A kill is the fix, never the problem.
case "$lower" in
  *pkill*|*killall*|*"kill -"*) exit 0 ;;
esac

# Already being polite? Let it through. nice 10+ yields the machine to whatever
# Caleb is actually doing.
if printf '%s' "$lower" | grep -qE 'nice -n *(1[0-9]|20)'; then exit 0; fi

# Did he authorize the fan-out in the last 10 minutes?
AUTH="$HOME/.chewbacca/load-authorized"
if [ -f "$AUTH" ]; then
  now=$(date +%s)
  then_=$(stat -f %m "$AUTH" 2>/dev/null || stat -c %Y "$AUTH" 2>/dev/null || echo 0)
  [ $((now - then_)) -lt 600 ] && exit 0
fi

# How wide is this? xargs -P N, parallel -j N, or a loop backgrounding with &.
width=1
p=$(printf '%s' "$cmd" | grep -oE '(xargs[^|]*-P *|parallel[^|]*-j *)[0-9]+' | grep -oE '[0-9]+$' | sort -rn | head -1)
[ -n "$p" ] && width="$p"
# `... &` inside a for/while loop is an unbounded fan-out, which is worse than
# a counted one because nothing caps it.
if printf '%s' "$cmd" | grep -qE '(for |while ).*(do|;).*&[[:space:]]*(done|$)'; then
  width=99
fi

# Current machine state. One decimal figure, the 1-minute load average.
load=$(uptime | grep -oE 'load averages?: *[0-9.]+' | grep -oE '[0-9.]+$')
[ -n "$load" ] || load=0
load_int=${load%%.*}
[ -n "$load_int" ] || load_int=0

block=""
if [ "$width" -ge 3 ]; then
  block="width"
elif [ "$load_int" -ge 8 ]; then
  block="load"
fi
[ -n "$block" ] || exit 0

cores=$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 8)

{
  echo "BLOCKED by load-guard: this fans out CPU-bound local work onto the machine Caleb is using."
  echo
  if [ "$block" = "width" ]; then
    if [ "$width" = 99 ]; then
      echo "  Detected: a loop backgrounding heavy jobs with & and nothing capping it."
    else
      echo "  Detected: parallel width $width on $cores cores, running local inference or transcode."
    fi
  else
    echo "  Detected: heavy local work while the 1-minute load average is already $load."
  fi
  echo
  echo "On 2026-09-22 six parallel Whisper jobs took his load average to 50 and he"
  echo "asked why his computer was laggy. The work was fine. Six wide was not."
  echo
  echo "Do one of these instead:"
  echo
  echo "  1. Serial and polite, which is what ended up working:"
  echo "       for x in ...; do nice -n 19 <command> \"\$x\"; done"
  echo "     Slower in wall clock, invisible to him, and it still finishes."
  echo
  echo "  2. If the fan-out is genuinely worth his machine, ask him, then:"
  echo "       touch ~/.chewbacca/load-authorized"
  echo "     Good for 10 minutes."
  echo
  echo "Network-bound work does not need this. Fan out tool calls, subagents and"
  echo "downloads as wide as you like. This is about cores."
} >&2

exit 2

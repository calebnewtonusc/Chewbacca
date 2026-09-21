#!/bin/bash
# UserPromptSubmit hook: when a YouTube link appears in the prompt, tell Claude
# the exact command to read it.
#
# Without this, models fall back to WebFetch (which returns no transcript) or
# claim they cannot watch videos. This makes the capability automatic instead
# of something the user has to remember to ask for.
#
# SHIPPED 2026-09-20 after measuring the gap between this machine and the kit.
# setup.sh already installs yt-transcript (cloned from
# calebnewtonusc/claude-youtube-transcripts) and two shipped files already
# reference it: .claude/rules/research-the-craft.md and
# skills/interface/references/data-loaders.md. The tool arrived, the rules
# mentioned it, and NOTHING surfaced it at the moment a link appeared. This
# hook was the missing third piece and it sat unshipped on one machine.
#
# It carries zero personal references, which is why it ships and why
# application-gate.sh, de-bootcamp-ready.sh and sync-to-d1.sh do not.
#
# Exits silently unless the prompt has a real YouTube URL and the tool is
# actually executable, so it costs nothing on every other turn.

TOOL="$HOME/.local/bin/yt-transcript"

PROMPT="$(jq -r '.prompt // empty' 2>/dev/null)"
[ -z "$PROMPT" ] && exit 0

# Only fire on a real link, not the bare word "youtube".
printf '%s' "$PROMPT" \
  | grep -iqE '(youtube\.com/(watch|shorts/|live/|embed/|v/)|youtu\.be/)' || exit 0

[ -x "$TOOL" ] || exit 0

# Channel and playlist URLs are a bulk job, not a single read.
if printf '%s' "$PROMPT" | grep -iqE 'youtube\.com/(@|c/|channel/|user/|playlist)'; then
  printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"%s"}}' \
    "The prompt contains a YouTube channel or playlist. Use yt-bulk, not WebFetch: \
\`yt-bulk <url> --out ./transcripts\` writes one markdown file per video and is resumable. \
Add --list first to see the scope before fetching. The youtube-transcripts skill has the \
rate-limit rules; read it before any bulk run."
  exit 0
fi

IDS="$(printf '%s' "$PROMPT" \
  | grep -oiE '(v=|/shorts/|/live/|/embed/|/v/|youtu\.be/)[A-Za-z0-9_-]{11}' \
  | grep -oE '[A-Za-z0-9_-]{11}$' \
  | awk '!seen[$0]++' | paste -sd ' ' -)"
[ -z "$IDS" ] && exit 0

CMDS=""
for id in $IDS; do
  CMDS="${CMDS}yt-transcript \\\"$id\\\" --timestamps\\n"
done

printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"%s"}}' \
  "The prompt contains $(printf '%s' "$IDS" | wc -w | tr -d ' ') YouTube link(s). You CAN read \
them. Run this before answering:\\n\\n${CMDS}\\nAdd --whisper if captions fail or are \
disabled. Do NOT WebFetch a YouTube URL and do NOT say you cannot watch videos. Summarize \
rather than reproducing long verbatim stretches."

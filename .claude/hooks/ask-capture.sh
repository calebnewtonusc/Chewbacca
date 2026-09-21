#!/bin/sh
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" 2>/dev/null || true
type hook_init >/dev/null 2>&1 && hook_init ask-capture.sh 3
# Keep every request, so none depends on an agent remembering it.
#
# THE FAILURE THIS EXISTS FOR, 2026-09-21. Caleb: "bro were you ignoring all my
# texts in this chat??? There's so many thing I want you to change and
# implement!" He was not being ignored. Every message was answered. Five of them
# were never written down: NASB95 and the wider Bible ingestion, automating
# prompting so what he says is read as self-learning, reorganising and
# refactoring the files, making the kit an actual graph engineer, and the rest
# of the file audit. An answered request that is not recorded is lost at the end
# of the turn, and the person then has to be the memory.
#
# His conclusion is the design: "Things should NEVER be lost within a chat."
#
# Writes raw, triages never. BACKLOG.md stays curated by hand, because a backlog
# auto-filled with every sentence is one nobody reads, which is the same failure
# in a new coat. This is the inbox; `backlog inbox` shows what has not been
# turned into an item yet.
#
# Silent always. Never blocks, never prints, never fails a turn.

ASK_PAYLOAD=$(cat)
export ASK_PAYLOAD

exec python3 <<'PY'
import json, os, pathlib, time

try:
    payload = json.loads(os.environ.get("ASK_PAYLOAD") or "{}")
except Exception:
    raise SystemExit(0)

prompt = (payload.get("prompt") or "").strip()
if not prompt:
    raise SystemExit(0)

# Machine traffic is not a request, and neither is a slash command the person
# already resolved by typing it.
NOISE = ("SYSTEM NOTIFICATION", "task-notification", "<task-id>",
         "exited with code", "hookSpecificOutput", "Stop hook additional context")
if prompt.startswith("/") or any(m in prompt for m in NOISE):
    raise SystemExit(0)

store = pathlib.Path.home() / ".chewbacca" / "asks.jsonl"
try:
    store.parent.mkdir(parents=True, exist_ok=True)
    # Trim rather than drop: a pasted transcript is still a request, and its
    # first lines are the part that says what was wanted.
    text = prompt if len(prompt) <= 1200 else prompt[:1200] + " ...[trimmed]"
    row = {
        "at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "session": (payload.get("session_id") or "")[:8],
        "cwd": payload.get("cwd") or "",
        "said": text,
    }
    with store.open("a", encoding="utf-8") as fh:
        fh.write(json.dumps(row, ensure_ascii=False) + "\n")
except OSError:
    pass
raise SystemExit(0)
PY

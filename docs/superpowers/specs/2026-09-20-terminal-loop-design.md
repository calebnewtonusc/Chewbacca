# The terminal loop

Voice routing (2026-09-20-voice-routing-design.md) made the terminal a place a
sentence can go. This design makes the terminal a place that talks back: the
voice hears when Claude Code in the remembered tab is waiting on a permission,
answers it, says when a turn finishes, and can stop a run. The HUD shows the
terminal's state in a strip under the pill.

Branch `feat/terminal-loop`, off `feat/voice-routing`.

## Decisions already made

- Only the tab `project.json` remembers counts. Other Claude Code sessions are
  invisible to the loop.
- The voice reads a permission prompt aloud only when Terminal is not the
  frontmost app. When the tab is in front, the strip and the field carry it.
- "Yes" grants one call. "Always" is not a voice word: a standing rule needs
  the keyboard. A misheard word costs one tool call, never a rule.

## Where the events come from

Claude Code hooks, not the session transcript. The transcript format is
documented as internal and changes between versions, and it never records
that a tool call is waiting on permission. Hooks are documented, receive the
session's `cwd` on every event, and a `PermissionRequest` hook may hold the
prompt and return the decision itself (`hookSpecificOutput.decision.behavior`
of `allow` or `deny`, default hook timeout 600 s). Reading the tab's pixels
was the third option; it is brittle and takes focus.

The loop registers one hook for six events: `PermissionRequest`,
`PreToolUse`, `PostToolUse`, `PermissionDenied`, `Stop`, and `SessionEnd`. `Notification`
is not used: its `permission_prompt` fires six seconds after the prompt, and
`PermissionRequest` fires before it.

## The hook

`.claude/hooks/terminal-loop.sh` is a one-line wrapper: `exec chewie
terminal hook`. `chewie` is on PATH after setup and knows its own lib
directory, so the wrapper never has to find the repo. `setup.sh` copies the
wrapper with the other hooks and registers it in `~/.claude/settings.json`
for the six events, empty matcher, `timeout` 45. The Python lives in
`mac/lib/terminal_events.py`, imported by `mac/lib/terminal.py` for the
`hook` verb and by the tests the way they import `terminal.py`.

Every invocation:

1. Read the event JSON from stdin.
2. Load `project.json` from `BOB_MEMORY_DIR` (default `~/.bob/memory`). No
   file, no `cwd` in it, or a `cwd` that is not the event's `cwd` after
   `realpath` on both: exit 0, print nothing. The tab is not ours.
3. Append one line to `$BOB_MEMORY_DIR/terminal-events.jsonl`:
   `{"t": <epoch>, "event": <name>, "tool": <tool_name or "">, "summary":
   <text>, "session": <session_id>, "ask": <ask id or "">, "held": <bool>}`.
   `held` is true only on a `PermissionRequest` the hook is waiting on. Capped at 2000
   lines the way the transcript is capped, rewritten when it passes the cap.
4. For `PermissionRequest`, run the ask protocol below. For everything else,
   exit 0 with no output.

Summaries, capped at 80 characters: a `Bash` call is its command; `Edit`,
`Write`, `Read` are the file's basename; `Agent` is its description; every
other tool is its name. `Stop` carries the first sentence of
`last_assistant_message`, the field the docs recommend over reading the
transcript, which lags.

### The ask protocol

1. Check the frontmost app with one `osascript` call to System Events, two
   second timeout. Terminal in front, or the check fails: append the event
   with `held` false, exit 0 with no output. The tab shows its own prompt
   with no delay, and the strip shows waiting.
2. Otherwise write `$BOB_MEMORY_DIR/asks/<id>.json` with the event's tool,
   input summary, session, and time, then poll for `asks/<id>.answer` every
   0.25 s for `ASK_WAIT_S` (30, guessed: nothing has measured how long a
   person takes to say yes; the hook's own `timeout` of 45 leaves room).
3. An answer file holding `allow` or `deny` becomes the decision JSON on
   stdout, and the ask file is removed. `deny` carries `message` "denied by
   voice" and `interrupt` true when the answer file says `deny stop`.
4. No answer in time: remove the ask file, append `ask_expired`, exit 0 with
   no output. The tab shows its ordinary prompt.

The hook never returns `allow` on its own. Only an answer file written by
hud-listen can.

## hud-listen

### The watcher

A daemon thread tails `terminal-events.jsonl` by byte offset, polling every
0.5 s, and folds events into one `terminal` state on the Listener:

| Event | State |
| --- | --- |
| `PreToolUse` | running, with the summary |
| `PostToolUse`, `PermissionDenied` | running with no tool, until the next event |
| `PermissionRequest`, `held` true | waiting on you (hook holding) |
| `PermissionRequest`, `held` false, or `ask_expired` | waiting on you (tab prompting) |
| `Stop` | done, with the summary |
| `SessionEnd` or no events for ten minutes | idle |

Every state change sends the strip line to the HUD (below). Waiting also
sends `p attention` when nothing of the assistant's own is in flight, which
is the existing blocked-on-you state; no new presence state is added. Done
sends `p done` under the same condition.

### Announcements

On waiting, when Terminal is not in front (one `hud-context` call): the voice
says "The terminal wants to <summary>. Yes or no?" through the existing
speak path, one line, nothing queued. On done, when Terminal is not in
front: "The terminal finished: <summary>." When Terminal is in front the
strip is the whole announcement.

### The answer words

Handled in `ask()` before routing, the way the draft words are, and only
while the state is waiting; otherwise they are ordinary sentences.

- allow: "yes", "yeah", "yep", "go ahead", "allow", "allow it", "do it"
- deny: "no", "nope", "deny", "deny it", "don't"

Hook still holding: write `asks/<id>.answer`. Ask expired, tab prompting:
`chewie terminal answer yes|no --tty <tty>`, which focuses the tab and
presses Return for yes or Escape for no. That path takes focus for as long
as the keypress takes, and it is only reachable while the state is waiting,
so a Return never lands on an input with a draft in it.

### Stop the terminal

"Stop the terminal", "stop in the terminal", "terminal stop", "cancel the
terminal": while an ask is held, write `deny stop`. Otherwise
`chewie terminal interrupt --tty <tty>`, which focuses the tab and presses
Escape, the key Claude Code reads as interrupt. Bare "stop" keeps its
meaning: the assistant's own run.

## chewie terminal

Two verbs added to `mac/lib/terminal.py`, both `--tty`, both refusing under
Secure Input the way the others do:

- `answer yes|no`: focus, then Return or Escape.
- `interrupt`: focus, then Escape.

And `focus`, exposing the existing `focus()` for the strip's click.

## The HUD

One new wire line, parsed in `LineParser.swift` and held on the model:

```
t "<text>" state=running|waiting|done     the terminal strip under the pill
t off                                     hide it
```

Drawn as one thin line in the pill's glass directly under it, hidden when
off, with the state as a leading dot in the palette's existing colours:
acting for running, attention for waiting, done for done. A click sends
`e terminal focus` up the socket, and hud-listen runs `chewie terminal
focus`. The Swift work is the last tasks of the plan; cutting it loses the
strip and nothing else.

## Failure modes

- No `project.json`, no match, a memory dir that cannot be written: the
  hook exits 0 and the tab behaves as it always has.
- hud-listen not running: the hook holds for `ASK_WAIT_S` when Terminal is
  not in front, then the tab prompts. Nothing is granted.
- Two asks in flight: only one ask file is honoured at a time; a second
  `PermissionRequest` while one is held is written with `ask` empty and
  falls through to the tab.
- The remembered tab closed: `ensure` already handles the next draft; the
  watcher goes idle on `SessionEnd`.
- A misheard "yes": one tool call runs that Claude Code was about to ask
  about. The transcript line records the answer with its event.

## Testing

- `tests/test_terminal_events.py`: the `hook` verb's filter (no file, wrong cwd, realpath
  match), summaries per tool, the cap, the ask protocol with a fake front
  check and a temp memory dir: answer within time, answer with stop,
  expiry, Terminal in front skips the hold.
- `tests/test_terminal.py`: the `answer`, `interrupt`, and `focus` verbs
  through the existing osascript stub, and the Secure Input refusals.
- `tests/test_hud_listen.py`: the watcher folds a fixture events file into
  states and sends the `t` lines; the answer words write the answer file
  while waiting and route normally otherwise; the expired path calls the
  stub terminal command with `answer`; "stop the terminal" with and without
  a held ask.
- `hud/Tests`: the `t` line parses, `t off` hides, the model holds the
  state.
- `tests/live/terminal-loop.sh`: opt-in, never run by `tests/run.sh`, opens
  its own tab with `ensure --fresh`, drafts a prompt that runs a harmless
  Bash command, and proves the hook writes the ask and the answer file
  grants it. Takes focus for about thirty seconds.

## Constants

| Name | Value | Evidence |
| --- | --- | --- |
| `ASK_WAIT_S` | 30 | guessed, never measured |
| hook `timeout` | 45 | must exceed `ASK_WAIT_S` plus the front check |
| front check timeout | 2 s | one System Events call takes well under a second on this machine |
| watcher poll | 0.5 s | same cadence as `ensure` |
| events cap | 2000 lines | the transcript's cap is 5000 and holds days of use |
| summary | 80 chars | one pill line |
| idle after | 10 min | matches `WARM_S` in voice memory |

## Out of scope

Reading every session's prompts, "always" by voice, permission rules of any
scope, a done summary written by a model, and anything in Chrome.

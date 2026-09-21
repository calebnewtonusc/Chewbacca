# Voice routing: say the thing, not where it goes

Gavin, 2026-09-20. Approved shape: deterministic first, a small model for the
ambiguous middle, sticky destinations, memory that survives the chat window.

## The problem

Today every spoken sentence goes to one place: the voice agent behind
`hud-listen`. To get words into the Claude Code session in Terminal, or a search
into Chrome, the person has to say where, and the assistant forgets what it was
doing the moment the chat window closes.

The target: a sentence goes to whatever the person is working in, unless it is
obviously a person-shaped act. Nobody says "in terminal" or "in chrome".
Chewbacca reads the screen and its own memory and picks.

## Destinations, to start

| Destination | What arrives there                                                                 | How                                                                                                                              |
| ----------- | ---------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| `terminal`  | a drafted prompt, placed in the Claude Code input and never submitted by Chewbacca | the assistant drafts it, `chewie terminal draft` pastes it into the tab running `claude`, the person presses Return or says send |
| `browser`   | a search or a URL opened in the person's real Chrome                               | `open -a "Google Chrome" <url>`; page reading stays with the assistant, which already gets the page URL from `hud-context`       |
| `assistant` | the existing voice agent with `mac` tools                                          | unchanged path, now with memory in its context                                                                                   |

Other apps are added later by adding a row, not by changing the router.

## The router

A pure function. `route(utterance, context, memory) -> Decision`.

```
Decision = {dest: terminal|browser|assistant, confidence: 0..1, reason: str}
context  = {app, title, selection}            # from hud-context, already collected
memory   = {last: {dest, t}, project: {...}}  # from ~/.bob/memory/
```

Three tiers, cheapest first. Stop at the first that decides.

**Tier 1, correction.** If the sentence is a correction of the previous
decision and the previous decision is under fifteen seconds old: "no, the
terminal", "no, to you", "no, chrome", "other one". Re-route the previous
utterance. If it went to the terminal, the draft is cleared first: nothing was
submitted, so nothing is lost.

**Tier 2, rules.** In order:

1. Person-shaped act -> `assistant`, whatever is on screen. Verbs: text,
   message, call, facetime, remind, email, mail, schedule, book, cancel; time
   and calendar questions; "note that"; any name from `~/.bob/names.txt` in the
   first six words. Confidence 0.95.
2. Continuation while a destination is warm -> that destination. Warm means
   under ten minutes since the last sentence went there. Continuation means the
   sentence opens with "and", "also", "then", "now", "next", or a bare
   imperative with a pronoun object ("make it", "fix that", "add one", "undo
   that"). Confidence 0.85.
3. Frontmost app is a known workspace and nothing above fired -> that
   workspace. Terminal with a `claude` tab -> `terminal`. Chrome -> `browser`.
   Confidence 0.8. **Amended 2026-09-21, see below: the Terminal half now
   also requires the sentence to name something the session owns.**
4. Browser-shaped with no workspace in front: "look up", "search", "google",
   "open <site>", "go to" -> `browser`. Confidence 0.8.

**Tier 3, classifier.** Everything else, and any case where tier 2 rules
disagree (frontmost is Chrome, terminal is warm, sentence is neither a
continuation nor browser-shaped). One `claude -p --model haiku` call, JSON out,
three-second timeout, with the project memory and the last five routed
sentences in the prompt. On timeout or parse failure: the warm destination if
any, else `assistant`. Expected under 800 ms. Expected to fire on a minority of
sentences; measure it. **Amended 2026-09-21: measured, and both halves of that
paragraph were wrong.**

### Amendment, 2026-09-21: the measurement this spec asked for

"Expected under 800 ms, measure it" was the right instruction and the answer is
9.0 to 17.0 seconds. `claude -p --model haiku --output-format json` loads the
user's CLAUDE.md and its eleven imported rules before answering anything, so
one three-word classification billed **35,335 cache-creation tokens and
$0.074**, measured four times from an empty directory with MCP stripped out.
Against a three-second timeout the call could never answer once, and the first
twenty rows of `~/.bob/memory/transcript.jsonl` agree: **8 decisions reading
"classifier timeout", 0 reading "classifier".** Every answer it produced was
paid for and discarded.

So tier 3 ships off. `HUD_CLASSIFY_CMD` still names a command and the tier
comes back the moment something can answer inside the bound; the Claude Code
CLI cannot, and an API call with a 200 token prompt can.

The two model calls are now separate functions, `_classify_cmd` and
`_model_cmd`, and that separation is load-bearing. They shared one, so the
first version of this change switched off the project summary along with the
classifier without a word about it. `summarize` runs the same CLI under a 20
second background budget it can actually meet; the classifier had a three
second one it never could. The budget is what decides, not the command.

Two consequences follow, and both are what the person actually complained
about on 2026-09-21: "assistant is being retarted and trying to just get
things as a draft to put in terminal."

**The fallback is the assistant, never the warm destination.** Warm was a
ratchet: one sentence lands in the terminal, the terminal is warm, and every
sentence the rules cannot settle lands behind it. 4 of those 8 went that way,
including a bare "No". The asymmetry decides it. A sentence sent to the
assistant by mistake comes back as an answer or a question; a sentence sent to
the coding session by mistake comes back as a drafted prompt aimed at somebody
who asked about their calendar.

**The frontmost application is a prior, not a destination.** Rule 3 handed the
terminal every sentence spoken in front of a Claude tab without reading one
word of it, and **8 of the 9 decisions it made were wrong**: a Google sheet for
Valencia, check-in dates, "Create a bubble" three times in different words,
"Terminal", and "No" twice. It now also requires `_work_shaped`, a measured
list of nouns the coding session owns plus a path or filename pattern. Not one
of those eight names anything in it; "write the readme" does. Replaying all
twenty rows through the new router moves 12 decisions, every one of them from
the terminal to the assistant, and leaves the two browser rows and the
person-shaped row alone.

The list is deliberately shorter than a code vocabulary. Words that mean
something else in his life were dropped even though they are ordinary code
words: "class" is a lecture, "route" is the drive to Valencia, "package" is a
delivery, "file" is "file a reminder", "type" is "what type of", "method" is a
payment method, "log" alone is a journal entry. Keeping them reintroduces the
exact bug being fixed, and the losses are absorbed elsewhere: "fix the type
error" is caught by "error", "open the file" by the path pattern, "check the
logs" by the plural.

Measured after the drop: 16 of 16 work sentences reach the terminal and 13 of
13 ordinary ones stay with the assistant, and both sets are rows in
`tests/test_route.py` rather than a number in this paragraph.

The known cost is false negatives on UI work: "add a loading state to the
dashboard", "make the header sticky" and "make the parser handle the format"
name nothing in the list and go to the assistant. That is the trade taken
deliberately. A missed route costs one "no, the terminal", which tier 1 handles
in under fifteen seconds. A wrong route costs a draft typed at somebody who was
asking about their week.

**The general lesson, which is bigger than the router.** The two sentence
classes that hurt most, "play X" and "create a bubble", were both fixed by
giving them a deterministic owner that claims them before the router is ever
asked: `bin/hud-music` and `bin/hud-bubble`, one regex each, no model turn. The
router's job is the genuine residue, and the residue is smaller every time
something takes a class of sentence out of it. Adding vocabulary to an owner
beats adding a rule here.

**Nothing is ever submitted to the terminal by Chewbacca.** A terminal
decision places a draft in the Claude Code input and stops. The person presses
Return, or says "send it", "run it", "confirm", or "go". A wrong route therefore
costs a draft sitting in the wrong place, which "no, to you" clears. The
confidence number is still recorded so the thresholds can be tuned from the
transcript, but no decision hinges on it.

The router lives in `bin/lib/route.py`, imports nothing from `hud-listen`, and
is tested as a table of `(utterance, context, memory) -> dest`.

## Terminal: draft, read, send

A terminal-bound sentence goes through the assistant, not around it. The
assistant says what it is doing in one line, "On it, working in the terminal",
then drafts the prompt and places it. The person reads it in the terminal and
submits it.

The example that set this: "in terminal, begin building a signaler for when my
stock reaches a certain price, draft a prompt." Chewbacca answers "On it,
working in the terminal", opens Claude Code if it is not already open, writes a
proper prompt into its input, and waits. The person presses Return, or says
"send it".

### Drafting

The voice agent receives the sentence with the router's tag, `dest: terminal`,
and the project memory. Its job is the prompt, not the task. Guidance in
`bin/hud-agent.md`:

- A short, specific instruction goes in as said. "Add tests for the parser" is
  already a prompt.
- A vague or large ask is drafted into a prompt Claude Code can act on: what to
  build, where, the constraints the person would state if asked. One paragraph.
  No headings, no code fences, because it is going into a one-line input.
- Say the first line aloud, then place the draft, then say nothing more. The
  draft is on screen; reading it aloud costs the person time.
- Never run `chewie terminal submit` on its own initiative.

### `chewie terminal`, four verbs

`mac/lib/terminal.py`, wrapped by `chewie terminal {tabs,ensure,draft,submit,clear}`.

**`tabs`**: one AppleScript listing every Terminal tab's `tty`, `processes`,
`selected`, and whether its window is front. JSON. Candidates are tabs whose
`processes` include `claude`.

**`ensure [--cwd DIR]`**: makes sure a Claude Code session exists and returns
its tty. If a candidate tab exists, pick it: the one whose tty matches
`project.json`, else the selected tab of the front window if it is a candidate,
else the first. If none exists, open a new Terminal window with
`do script "cd <DIR> && claude"`, poll `tabs` until `claude` appears in its
processes (up to ten seconds), and return it. `DIR` is `--cwd`, else
`project.json`'s `cwd`, else the assistant asks "which folder?" once; a new
project goes in `~/dev/<slug>`, created if needed. `do script` is the right
tool here because this is a shell command and Return is wanted.

**`draft <text> [--tty TTY]`**: places text in the Claude Code input without
submitting. Brings Terminal to the front and selects the tab on purpose: the
person is about to read the draft and press Return there, so the terminal being
in front is the wanted state, not focus theft. Then pastes through
`peekaboo paste`, which restores the previous clipboard. No Return. Newlines in
the draft are collapsed to spaces so the input holds one paragraph. Prints
`{tty, chars}`.

**`submit [--tty TTY]`**: selects the tab if it is not already selected, brings
Terminal front if it is not, presses Return through System Events `key code 36`.
This is the only thing that runs a prompt, and only a person triggers it. It
refuses with exit 3 unless `CHEWIE_TERMINAL_SUBMIT=1` is in its environment:
`hud-listen`'s draft-word path is the only caller that sets it, and only in
answer to a person saying "send it" with a draft outstanding. `bin/hud-agent.md`
still tells the model never to run it, but the gate is what actually stops it.

**`clear [--tty TTY]`**: same focus dance, then Control-U to clear the input.
Used by "scrap that" and by the "no, to you" correction after a draft.

`submit` and `clear`, called from `hud-listen`'s draft-word path, act on the
tty `draft` recorded in `draft.json`, not on whatever tab is
front-and-selected at the moment: that can move between the draft landing and
the person reading it, and "send it" pressing Return in an unreviewed tab is
the exact failure this whole design exists to prevent.

Secure Input: `draft`, `submit` and `clear` all synthesize input to
Terminal, a paste or a keystroke, so `chewie type`'s existing Secure Input
check runs first on all three and the assistant says which app holds it if it
is on.

### Voice words the bridge handles itself

These never reach the model. `hud-listen` matches them when a draft is
outstanding, meaning `draft` ran in the last five minutes and nothing has
submitted or cleared it since:

- submit: "send it", "send", "run it", "run", "confirm", "go", "do it"
- clear: "scrap that", "clear it", "never mind", "cancel that"
- re-route: "no, to you", "not the terminal" clears the draft and hands the
  original sentence to the assistant

If no draft is outstanding these words fall through to normal routing, so
"run" in a sentence about something else is not eaten.

### Verification before building

Two things, by hand, on a throwaway tab running `claude` in an empty temp
directory, never on a live session:

1. `peekaboo paste` of a one-paragraph string lands in the Claude Code input
   intact and does not submit.
2. `key code 36` submits it, and Control-U clears it.

## Delivery to the browser

`open -a "Google Chrome" "https://www.google.com/search?q=<encoded>"` for a
lookup, `open -a "Google Chrome" "<url>"` for an open or go-to. This uses the
person's real profile and logins, needs no bridge and no grant. Anything that
needs the page's content ("summarize this", "what does this say") is
`assistant`, which already receives the frontmost URL and title from
`hud-context` and can call `chewie web read <url>`.

## Memory

Two files under `~/.bob/memory/`, written by `hud-listen`, which already sees
every turn and already writes `~/.bob/names.txt`.

`transcript.jsonl`, one line per utterance:

```
{"t": iso, "via": "voice|typed", "text": ..., "dest": ..., "confidence": ...,
 "reason": ..., "reply": ... | null, "project": <project.name> | null,
 "draft": ... | null, "submitted": true | false | null}
```

`project.json`, the current terminal project:

```
{"tty": "/dev/ttys000", "cwd": ..., "name": ..., "summary": "one line, what
 is being built", "last_sent": iso, "updated": iso}
```

`cwd` comes from the chosen tab's title, which Claude Code sets to the working
directory, with `lsof -p <pid> -Fn | grep cwd` as the check. `name` is the
basename of the repo root if there is one, else of `cwd`. `summary` is
regenerated by a haiku call from the last twenty terminal-bound sentences every
tenth send or at session end, whichever first, and never blocks a send.

Both load on every new chat window and every new `hud-listen` session. The
router gets `project` and the last five routed sentences. The assistant's
context prefix gains one line: "They are building <summary> in <name>; the
terminal is warm" or nothing if there is no project.

Retention: `transcript.jsonl` is capped at 5,000 lines by rotation. Nothing in
it leaves the machine; the classifier prompt includes only the last five
sentences, not the file.

## Feedback in the pill

The pill already carries one line and six phases. A terminal decision shows
`to terminal`; a browser decision shows the label `browser_url` built,
`chrome: <query>` (no "to", since the label already names the destination).
Once a terminal turn is done, if a draft is still outstanding the pill adds
`draft in terminal, say send`. That line holds for as long as the turn's own
`done`/`failed` state does, the ordinary `settle()` hold (`LEAVE_AFTER`, ten
seconds guessed) rather than a separate five-minute timer: the draft itself
is visible in the terminal the whole time it is outstanding, so the pill only
needs to say so once. Assistant-bound sentences show nothing new.

## Changes by file

| File                               | Change                                                                                                                                  |
| ---------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| `bin/lib/route.py`                 | new: the router, pure                                                                                                                   |
| `bin/hud-listen`                   | call the router in `handle()` before dispatch; tag terminal-bound turns; the outstanding-draft words; write memory; drive the pill line |
| `mac/lib/terminal.py`              | new: tab discovery, ensure, draft, submit, clear                                                                                        |
| `mac/bin/chewie`                   | new verb `terminal {tabs,ensure,draft,submit,clear}`                                                                                    |
| `bin/hud-agent.md`                 | the drafting rules, the memory line, never submit                                                                                       |
| `hud/Sources/BobHUDKit/Pill.swift` | only if the existing line op cannot hold a transient message; expected no change                                                        |
| `tests/test_route.py`              | the routing table                                                                                                                       |
| `tests/test_memory.py`             | round-trip and rotation                                                                                                                 |
| `tests/test_terminal.py`           | tab discovery and tab choice against a fixture; paste, submit and clear are manual and opt-in because they open a window                |
| `docs/VOICE-DESIGN.md`             | a section on routing, with the thresholds and why                                                                                       |

## Error handling

- No Claude tab and no known folder: the assistant asks which folder, once.
- `ensure` cannot see `claude` in the new tab within ten seconds: spoken,
  the draft is not placed, transcript records the error.
- `draft` paste fails or Secure Input is on: spoken with the holding app named,
  transcript records `dest: terminal, error: ...`.
- Classifier timeout: warm destination else `assistant`, transcript records
  `reason: "classifier timeout"`.
- Memory unwritable: log and continue; routing degrades to rules plus
  frontmost app, which is most of the value anyway.
- Secure Input on: `draft`, `submit` and `clear` refuse with exit 2 and name
  the holder; `ensure` is unaffected because `do script` is not a keystroke.
- `submit` run without `CHEWIE_TERMINAL_SUBMIT=1`: refuses with exit 3 and
  presses nothing. Only `hud-listen`'s draft-word path sets it.

## Constants, and what set them

- Correction window 15 s: guessed, never measured. Long enough to finish a
  sentence and change your mind, short enough that "no" twenty seconds later
  means something else.
- Outstanding draft 5 min: guessed. After that "send" is a normal word again.
- Ensure poll 10 s: `claude` on this machine shows its prompt in about two
  seconds; ten leaves room for a cold start.
- Warm destination 10 min: guessed. The failure to watch for is a terminal
  sentence sent to Chrome after a long read; lower it if that happens.
- Classifier timeout 3 s: the measured time to first text on the lean session
  is 1.1 to 6.0 s; a routing decision that takes longer than the answer would
  is not worth waiting for. It now bounds an `HUD_CLASSIFY_CMD` somebody sets
  rather than a shipped default, because the default took 9.0 to 17.0 s and
  $0.074 a call. See the amendment above.
- Work-shaped noun list: measured against the nine frontmost-app decisions in
  the transcript on 2026-09-21, eight of which were wrong. Every noun in it is
  there because a sentence that belonged in the terminal used it, or because
  removing it would have lost "write the readme". Nothing was added on a hunch,
  which is why "parser" is missing and known to be a false negative.

## Not in this spec

Reading terminal output back aloud. Reading the draft aloud. Other workspaces beyond Terminal and
Chrome. Multiple Claude sessions in different projects at once, beyond
preferring the remembered tty. A settings UI for the thresholds; they are
constants until measured.

## Testing

`tests/test_route.py` is the contract: every rule above is a row. The
classifier is mocked in tests and exercised once by hand. Terminal paste, submit and
clear are verified once by hand against a throwaway `claude` tab before
anything else is built.

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

| Destination | What arrives there                                             | How                                                                                                                        |
| ----------- | -------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| `terminal`  | the sentence as a prompt to the Claude Code session, submitted | `chewie terminal send`, AppleScript `do script ... in tab` against the tab whose processes include `claude`                |
| `browser`   | a search or a URL opened in the person's real Chrome           | `open -a "Google Chrome" <url>`; page reading stays with the assistant, which already gets the page URL from `hud-context` |
| `assistant` | the existing voice agent with `mac` tools                      | unchanged path, now with memory in its context                                                                             |

Other apps are added later by adding a row, not by changing the router.

## The router

A pure function. `route(utterance, context, memory) -> Decision`.

```
Decision = {dest: terminal|browser|assistant, confidence: 0..1, reason: str, hold: bool}
context  = {app, title, selection}            # from hud-context, already collected
memory   = {last: {dest, t}, project: {...}}  # from ~/.bob/memory/
```

Three tiers, cheapest first. Stop at the first that decides.

**Tier 1, correction.** If the sentence is a correction of the previous
decision and the previous decision is under fifteen seconds old: "no, the
terminal", "no, to you", "no, chrome", "other one". Re-route the previous
utterance. If it already went to the terminal it was submitted and cannot be
recalled; say so instead.

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
   Confidence 0.8.
4. Browser-shaped with no workspace in front: "look up", "search", "google",
   "open <site>", "go to" -> `browser`. Confidence 0.8.

**Tier 3, classifier.** Everything else, and any case where tier 2 rules
disagree (frontmost is Chrome, terminal is warm, sentence is neither a
continuation nor browser-shaped). One `claude -p --model haiku` call, JSON out,
three-second timeout, with the project memory and the last five routed
sentences in the prompt. On timeout or parse failure: the warm destination if
any, else `assistant`. Expected under 800 ms. Expected to fire on a minority of
sentences; measure it.

**Hold.** Any `terminal` decision under 0.7 sets `hold`. A held sentence does
not touch the terminal. The pill shows it with "to the terminal? say send" and
waits fifteen seconds. "Send", "yes", "go" delivers it. "No" or "to you" routes
it to the assistant. Silence drops it and says so. This is the only place the
person is asked, and the threshold is set so it is rare. The reason for holding
rather than delivering without Return: delivering without Return needs focus
theft and synthetic typing, and the research says outbound artifacts get an
Edit, Discard, Send affordance, which the pill already is.

The router lives in `bin/lib/route.py`, imports nothing from `hud-listen`, and
is tested as a table of `(utterance, context, memory) -> dest`.

## Delivery to the terminal

`chewie terminal send <text> [--tab TTY] [--json]`, implemented in
`mac/lib/terminal.py`.

1. Ask Terminal for every tab's `tty`, `processes`, `selected`, and the window's
   `frontmost`, in one AppleScript.
2. Candidate tabs: `processes` contains `claude`. If none: exit 1, "no Claude
   Code session in Terminal", and the router falls back to `assistant` with
   that message spoken.
3. Choose: the tab whose `tty` matches `project.json`; else the selected tab of
   the front window if it is a candidate; else the first candidate.
4. `do script <text> in <tab>`. Never `activate`. Focus stays where it was.
5. Print `{tty, title}` so the transcript records where it went.

The first implementation task is to verify step 4 reaches Claude Code's prompt
when Claude Code is the foreground process, using a throwaway tab running
`cat`, not a live session. If `do script` reaches the shell instead, the
fallback is: `set selected of tab`, `activate`, `chewie type --paste`, key
Return, then re-activate the previous app. That is uglier and steals focus for
a moment, and the spec prefers it not be needed.

Quoting: the text is passed to AppleScript as a string literal with `"` and
`\` escaped. Newlines in the utterance are replaced with spaces; a spoken
sentence has none.

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
 "reason": ..., "reply": ... | null, "project": <project.name> | null}
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

The pill already carries one line and six phases. On a decision it shows
`to terminal: <first six words>` or `to chrome: <query>` for 1.2 seconds before
the normal phase resumes. Assistant-bound sentences show nothing new; that is
today's behavior. A held sentence shows `to the terminal? say send` for the
fifteen-second window.

## Changes by file

| File                               | Change                                                                                                                              |
| ---------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| `bin/lib/route.py`                 | new: the router, pure                                                                                                               |
| `bin/hud-listen`                   | call the router in `handle()` before dispatch; write memory; drive the pill line; hold and correction windows                       |
| `mac/lib/terminal.py`              | new: tab discovery and `do script` delivery                                                                                         |
| `mac/bin/chewie`                   | new verb `terminal {send,tabs}`                                                                                                     |
| `bin/hud-agent.md`                 | one paragraph: the terminal exists, memory line format, never forward a sentence to the terminal itself (the router did or did not) |
| `hud/Sources/BobHUDKit/Pill.swift` | only if the existing line op cannot hold a transient message; expected no change                                                    |
| `tests/test_route.py`              | the routing table                                                                                                                   |
| `tests/test_memory.py`             | round-trip and rotation                                                                                                             |
| `tests/test_terminal.py`           | tab discovery against a fixture; delivery test is manual and opt-in because it opens a window                                       |
| `docs/VOICE-DESIGN.md`             | a section on routing, with the thresholds and why                                                                                   |

## Error handling

- No Claude tab: spoken once, sentence goes to `assistant`.
- `do script` fails: spoken, transcript records `dest: terminal, error: ...`.
- Classifier timeout: warm destination else `assistant`, transcript records
  `reason: "classifier timeout"`.
- Memory unwritable: log and continue; routing degrades to rules plus
  frontmost app, which is most of the value anyway.
- Secure Input on: irrelevant to `do script`; relevant only to the fallback
  typing path, where `chewie type` already warns.

## Constants, and what set them

- Correction window 15 s and hold window 15 s: guessed, never measured. Long
  enough to finish a sentence and change your mind, short enough that "no"
  twenty seconds later means something else.
- Warm destination 10 min: guessed. The failure to watch for is a terminal
  sentence sent to Chrome after a long read; lower it if that happens.
- Hold threshold 0.7: guessed. Measure how often it fires in the first week
  against how often a wrong terminal send happened, and move it.
- Classifier timeout 3 s: the measured time to first text on the lean session
  is 1.1 to 6.0 s; a routing decision that takes longer than the answer would
  is not worth waiting for.

## Not in this spec

Reading terminal output back aloud. Other workspaces beyond Terminal and
Chrome. Multiple Claude sessions in different projects at once, beyond
preferring the remembered tty. A settings UI for the thresholds; they are
constants until measured.

## Testing

`tests/test_route.py` is the contract: every rule above is a row. The
classifier is mocked in tests and exercised once by hand. Terminal delivery is
verified once by hand against a throwaway tab before anything else is built,
because the whole design rests on `do script` reaching the foreground process.

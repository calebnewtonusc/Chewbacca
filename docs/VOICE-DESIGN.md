# How the voice answers, and why

The rules `bin/hud-agent.md` gives the model and the two things `hud listen`
does around it, with where each came from. Read this before changing how the
assistant talks; the prompt is the artifact, this is the reasoning.

## The moment after the key comes up

Three things happen, in this order, and each covers a different gap.

1. **Receipt, at 0 s.** The band moves and the pill shows the sentence the
   moment the press is heard. A 40 ms tone (`Earcon`, "Sound when heard") is
   there for anyone who wants it and off by default: it shipped on, and a day
   of use said a tone on every release is a tone on every sentence. Alexa's
   Brief Mode went the other way for the same reason, replacing spoken
   confirmations with a chime: receipt is a signal, not a sentence.
2. **The model's first sentence, at about 1 s.** Under the lean profile the
   first words arrived 1.0 to 1.7 s after the prompt (2026-09-20). For a task
   that sentence is the acknowledgement on its own, "On it." or a synonym,
   never "Okay" or "Yes" ("I'm tired of it saying yes or ok", 2026-09-20).
   The details are said back only when a mishearing would go somewhere
   wrong: "On it. Texting Caleb you're running ten late."
3. **A filler, only past 2 s.** If the model has said nothing by then, the
   bridge says "On it." for a task or "Let me see." for a question, and the
   model's words queue behind it instead of cutting it off. A bare
   acknowledgement arriving from the model after the filler is not said
   again, so it is "On it." once and never "On it. On it."

The filler threshold is the one number here with real evidence behind it.
Studies of conversational agents from 2019 to 2025 agree that a filler improves
perceived response time once the wait passes roughly two seconds, that quality
of experience degrades past four, and that a filler shaped to the request
("Checking the forecast for Boulder") beats a generic one ("um"). Under two
seconds a filler is talk over the answer. Google Duplex found the same in its
user studies: disfluencies made calls sound more familiar, and quick, simple
utterances needed instant replies while complex ones could take a beat.

## Interrupting

"Make sure if I interrupt the assistant while it's speaking, it stops talking
and doesn't continue the task. It keeps talking over me when I try to speak
while it's working or giving a response from a previous request" (2026-09-20).

Two things were wrong. The voice was cut when the words arrived, which is
seconds after the key went down, so the person spoke over a voice that had
not yet been told to stop. And the cut only reached what was queued: the run
in flight kept writing, and every later sentence was spoken as it landed,
so the answer to the old question came out on top of the new one.

Now the display sends `k down` the moment the talk key goes down, before the
microphone opens, and the bridge stops the voice on that line and mutes the
run in flight: what it goes on to write still reaches the panel, none of it
is said. If nothing is said after the press, that is all that happens. If
words follow, they replace the run: it is ended without a "Stopped", nothing
waits behind it, and the new words start at once. What they most recently
asked for is what they mean, and an answer to the earlier question read out
after the new one would be exactly the talking-over this ends. "Stop" still
stops. A typed request still queues behind a run, because typing interrupts
nobody.

## Confirmation

Google's conversation design guide, which is the most complete published set
of rules from a team that shipped a voice assistant to hundreds of millions of
people, sorts confirmations four ways and the prompt follows it:

- **Implicit confirmation of the details, when a detail could have been
  misheard.** "On it. Dentist, Tuesday at two." A name, a time, an amount, the
  words of a message. Everything else is just done: "On it." then "Chrome's
  up." ("Simplify simple responses", 2026-09-20: the say-back on every task
  was padding.) Never "I heard you say", never a restatement of the yes or no.
- **Implicit confirmation of the action, unless self-evident.** "Sent."
  "Booked." A result said as a result.
- **Explicit confirmation, rarely.** Only before what cannot be undone or costs
  them: sending mail, deleting, calling, paying. One line: "That's the call
  with Caleb at three. Delete it?"
- **No confirmation** when the answer itself shows understanding: "It's one
  thirty-six."

Gavin's own earlier rule stands with it: no cancel window on a spoken request.
Release the key, think, reply, act.

## Long answers go to the hyper bar

The floating pill is "the hyper bar" to the person. A spoken answer is up to
three sentences or three things. A summary, a recap, an explanation, a
comparison or a longer list is written for the panel behind the hyper bar and
not read out; the voice says one sentence that names the topic and points
there: "All the info on the Civil War is ready for you in the hyper bar." Then
a blank line, then the whole answer, written to be read, so headings and lists
are fine there.

The bridge makes the pointer mean it: a spoken sentence that names the hyper
bar ends the spoken part of that block, and a long block that never pointed is
cut at `SPOKEN_CAP` words with "The rest is in the hyper bar." said after it.
The glass holds twenty seconds rather than ten after such a reply, for the
click that opens it. The read-aloud button on an answer in the panel starts
at the answer: the pointer sentence is taken off the front first, because
whoever pressed it has already found the hyper bar.

## Connected to the brain, both ways

The lean profile that makes the voice affordable also cut it off: none of the
person's settings means none of the session briefing, so the voice knew
nothing about who it was talking to, and nothing it was asked went anywhere.
`bin/superassistant` closes both halves. Before every run the bridge rebuilds
the prompt from `hud-agent.md` plus a digest of the second brain (identity,
all of NOW.md, the people, the memory index, and a map of the rest with the
rule to read the file before answering), rewritten only when those files
change. After every run the request and its written answer are appended to
`superassistant/questions.jsonl`, which the session-context hook reads back
into every Claude Code session and `superassistant recent` and `search`
query. Asked for on 2026-09-20: "make sure this application is connected to
chewbacca and has all the current up to date information, vice versa".

It is the person's call, not the bridge's. The panel's header has a switch,
"Speech off for long answers", on by default and kept across launches. Off,
the display sends `e prefer voice long=spoken`, the bridge withholds nothing
from the voice, and every spoken request carries one line telling the model
to read the answer out in full and not point at the hyper bar. The line goes
on every request rather than once, because the pointing rule sits in the
system prompt for every turn and a note said once fades under it. The bridge
is told again whenever it subscribes, so a restart starts right.

Why: speech cannot be skimmed, so every extra spoken sentence is time the
person cannot get back, and Google's VUI brevity principle and Alexa's
one-breath test both say the same thing from the other side. Asked for by
Gavin on 2026-09-20: "when the user asks questions with large summaries that
require a lot of speaking for the assistant, it just says something along the
lines of 'all info on x topic is ready for you in the hyper bar'".

What the voice could learn from its own log, corrections said out loud
included, and why the kit has to do that itself, is
[SELF-LEARNING.md](SELF-LEARNING.md).

## Showing them where

Asked for on 2026-09-20, for somebody who is not the builder: "if a grandma
is trying to fill out information on a page and she's getting stuck, a little
bubble will appear exactly where she needs to click." The voice could already
describe a screen; describing is what a phone call with a relative does, and
it is why those calls take an hour.

`bin/hud-guide` reads the front window's controls through the accessibility
tree peekaboo walks, and puts one mark on the glass with `tone=guide`: a ring
around the control, a bubble above it in words a person would use, a slow
pulse. The display treats that one mark as a control of its own: a click
inside it takes it down and sends `e hit guide label="..."` up the socket,
the bridge relays that to the model marked as coming from the screen rather
than from the person, and the model looks again and shows the next step. The
person follows along without saying a word.

The rules the model guides by, in `hud-agent.md`: one step at a time, in
their words, calling things by the name on the screen; their hands, never the
model's, while guiding; the bubble only ever on request. And the offer, from
the same ask: "if the user is asking a task that you can complete, show them
the highlighted version and then follow up with something like, I can
complete this for you if you want as well, just ask." So when the task is
one the machine section covers, the highlighted step comes first and the
offer once, after it, never per step, and the model acts on it only when
asked, and stops before anything they cannot undo.

The display also notes the app it took focus from, in `~/.bob/front-app`,
because the conversation panel takes key: without that, a typed "where do I
click" had the screen reader reading the panel it was typed into.

## Music without the model

Asked for on 2026-09-20: "tell the assistant to play a song or artist and it
plays almost instantly." The loop as built could already play a song: the
model would hear "play Blinding Lights", write an AppleScript, run it, and
say so, in the two to eight seconds a model turn takes. Almost instantly is
not a model turn.

So "play X", "shuffle X", "pause", "skip", "what's playing" and the volume
never reach the model. `bin/hud-music` owns the vocabulary, one regular expression a
verb, and the bridge asks it first: `parse()` on every utterance, and when
it answers with a command, `perform()` on a worker, the one sentence it
returns spoken, written to the pill, and kept in the superassistant log,
with the glass held on `done` as after any reply. The model sees nothing.
The same file is a command, `hud-music`, so the model can still play music
when the request is wrapped in something else, and so a person can from a
shell.

The players. Where they said ("on YouTube", "in Music") wins. Otherwise
Spotify, when it is installed, and what plays is whatever Spotify's own
search puts at the top for the words. "If the user doesn't speak the
correct name for the song, or the assistant mishears, just play whatever
the top choice is that Spotify pops up when you search it, it's been right
every time" (2026-09-20). With its keys in `~/.bob/spotify.json` that is
one client-credentials search for the URI, then the desktop app told to
play it, under a second; the keys are a Spotify developer app's client id
and secret, which any account can create, no login and no Premium. Without
keys, and that is the normal case, a headless browser (Playwright's
Chromium) loads `open.spotify.com/search/<words>`, which Spotify renders
for anyone, and reads the "Top result" card: the same card the desktop app
shows. Measured 2026-09-20: 1.5 s to start the browser, 1.4 to 2.2 s a
search after that, and the browser is kept for fifteen minutes so the next
request pays only the search. "Freddie again" (the recogniser's hearing of
Fred again..) is Fred again.. to it, "bye-bye by Mac DeMarco" is Baby Bye
Bye, "that song from Barbie" is a Barbie podcast episode, so a podcast at
the top of a music request gives way to the first song row, unless the
words asked for a podcast. Albums are searched with the word on the end,
because "album After Hours by The Weeknd" is the song to Spotify and
"After Hours The Weeknd album" the album. A result is cached a week.

When the page cannot be read (no Playwright, no network), the open sources
stand in: Deezer's search reads the name the way a person says it;
Wikidata (which carries Spotify's own IDs for well-known songs, albums and
artists) or MusicBrainz (which links most artists to their Spotify page)
gives the URI; and for a song Wikidata has no entry for, Spotify's public
embed page for the artist lists their top ten, and the album's page the
rest. Measured 2026-09-20: 0.2 to 1.5 s to the URI, thirteen of fifteen
names found. A tie between a song and an artist of the same name goes to
the artist only with a following ("blinding lights" is also a Deezer
artist with twelve fans). A name nobody has opens the app with the search
on screen, one tap from playing, and the panel says how to do the setup.
That is the fourth version in one afternoon: the first fell through to
YouTube ("play some Mac DeMarco on Spotify" got an invisible stream, "I
can't even find the tab to turn it off"), the second opened the search
("why is it making me tap the top result, it should just play
automatically"), the third guessed from the open sources and sent
anything it was not sure of to the model. Music.app's library when
Spotify is not installed. YouTube when neither is there and `yt-dlp` and
`ffplay` are: the first result's audio with no window, a few seconds in,
no next or previous, and the panel says how to stop it. Each player is
told to stop before another starts.

The model is the last resort, not the reasoning. "Give it reasoning, I
don't want to have to list the exact name of songs and spell them out"
(2026-09-20) was answered for one version by sending described words and
unsure guesses to the model with a hint; the next message made the point
that Spotify's own search already does that reasoning, faster. So only a
request the page could not be read for, and the open sources were not sure
of (below 0.75, which is where "freddie again" came out as Begin Again by
Freddie And The Scenarios), goes to the model, with a hint saying what to
run: `hud-music play --anyway` with the name it works out, one Bash call.
A name never waits on the model when Spotify can be asked.

"Stop" is a stop word, and with the model idle and music playing it is the
music that stops. With a run in flight it is still the run: what they most
recently asked for is what they most likely mean. "Stop the music" is always
the music.

## Sounding like a person

From the same guide, OpenAI's Realtime prompting guide, and Sesame's work on
voice presence, reduced to what a text-only prompt can do (Kokoro has no
prosody control, so the words carry all of it):

- **One breath per sentence.** Speech cannot be skimmed; the longer the floor
  is held the more it costs the listener. Under fifteen words is the norm.
- **Known thing first, new thing last.** "Your next call is at three." The
  end of the sentence is where the ear puts the stress.
- **Contractions always. Times and dates as spoken.** "Three fifteen", "the
  twenty-first". Never an id, a URL or a hash aloud.
- **Sample lines over prose rules.** OpenAI's guide is blunt that the model
  follows example phrases far more closely than descriptions, and Bob's own
  catalog work found the same. The prompt carries a dozen request-to-reply
  pairs and the rotation of acknowledgements.
- **Vary the wording.** The same guide names repetition as the first tell of a
  robot. No two answers open the same way; no acknowledgement twice running.
- **A persona, stated.** Every voice projects one whether designed or not
  (Google Design). Calm, quick, dry, warm, matching the person's register.
- **Hesitate when unsure.** Duplex used hesitant phrasing when its confidence
  was low; Sesame's team calls it embracing imperfection. "I think that's
  Tuesday, checking" is more human and more honest than a confident wrong date.
- **Nothing promotional or instructional.** No "let me know if you need
  anything else", no "you can also ask me to". Speech is for moving forward.

## Where a sentence goes

Since 2026-09-20 a sentence is routed before it is answered. The rules live in
`bin/lib/route.py` and the table that pins them is `tests/test_route.py`; the
design and the evidence are in
`docs/superpowers/specs/2026-09-20-voice-routing-design.md`.

The short version: "in terminal" or "in chrome" at the start wins; a
correction ("no, the terminal") inside fifteen seconds re-routes the last
sentence; a person-shaped act (text, remind, call, a known name) is the
assistant's whatever is on screen; a continuation ("and add tests", "fix
that") follows whichever destination was used in the last ten minutes; a
Claude tab in front takes it only if the sentence names something the coding
session owns; "look up" and "search" go to Chrome; and anything still
unsettled goes to the assistant.

Two of those clauses changed on 2026-09-21 and the amendment in the spec
carries the numbers. The frontmost app used to decide on its own and got
eight of nine decisions wrong. The haiku call used to settle the rest, and it
never once did: it took 9 to 17 seconds against a three-second timeout, at
$0.074 a sentence, so the tier now ships off behind `HUD_CLASSIFY_CMD`.

Nothing is submitted to the terminal by the machine. A terminal sentence
becomes a drafted prompt sitting in Claude Code's input, the pill reads
"draft in terminal, say send", and the person presses Return or says "send
it". "Scrap that" clears it; "no, to you" hands the sentence to the assistant
instead.

Every routed sentence is a line in `~/.bob/memory/transcript.jsonl` with its
destination, confidence, and reason, which is the data for moving any of the
thresholds above. The constants and what set them are listed in the spec.

## The terminal talks back

The tab is not only a place a sentence goes. A Claude Code hook,
`chewie terminal hook`, runs on every tool call, permission prompt, and
finished turn in the remembered tab and writes one line each to
`~/.bob/memory/terminal-events.jsonl`. hud-listen tails it into one state
and shows it as a strip under the pill: running, waiting on you, done.

When the tab stops on a permission and Terminal is not in front, the hook
holds the prompt for thirty seconds and the voice asks: "The terminal wants
to run npm test. Yes or no?" "Yes", "go ahead", or "allow" grants that one
call; "no" or "deny" refuses it. Nothing grants a standing rule by voice:
"always" needs the keyboard, so a misheard word costs one tool call. If
nobody answers in time, the tab shows its ordinary dialog and the same
words press Return or Escape there instead.

When Terminal is in front the voice says nothing: you can see the dialog.
The strip and the ring's attention state carry it.

"Stop the terminal" denies a held prompt with interrupt, or sends Escape to
the tab. A finished turn says one line, the first sentence of the answer,
again only when the tab is not in front.

Setup registers the hook in `~/.claude/settings.json` for six events. Any
session whose folder is not the remembered one is invisible to all of this:
the hook exits before writing anything.

## Measuring it

Every turn writes a `turn:` line to `~/.bob/listen.log` with `text=` (prompt
to first words) and `audio=` (prompt to first sound). The filler logs
`filler: On it.` with its time. If `text=` stays under two seconds for a week,
the filler never fires and can go; if it sits above three, the threshold is
too high and the number above should move, with the new evidence written next
to it.

## Sources

- Google, Conversation design: confirmations
  (developers.google.com/assistant/conversation-design/confirmations)
- Google Design, Speaking the same language: six principles of VUI
  (design.google/library/speaking-the-same-language-vui)
- Google Research, Google Duplex: an AI system for accomplishing real-world
  tasks over the phone (2018)
- OpenAI, Realtime prompting guide (developers.openai.com/cookbook/examples/
  realtime_prompting_guide) and the voice agent metaprompt in
  openai/openai-realtime-agents
- Sesame, Crossing the uncanny valley of conversational voice (2025)
- Mitigating Response Delays in Free-Form Conversations with LLM-powered
  Intelligent Virtual Agents (arXiv 2507.22352, 2025): fillers help in
  high-delay conditions, quality degrades past 4 s
- Behavioral and Symbolic Fillers as Delay Mitigation for Embodied
  Conversational Agents (arXiv 2508.11781, 2025): behavioral fillers preferred
  by 75% over progress indicators
- Don't Just Fill the Silence: Exploring Conversational Filler Strategies in
  Embodied Virtual Agents (ACM TAP, 2025): context-specific fillers beat
  generic ones on rapport and perceived response time
- Stream, Speculative tool calling for voice (2026): the two-track pattern, an
  acknowledgement buys 1.5 to 2 s
- Amazon, Alexa Brief Mode (2018): a chime in place of spoken confirmations
